-- ============================================================
-- Командные бэкенды переключения раскладки.
--
-- Здесь собраны:
--   * Linux-адаптеры: fcitx5, IBus, X11 xkb-switch, GNOME g3kb-switch;
--   * fallback для macOS через внешний macism;
--   * декларативный custom-бэкенд для Wayland-композиторов, которые
--     не покрыты стандартными утилитами (Hyprland, Sway, KDE и т.п.).
--
-- Все команды запускаются списком аргументов через vim.system, без shell.
-- Это исключает проблемы с пробелами/кавычками и случайную инъекцию.
-- ============================================================

local M = {}

-- vim.system синхронно ждёт процесс; таймаут нужен, чтобы сломанная
-- утилита не подвесила Neovim на событии InsertLeave/InsertEnter.
local DEFAULT_TIMEOUT_MS = 200

---Запустить команду и вернуть её stdout.
-- cmd может быть списком argv или Lua-функцией (для custom-бэкенда).
---@param cmd string[]|fun(): string|nil
---@param timeout_ms number|nil
---@return boolean ok
---@return string|nil out
---@return string|nil err
function M.run(cmd, timeout_ms)
	if type(cmd) == "function" then
		local ok, result = pcall(cmd)
		if not ok then
			return false, nil, tostring(result)
		end
		if result == nil or result == false then
			return false, nil, "команда не вернула значение"
		end
		return true, tostring(result), nil
	end

	if type(cmd) ~= "table" or #cmd == 0 then
		return false, nil, "пустая команда"
	end

	-- pcall на случай, если vim.system недоступен или получил
	-- некорректный argv (например, из кастомного конфига).
	local spawn_ok, proc = pcall(vim.system, cmd, { text = true })
	if not spawn_ok then
		return false, nil, tostring(proc)
	end

	local wait_ok, result = pcall(function()
		return proc:wait(timeout_ms or DEFAULT_TIMEOUT_MS)
	end)
	if not wait_ok then
		return false, nil, tostring(result)
	end

	-- Код 124 приходит от vim.system по таймауту. Для нас это такая же
	-- ошибка, как и ненулевой exit code: раскладка не переключилась.
	if result.code ~= 0 then
		local err
		if result.code == 124 then
			err = "таймаут команды (" .. tostring(timeout_ms or DEFAULT_TIMEOUT_MS) .. " мс)"
		else
			err = result.stderr
			if not err or err == "" then
				err = "exit code " .. tostring(result.code)
			end
		end
		return false, nil, vim.trim(err)
	end

	return true, vim.trim(result.stdout or ""), nil
end

---Разбить stdout утилиты на непустые строки.
---@param out string|nil
---@return string[]
local function split_lines(out)
	local lines = {}
	for line in (out or ""):gmatch("[^\r\n]+") do
		line = vim.trim(line)
		if line ~= "" then
			table.insert(lines, line)
		end
	end
	return lines
end

-- Описание Linux-адаптеров.
--
-- Порядок в этом списке не задаёт приоритет: приоритет задаётся в
-- linux_order() ниже, потому что он зависит от X11/Wayland.
local LINUX_ADAPTERS = {
	fcitx5 = {
		name = "fcitx5",
		bin = "fcitx5-remote",
		get_cmd = { "fcitx5-remote", "-n" },
		set_cmd = function(id)
			return { "fcitx5-remote", "-s", id }
		end,
		default_id = "keyboard-us",
	},
	ibus = {
		name = "ibus",
		bin = "ibus",
		get_cmd = { "ibus", "engine" },
		set_cmd = function(id)
			return { "ibus", "engine", id }
		end,
		default_id = "xkb:us::eng",
	},
	["xkb-switch"] = {
		name = "xkb-switch",
		bin = "xkb-switch",
		get_cmd = { "xkb-switch" },
		set_cmd = function(id)
			return { "xkb-switch", "-s", id }
		end,
		-- xkb-switch не знает, какая раскладка «английская», поэтому
		-- выбираем её из списка по префиксу us/en.
		default_from_list = {
			cmd = { "xkb-switch", "-l" },
			patterns = { "^us", "^en" },
		},
		list_cmd = { "xkb-switch", "-l" },
	},
	["g3kb-switch"] = {
		name = "g3kb-switch",
		bin = "g3kb-switch",
		get_cmd = { "g3kb-switch", "-p" },
		set_cmd = function(id)
			return { "g3kb-switch", "-s", id }
		end,
		-- g3kb-switch печатает человекочитаемые названия групп.
		default_from_list = {
			cmd = { "g3kb-switch", "-l" },
			patterns = { "^English", "^US" },
		},
		list_cmd = { "g3kb-switch", "-l" },
	},
}

---Определить английский layout ID для адаптера.
-- Приоритет: явная настройка пользователя -> известный ID -> список.
---@param adapter table
---@param opts table
---@return string|nil id
---@return string|nil err
local function resolve_default(adapter, opts)
	if type(opts.default_layout) == "string" and opts.default_layout ~= "" then
		return opts.default_layout
	end

	if adapter.default_id then
		return adapter.default_id
	end

	if adapter.default_from_list then
		local ok, out, err = M.run(adapter.default_from_list.cmd, opts.timeout_ms)
		if not ok then
			return nil, err
		end

		for _, line in ipairs(split_lines(out)) do
			for _, pattern in ipairs(adapter.default_from_list.patterns) do
				if line:match(pattern) then
					return line
				end
			end
		end

		return nil, "не найдена английская раскладка в " .. adapter.name
	end

	return nil, "не задана английская раскладка"
end

---Проверить, что адаптер установлен и реально отвечает.
---@param adapter table
---@param opts table
---@return table|nil probed
---@return string|nil err
local function probe_adapter(adapter, opts)
	if vim.fn.executable(adapter.bin) ~= 1 then
		return nil, adapter.bin .. " не установлен"
	end

	local ok, out, err = M.run(adapter.get_cmd, opts.timeout_ms)
	if not ok then
		return nil, err
	end
	if out == "" then
		return nil, adapter.name .. " вернул пустой ответ"
	end

	-- Некоторые утилиты печатают ошибку в stdout, но завершаются с кодом 0.
	local lower = out:lower()
	if lower:find("error", 1, true) or lower:find("failed", 1, true) then
		return nil, out
	end

	local default, default_err = resolve_default(adapter, opts)
	if not default then
		return nil, default_err
	end

	return { adapter = adapter, default_id = default }
end

---Собрать backend-объект из описания адаптера.
-- Наружу отдаём единый интерфейс get/set/default/list, чтобы init.lua
-- не зависел от конкретной утилиты.
---@param adapter table
---@param default_id string
---@param opts table
---@return table
local function make_backend(adapter, default_id, opts)
	local timeout = opts.timeout_ms

	local function get()
		local ok, out, err = M.run(adapter.get_cmd, timeout)
		if not ok then
			return nil, err
		end
		if out == "" then
			return nil, "пустой ответ от " .. adapter.name
		end
		return out
	end

	local function set(id)
		if type(id) ~= "string" or id == "" then
			return false, "пустой layout ID"
		end

		local cmd = adapter.set_cmd(id)
		local ok, _, err = M.run(cmd, timeout)
		if not ok then
			return false, err
		end
		return true
	end

	local function list()
		if not adapter.list_cmd then
			return nil
		end
		local ok, out = M.run(adapter.list_cmd, timeout)
		if not ok then
			return nil
		end
		return split_lines(out)
	end

	return {
		name = adapter.name,
		get = get,
		set = set,
		default = function()
			return default_id
		end,
		list = list,
	}
end

---Определить, что сессия работает через Wayland.
-- WAYLAND_DISPLAY — основной признак; XDG_SESSION_TYPE нужен для
-- окружений, где переменная дисплея не проброшена в дочерний процесс.
---@return boolean
function M.is_wayland()
	local display = vim.env.WAYLAND_DISPLAY
	local session = (vim.env.XDG_SESSION_TYPE or ""):lower()
	return (display ~= nil and display ~= "") or session == "wayland"
end

---Порядок Linux-адаптеров с учётом X11/Wayland.
-- В Wayland xkb-switch работает через XWayland и может менять не ту
-- раскладку, поэтому его не рассматриваем. На X11 он основной.
---@return string[]
local function linux_order()
	local order = { "fcitx5", "ibus" }

	if M.is_wayland() then
		order[#order + 1] = "g3kb-switch"
	else
		order[#order + 1] = "xkb-switch"
		-- g3kb-switch — запасной вариант для GNOME/X11, если xkb-switch нет.
		order[#order + 1] = "g3kb-switch"
	end

	return order
end

---Автоматически выбрать Linux-бэкенд.
---@param opts table
---@return table|nil backend
---@return string|nil err
function M.detect(opts)
	local uv = vim.uv or vim.loop
	if uv.os_uname().sysname ~= "Linux" then
		return nil, "командные бэкенды поддерживаются только на Linux"
	end

	local errors = {}
	for _, name in ipairs(linux_order()) do
		local adapter = LINUX_ADAPTERS[name]
		local probed, err = probe_adapter(adapter, opts)
		if probed then
			return make_backend(probed.adapter, probed.default_id, opts)
		end
		errors[#errors + 1] = name .. ": " .. tostring(err)
	end

	-- Возвращаем общую причину плюс детали: init.lua добавит к ней
	-- подсказку, какие утилиты можно установить или настроить.
	return nil,
		"не найден поддерживаемый переключатель ("
			.. table.concat(errors, "; ")
			.. ")"
end

---Короткая подсказка для сообщения об отсутствии Linux-бэкенда.
---@return string
function M.supported_hint()
	return "fcitx5-remote, ibus, xkb-switch (X11) или g3kb-switch (GNOME)"
end

---Fallback для macOS: внешний macism.
-- Используется только если Carbon TIS/FFI почему-то недоступны.
---@param opts table
---@return table|nil backend
---@return string|nil err
function M.macism(opts)
	if vim.fn.executable("macism") ~= 1 then
		return nil, "macism не установлен"
	end

	local default
	if type(opts.default_layout) == "string" and opts.default_layout ~= "" then
		default = opts.default_layout
	else
		default = "com.apple.keylayout.ABC"
	end

	local adapter = {
		name = "macism",
		bin = "macism",
		get_cmd = { "macism" },
		set_cmd = function(id)
			return { "macism", id }
		end,
	}

	return make_backend(adapter, default, opts)
end

---Собрать декларативный custom-бэкенд.
--
-- Пример для нестандартного Wayland-композитора:
--
--   backend = {
--     name = "my-wm",
--     get = function()
--       return vim.trim(vim.fn.system({ "my-layout-tool", "get" }))
--     end,
--     set = function(id)
--       return vim.system({ "my-layout-tool", "set", id }):wait(200).code == 0
--     end,
--     default = "us",
--   }
--
-- get/set/default могут быть также списками argv. Для set список
-- дополняется id в конец: { "my-layout-tool", "set" } -> ... set <id>.
---@param spec table
---@param opts table
---@return table|nil backend
---@return string|nil err
function M.custom(spec, opts)
	if type(spec) ~= "table" then
		return nil, "backend должен быть таблицей"
	end
	if spec.get == nil or spec.set == nil then
		return nil, "custom backend должен содержать get и set"
	end

	local timeout = opts.timeout_ms

	local function get()
		if type(spec.get) == "function" then
			local ok, id = pcall(spec.get)
			if not ok then
				return nil, tostring(id)
			end
			if type(id) ~= "string" then
				return nil, "custom get не вернул layout ID"
			end
			id = vim.trim(id)
			if id == "" then
				return nil, "custom get не вернул layout ID"
			end
			return id
		end

		local ok, out, err = M.run(spec.get, timeout)
		if not ok then
			return nil, err
		end
		if out == "" then
			return nil, "custom get вернул пустую строку"
		end
		return out
	end

	local function set(id)
		if type(id) ~= "string" or id == "" then
			return false, "пустой layout ID"
		end

		if type(spec.set) == "function" then
			local ok, result = pcall(spec.set, id)
			if not ok then
				return false, tostring(result)
			end
			if result == false then
				return false, "custom set вернул false"
			end
			return true
		end

		-- Копируем argv, чтобы не мутировать таблицу из пользовательского
		-- конфига при каждом вызове.
		local cmd = {}
		for _, value in ipairs(spec.set) do
			cmd[#cmd + 1] = value
		end
		if #cmd == 0 then
			return false, "custom set: пустая команда"
		end
		cmd[#cmd + 1] = id

		local ok, _, err = M.run(cmd, timeout)
		if not ok then
			return false, err
		end
		return true
	end

	local function default()
		if type(spec.default) == "function" then
			local ok, id = pcall(spec.default)
			if ok and type(id) == "string" then
				id = vim.trim(id)
				if id ~= "" then
					return id
				end
			end
			return nil
		end
		if type(spec.default) == "string" then
			local id = vim.trim(spec.default)
			if id ~= "" then
				return id
			end
		end
		if type(opts.default_layout) == "string" and opts.default_layout ~= "" then
			return opts.default_layout
		end
		return nil
	end

	local default_id = default()
	if not default_id then
		return nil, "custom backend: не задана английская раскладка"
	end

	local function list()
		if type(spec.list) == "function" then
			local ok, ids = pcall(spec.list)
			if ok and type(ids) == "table" then
				return ids
			end
			return nil
		end
		if type(spec.list) == "table" then
			local ok, out = M.run(spec.list, timeout)
			if not ok then
				return nil
			end
			return split_lines(out)
		end
		return nil
	end

	return {
		name = spec.name or "custom",
		get = get,
		set = set,
		default = function()
			return default_id
		end,
		list = list,
	}
end

return M
