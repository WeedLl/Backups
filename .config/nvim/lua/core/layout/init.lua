-- ============================================================
-- Переключение системной раскладки.
--
-- Поведение:
--   * Normal/Cmdline/Terminal — английская раскладка;
--   * Insert — та раскладка, с которой пользователь работал в буфере;
--   * при выходе из Insert текущая раскладка запоминается для буфера,
--     после чего включается английская.
--
-- Платформы:
--   * macOS — Carbon TIS через LuaJIT FFI (core/layout/macos.lua),
--     без внешних бинарей; при недоступности FFI — fallback на macism;
--   * Linux — fcitx5, IBus, xkb-switch (X11), g3kb-switch (GNOME);
--     для остальных Wayland-композиторов можно передать свой backend.
--
-- Учитываемые сценарии:
--   * InsertEnter/InsertLeave, включая i_CTRL-O, Ctrl-C и Ctrl-[;
--   * command-line и terminal mode;
--   * FocusLost/FocusGained (в tmux нужен `set -g focus-events on`);
--   * prompt-буферы (Snacks picker/input) принудительно английские,
--     чтобы y/n и команды не превращались в кириллицу;
--   * хранение раскладки per-buffer, чтобы языки не «протекали»
--     между разными файлами.
--
-- Ограничение remote-сценария: при запуске Neovim по SSH меняется
-- раскладка на удалённой машине, а не на локальном клиенте. Для
-- headless/контейнеров без UI автоматика отключается.
--
-- Публичное API:
--   require("core.layout").get() / set(id) / default() / status()
--   require("core.layout").enable() / disable() / toggle()
-- ============================================================

local macos = require("core.layout.macos")
local command = require("core.layout.command")

local M = {}

-- Настройки по умолчанию. Комментарий у каждого пункта — это не
-- украшение: именно эти значения пользователь будет менять чаще всего.
local defaults = {
	-- Полностью включает/выключает автоматику.
	enabled = true,
	-- Реагировать на потерю/получение фокуса окном Neovim.
	focus = true,
	-- Переключать раскладку при входе/выходе из command-line.
	cmdline = true,
	-- Переключать раскладку при входе/выходе из terminal mode.
	terminal = true,
	-- Выставлять английскую раскладку при старте Neovim.
	startup = true,
	-- Выставлять английскую раскладку при выходе из Neovim.
	on_exit = true,
	-- Явный ID английской раскладки. nil = автоопределение.
	-- Примеры: "com.apple.keylayout.ABC", "keyboard-us", "xkb:us::eng", "us".
	default_layout = nil,
	-- Кастомный backend для нестандартной среды (см. core/layout/command.lua).
	backend = nil,
	-- Таймаут внешней команды в миллисекундах. 124 от vim.system = таймаут.
	timeout_ms = 200,
	-- Показывать предупреждения о проблемах с бэкендом.
	notify = true,
}

local opts = vim.tbl_extend("force", {}, defaults)
local state = {
	enabled = true,
	headless = false,
	backend = nil,
	default_id = nil,
	focus_layout = nil,
	insert_active = false,
	cmdline_from_insert = false,
	cmdline_restore = nil,
	disabled_reason = nil,
	warned = {},
}

---Показать предупреждение только один раз за сессию.
-- Без этого сломанная утилита будет писать в :messages на каждый Esc.
---@param key string
---@param message string
---@param level integer|nil
local function notify_once(key, message, level)
	if not opts.notify then
		return
	end
	if state.warned[key] then
		return
	end

	state.warned[key] = true
	vim.notify(message, level or vim.log.levels.WARN)
end

---Neovim запущен без UI (headless/Ex silent/Lua-скрипт).
-- В таких режимах нельзя трогать системную раскладку: это тесты,
-- LSP-скрипты и другие неинтерактивные запуски.
---@return boolean
local function is_headless()
	for _, arg in ipairs(vim.v.argv) do
		if arg == "--headless" or arg == "-es" or arg == "-Es" or arg == "-l" then
			return true
		end
	end
	return false
end

---Прочитать английский layout ID у backend-а.
-- default может быть динамическим (macOS TIS), поэтому вызываем его
-- каждый раз, а не кэшируем навсегда.
---@param backend table|nil
---@return string|nil
local function read_default(backend)
	if not backend or type(backend.default) ~= "function" then
		return nil
	end

	local ok, default = pcall(backend.default)
	if not ok or type(default) ~= "string" or default == "" then
		return nil
	end
	return default
end

---Лениво определить и создать backend.
-- До первого вызова (обычно VimEnter) внешние команды не запускаются,
-- поэтому require("core.layout").setup() не тормозит старт.
---@return table|nil
local function ensure_backend()
	if state.backend then
		return state.backend
	end
	if state.disabled_reason then
		return nil
	end

	local backend
	local err
	local osname = (vim.uv or vim.loop).os_uname().sysname

	if opts.backend then
		-- Пользовательский backend имеет приоритет на любой ОС.
		backend, err = command.custom(opts.backend, opts)
	elseif osname == "Darwin" then
		local loaded, ffi_err = macos.load()
		if loaded then
			backend = {
				name = "macos-tis",
				get = function()
					return macos.current()
				end,
				set = function(id)
					return macos.select(id)
				end,
				default = function()
					return opts.default_layout or macos.default()
				end,
				list = function()
					return macos.list()
				end,
			}
		else
			-- FFI может быть недоступен в нестандартной сборке Neovim.
			-- macism — запасной вариант, но только если он уже установлен.
			backend, err = command.macism(opts)
			if not backend then
				err = "Carbon TIS недоступен (" .. tostring(ffi_err) .. "), macism: " .. tostring(err)
			end
		end
	elseif osname == "Linux" then
		backend, err = command.detect(opts)
	else
		err = "ОС " .. tostring(osname) .. " не поддерживается"
	end

	if not backend then
		state.disabled_reason = err or "не найден поддерживаемый бэкенд"

		local message = "LayoutSwitch: " .. state.disabled_reason
		if osname == "Linux" then
			message = message .. "\nДоступные варианты: " .. command.supported_hint() .. "."
			if command.is_wayland() then
				message = message
					.. '\nДля Wayland без них задайте backend в require("core.layout").setup({...}).'
			else
				message = message
					.. "\nДля X11 можно установить xkb-switch; для нестандартной среды задайте backend в setup()."
			end
		elseif osname == "Darwin" then
			message = message
				.. "\nМожно установить macism или использовать Neovim с LuaJIT."
		end

		notify_once("no_backend", message, vim.log.levels.WARN)
		return nil
	end

	local default = read_default(backend)
	if not default then
		state.disabled_reason = "не удалось определить английскую раскладку"
		notify_once(
			"no_default",
			"LayoutSwitch: не удалось определить английскую раскладку. Задайте default_layout в setup().",
			vim.log.levels.WARN
		)
		return nil
	end

	state.backend = backend
	state.default_id = default
	return backend
end

---Вернуть актуальный английский layout ID.
---@return string|nil
local function get_default()
	local backend = ensure_backend()
	if not backend then
		return nil
	end

	local default = read_default(backend)
	if not default then
		notify_once(
			"no_default_runtime",
			"LayoutSwitch: английская раскладка больше не определяется. Проверьте настройки системы.",
			vim.log.levels.WARN
		)
		return nil
	end

	state.default_id = default
	return default
end

---Безопасно прочитать текущую раскладку.
-- Ошибки backend-а не должны ломать autocmd и не должны спамить.
---@return string|nil
local function safe_get()
	local backend = ensure_backend()
	if not backend then
		return nil
	end

	local ok, id, err = pcall(backend.get)
	if not ok then
		notify_once(
			"get_error",
			"LayoutSwitch: ошибка чтения раскладки: " .. tostring(id),
			vim.log.levels.WARN
		)
		return nil
	end
	if type(id) ~= "string" or id == "" then
		if err then
			notify_once(
				"get_error",
				"LayoutSwitch: не удалось прочитать раскладку: " .. tostring(err),
				vim.log.levels.WARN
			)
		end
		return nil
	end

	return id
end

---Безопасно переключить раскладку.
-- Синхронность важна: при выходе из Insert раскладка должна успеть
-- переключиться до следующего нажатия пользователя.
---@param id string
---@return boolean
local function safe_set(id)
	local backend = ensure_backend()
	if not backend then
		return false
	end

	local ok, result, err = pcall(backend.set, id)
	if not ok then
		notify_once(
			"set_error",
			"LayoutSwitch: ошибка переключения раскладки: " .. tostring(result),
			vim.log.levels.WARN
		)
		return false
	end
	if result ~= true then
		local suffix = err and (": " .. tostring(err)) or ""
		notify_once(
			"set_error",
			"LayoutSwitch: не удалось переключить раскладку" .. suffix,
			vim.log.levels.WARN
		)
		return false
	end

	return true
end

---Переключиться на английскую раскладку.
---@return boolean
local function set_default()
	local default = get_default()
	if not default then
		return false
	end
	return safe_set(default)
end

---Текущий буфер и его per-buffer состояние.
---@return integer
local function current_buf()
	return vim.api.nvim_get_current_buf()
end

---Сохранённая раскладка Insert для буфера.
---@param buf integer
---@return string|nil
local function get_saved(buf)
	local saved = vim.b[buf].layout_switch_saved
	if type(saved) == "string" and saved ~= "" then
		return saved
	end
	return nil
end

---Запомнить раскладку Insert для буфера.
-- Именно per-buffer хранение не даёт русскому языку из одного файла
-- включиться при входе в Insert в другом файле.
---@param buf integer
---@param id string|nil
local function save_layout(buf, id)
	if type(id) == "string" and id ~= "" then
		vim.b[buf].layout_switch_saved = id
	end
end

---Специальные буферы, где раскладка не должна восстанавливаться.
-- prompt — Snacks picker/input, Telescope и т.п.; terminal — :terminal.
---@param buf integer
---@return boolean
local function is_special_buffer(buf)
	local buftype = vim.bo[buf].buftype
	return buftype == "prompt" or buftype == "terminal"
end

---Текущий режим — Insert или Replace.
---@return boolean
local function is_insert_mode()
	local mode = vim.api.nvim_get_mode().mode
	return mode:sub(1, 1) == "i" or mode:sub(1, 1) == "R"
end

---Можно ли сейчас трогать раскладку.
-- Проверяем enabled, headless и наличие UI: в --headless не должно быть
-- системных переключений даже если сработал :startinsert.
---@return boolean
local function active()
	if not state.enabled or state.headless then
		return false
	end
	return #vim.api.nvim_list_uis() > 0
end

---InsertEnter: восстановить язык буфера или запомнить ручной выбор.
-- Если пользователь сам переключился на русский до нажатия i, считаем
-- это осознанным выбором и не затираем сохранённым значением.
local function on_insert_enter()
	if not active() then
		return
	end

	-- Запоминаем, что мы в Insert. Это нужно для command-line, который
	-- открывается прямо из Insert (например, <C-r>=): там InsertLeave
	-- не срабатывает, и после возврата нужно восстановить язык самим.
	state.insert_active = true

	local buf = current_buf()

	-- В prompt/terminal язык всегда английский: иначе y/n и команды
	-- оболочки будут вводиться кириллицей.
	if is_special_buffer(buf) then
		set_default()
		return
	end

	local current = safe_get()
	local default = get_default()

	if current and default and current ~= default then
		save_layout(buf, current)
		return
	end

	local saved = get_saved(buf)
	if saved and saved ~= current then
		safe_set(saved)
	end
end

---InsertLeave: запомнить язык буфера и перейти на английский.
local function on_insert_leave()
	if not active() then
		return
	end

	state.insert_active = false

	local buf = current_buf()

	if is_special_buffer(buf) then
		set_default()
		return
	end

	local current = safe_get()
	if current then
		save_layout(buf, current)
	end

	local default = get_default()
	if not current or not default or current ~= default then
		set_default()
	end
end

---CmdlineEnter: запомнить язык, если command-line открыт из Insert.
-- Обычный `:` из Normal — это просто английская command-line. Но
-- <C-r>= не выходит из Insert: после вставки результата нужно вернуть
-- тот язык, с которым пользователь печатал, иначе кириллица сломается.
local function on_cmdline_enter()
	if not active() then
		return
	end

	state.cmdline_from_insert = state.insert_active
	state.cmdline_restore = state.cmdline_from_insert and safe_get() or nil
	set_default()
end

---CmdlineLeave: вернуть язык Insert или оставить английский.
local function on_cmdline_leave()
	if not active() then
		return
	end

	if state.cmdline_from_insert then
		local restore = state.cmdline_restore
		if restore and restore ~= "" then
			safe_set(restore)
		else
			set_default()
		end
	else
		set_default()
	end

	state.cmdline_from_insert = false
	state.cmdline_restore = nil
end

---Общий обработчик для режимов, где нужен только английский.
local function switch_to_default()
	if not active() then
		return
	end
	set_default()
end

---FocusLost: запомнить раскладку и отдать английскую другим окнам.
local function on_focus_lost()
	if not active() then
		return
	end

	state.focus_layout = safe_get()
	set_default()
end

---FocusGained: в Insert вернуть язык, в остальных режимах — английский.
local function on_focus_gained()
	if not active() then
		return
	end

	local buf = current_buf()
	if is_insert_mode() and not is_special_buffer(buf) and state.focus_layout then
		safe_set(state.focus_layout)
	else
		set_default()
	end
end

---VimEnter: выставить английский, но не мешать :startinsert.
local function on_vim_enter()
	if not active() then
		return
	end
	if vim.api.nvim_get_mode().mode == "n" then
		set_default()
	end
end

---VimLeavePre: не оставлять русскую раскладку в терминале после выхода.
-- Только для интерактивного UI: неинтерактивные запуски не должны
-- менять системную раскладку на выходе.
local function on_vim_leave()
	if not active() then
		return
	end
	set_default()
end

---Публичное чтение текущей раскладки (для интеграций/сниппетов).
---@return string|nil
function M.get()
	return safe_get()
end

---Публичное переключение раскладки.
---@param id string
---@return boolean
function M.set(id)
	if type(id) ~= "string" or id == "" then
		return false
	end
	return safe_set(id)
end

---Публичное получение английского layout ID.
---@return string|nil
function M.default()
	return get_default()
end

---Показать/вернуть состояние модуля.
---@return table
function M.status()
	local backend = ensure_backend()
	local current = backend and safe_get() or nil
	local default = backend and get_default() or nil
	local buf = current_buf()

	local info = {
		enabled = active(),
		headless = state.headless,
		backend = backend and backend.name or "-",
		default = default or state.default_id or "-",
		current = current or "-",
		saved = get_saved(buf) or "-",
		focus = state.focus_layout or "-",
		disabled_reason = state.disabled_reason or "-",
	}

	local lines = {
		"LayoutSwitch: " .. (info.enabled and "включён" or "выключен"),
		"backend: " .. info.backend,
		"default: " .. info.default .. " | current: " .. info.current,
		"буфер: " .. info.saved .. " | focus: " .. info.focus,
	}
	if state.headless then
		lines[#lines + 1] = "режим: headless (переключения отключены)"
	end
	if state.disabled_reason then
		lines[#lines + 1] = "причина: " .. state.disabled_reason
	end

	local message = table.concat(lines, "\n")
	if opts.notify then
		vim.notify(message, vim.log.levels.INFO)
	else
		print(message)
	end

	return info
end

---Включить автоматику заново.
-- Сбрасываем backend, чтобы можно было подхватить только что
-- установленную утилиту без перезапуска Neovim.
---@return boolean
function M.enable()
	if state.headless then
		state.enabled = false
		notify_once(
			"headless",
			"LayoutSwitch: headless-режим, переключения недоступны",
			vim.log.levels.WARN
		)
		return false
	end

	state.enabled = true
	state.disabled_reason = nil
	state.backend = nil
	state.default_id = nil
	set_default()
	return true
end

---Выключить автоматику, по возможности вернув английскую раскладку.
---@return boolean
function M.disable()
	if state.enabled and not state.headless then
		set_default()
	end
	state.enabled = false
	return true
end

---Переключить автоматику.
---@return boolean enabled
function M.toggle()
	if state.enabled then
		M.disable()
	else
		M.enable()
	end
	return state.enabled
end

---Инициализация модуля.
-- Вызывается из init.lua после core.keymaps. До VimEnter внешние
-- команды не запускаются: backend создаётся лениво.
---@param user_opts table|nil
---@return table M
function M.setup(user_opts)
	opts = vim.tbl_extend("force", {}, defaults, user_opts or {})

	-- Переинициализация не должна оставлять старые autocmd'ы/backend.
	state.enabled = opts.enabled ~= false
	state.headless = is_headless()
	state.backend = nil
	state.default_id = nil
	state.focus_layout = nil
	state.insert_active = false
	state.cmdline_from_insert = false
	state.cmdline_restore = nil
	state.disabled_reason = nil
	state.warned = {}

	local group = vim.api.nvim_create_augroup("LayoutSwitch", { clear = true })

	---Зарегистрировать autocmd в группе LayoutSwitch.
	---@param events string|string[]
	---@param callback function
	---@param desc string
	local function au(events, callback, desc)
		vim.api.nvim_create_autocmd(events, {
			group = group,
			callback = callback,
			desc = desc,
		})
	end

	-- Основная логика: вход/выход из Insert.
	au("InsertEnter", on_insert_enter, "LayoutSwitch: восстановить раскладку Insert")
	au(
		"InsertLeave",
		on_insert_leave,
		"LayoutSwitch: запомнить раскладку и включить английскую"
	)

	-- Command-line: : и / должны вводиться латиницей; после выхода
	-- нормальный режим также остаётся английским.
	if opts.cmdline then
		au("CmdlineEnter", on_cmdline_enter, "LayoutSwitch: английская в command-line")
		au("CmdlineLeave", on_cmdline_leave, "LayoutSwitch: вернуть язык после command-line")
	end

	-- Terminal mode: команды оболочки — латиницей; после выхода из
	-- terminal mode normal тоже английский.
	if opts.terminal then
		au("TermEnter", switch_to_default, "LayoutSwitch: английская в terminal mode")
		au("TermLeave", switch_to_default, "LayoutSwitch: английская после terminal mode")
	end

	-- Фокус: при уходе из Neovim отдаём английскую другим приложениям,
	-- при возврате в Insert восстанавливаем язык, с которым работали.
	if opts.focus then
		au("FocusLost", on_focus_lost, "LayoutSwitch: английская при потере фокуса")
		au(
			"FocusGained",
			on_focus_gained,
			"LayoutSwitch: вернуть раскладку при получении фокуса"
		)
	end

	-- Старт и выход. VimEnter откладываем через schedule, чтобы UI уже
	-- существовал и старт Neovim не блокировался внешними командами.
	if opts.startup then
		au("VimEnter", function()
			vim.schedule(on_vim_enter)
		end, "LayoutSwitch: английская при старте")
	end

	if opts.on_exit then
		au("VimLeavePre", on_vim_leave, "LayoutSwitch: английская при выходе")
	end

	-- Пользовательские команды для диагностики и быстрого отключения.
	vim.api.nvim_create_user_command("LayoutSwitchStatus", function()
		M.status()
	end, { force = true, desc = "LayoutSwitch: показать состояние" })

	vim.api.nvim_create_user_command("LayoutSwitchToggle", function()
		M.toggle()
	end, { force = true, desc = "LayoutSwitch: включить/выключить" })

	return M
end

return M
