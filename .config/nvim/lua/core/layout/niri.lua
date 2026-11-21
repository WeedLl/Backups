-- ============================================================
-- niri-бэкенд переключения раскладки (Linux/Wayland).
--
-- niri сам хранит список раскладок и текущий индекс; Neovim не может
-- прочитать это напрямую, поэтому ходим в IPC niri:
--   niri msg --json keyboard-layouts -> { names = {...}, current_idx = N }
--   niri msg action switch-layout <index>
--
-- Почему отдельный модуль, а не адаптер в command.lua:
-- command.lua описывает простые CLI-утилиты в стиле «одна команда —
-- один ID». niri отдаёт JSON и адресует раскладку индексом, поэтому
-- парсинг ответа и сопоставление имён живут здесь, рядом с macos.lua.
--
-- Наружу отдаём имена раскладок ("English (US)", "Russian"), а не
-- индексы: они стабильнее при переупорядочивании и читаемы в
-- :messages. set() принимает и имя, и числовой индекс.
-- ============================================================

local M = {}

local DEFAULT_TIMEOUT_MS = 200

---Запустить niri с таймаутом и вернуть stdout.
---@param args string[]
---@param timeout_ms number|nil
---@return string|nil out
---@return string|nil err
local function run(args, timeout_ms)
	local ok, proc = pcall(vim.system, args, { text = true })
	if not ok then
		return nil, tostring(proc)
	end

	local wait_ok, result = pcall(function()
		return proc:wait(timeout_ms or DEFAULT_TIMEOUT_MS)
	end)
	if not wait_ok then
		return nil, tostring(result)
	end

	if result.code ~= 0 then
		local err = result.stderr
		if not err or err == "" then
			err = "exit code " .. tostring(result.code)
		end
		return nil, vim.trim(err)
	end

	return vim.trim(result.stdout or ""), nil
end

---Прочитать список раскладок и текущий индекс.
---@param timeout_ms number|nil
---@return string[]|nil names
---@return integer|nil current_idx
---@return string|nil err
local function read_layouts(timeout_ms)
	local out, err = run({ "niri", "msg", "--json", "keyboard-layouts" }, timeout_ms)
	if not out then
		return nil, nil, err
	end

	local ok, data = pcall(vim.json.decode, out)
	if not ok or type(data) ~= "table" or type(data.names) ~= "table" then
		return nil, nil, "niri вернул неожиданный JSON"
	end

	local names = {}
	for _, name in ipairs(data.names) do
		if type(name) == "string" and name ~= "" then
			table.insert(names, name)
		end
	end

	local idx = tonumber(data.current_idx)
	if #names == 0 or not idx or idx < 0 or idx >= #names then
		return nil, nil, "niri вернул некорректный список раскладок"
	end

	return names, idx, nil
end

---Найти индекс раскладки по имени или числовому ID.
---@param names string[]
---@param id string
---@return integer|nil index  ноль-based, как в niri
local function find_index(names, id)
	local numeric = tonumber(id)
	if numeric and numeric >= 0 and numeric < #names then
		return numeric
	end

	for i, name in ipairs(names) do
		if name == id then
			return i - 1
		end
	end

	local lower = id:lower()
	for i, name in ipairs(names) do
		if name:lower() == lower then
			return i - 1
		end
	end

	return nil
end

---Найти английскую раскладку по имени.
---@param names string[]
---@return string|nil name
local function find_english(names)
	for _, name in ipairs(names) do
		local lower = name:lower()
		if lower:match("^english") or lower:match("^us") or lower:match("^en") then
			return name
		end
	end

	return nil
end

---Собрать backend для core/layout.
-- Ошибка возвращается, если niri недоступен или IPC не отвечает;
-- init.lua тогда пробует command.detect() как раньше.
---@param opts table
---@return table|nil backend
---@return string|nil err
function M.backend(opts)
	local timeout = opts.timeout_ms or DEFAULT_TIMEOUT_MS
	local names, _, err = read_layouts(timeout)
	if not names then
		return nil, err
	end

	local default = opts.default_layout
	if type(default) ~= "string" or default == "" then
		default = find_english(names) or names[1]
	end

	-- get/set/list намеренно читают IPC каждый раз, а не кэшируют:
	-- пользователь может переключить раскладку мышью/виджетом niri,
	-- и кэш стал бы врать при возврате в Normal.
	local function get()
		local current_names, current_idx, read_err = read_layouts(timeout)
		if not current_names then
			return nil, read_err
		end
		return current_names[current_idx + 1]
	end

	local function set(id)
		if type(id) ~= "string" or id == "" then
			return false, "пустой layout ID"
		end

		local current_names, current_idx, read_err = read_layouts(timeout)
		if not current_names then
			return false, read_err
		end

		local target = find_index(current_names, id)
		if target == nil then
			return false, "раскладка не найдена: " .. id
		end
		if target == current_idx then
			return true
		end

		local _, switch_err = run(
			{ "niri", "msg", "action", "switch-layout", tostring(target) },
			timeout
		)
		if switch_err then
			return false, switch_err
		end
		return true
	end

	local function list()
		local current_names = read_layouts(timeout)
		return current_names
	end

	return {
		name = "niri",
		get = get,
		set = set,
		default = function()
			return default
		end,
		list = list,
	}
end

return M
