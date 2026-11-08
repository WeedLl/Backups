-- ============================================================
-- macOS-бэкенд переключения раскладки.
--
-- Использует Carbon Text Input Sources (TIS) через LuaJIT FFI.
-- Это даёт синхронное переключение без внешних бинарников и без
-- Accessibility-разрешений. Если FFI/фреймворки недоступны,
-- core/layout/init.lua попробует fallback на macism.
--
-- Важно: модуль рассчитан на клавиатурные раскладки (ABC/Russian и
-- т.п.). Для экзотических CJK IME может понадобиться macism, который
-- умеет обходить известные проблемы TIS.
-- ============================================================

local M = {}

-- FFI и фреймворки загружаются лениво: сам require("core.layout.macos")
-- не должен ничего делать при старте Neovim.
local ffi
local carbon
local cf
local load_error

-- kCFStringEncodingUTF8: TIS отдаёт CFString, который нужно
-- конвертировать в обычную C-строку.
local UTF8 = 0x08000100

-- CFRunLoopRunInMode возвращает это значение, если обработал источник.
local RUN_LOOP_HANDLED_SOURCE = 4

-- Минимальный набор объявлений TIS/CoreFoundation, необходимый
-- для чтения текущей раскладки, выбора английской и перечисления
-- доступных keyboard input sources.
local CDEF = [[
typedef const void *CFTypeRef;
typedef const struct __CFString *CFStringRef;
typedef const struct __CFArray *CFArrayRef;
typedef struct __TISInputSource *TISInputSourceRef;
typedef long CFIndex;
typedef int32_t OSStatus;

TISInputSourceRef TISCopyCurrentKeyboardInputSource(void);
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void);
CFArrayRef TISCreateInputSourceList(CFTypeRef properties, bool includeAllInstalled);
CFTypeRef TISGetInputSourceProperty(TISInputSourceRef source, CFStringRef key);
OSStatus TISSelectInputSource(TISInputSourceRef source);

extern const CFStringRef kTISPropertyInputSourceID;
extern const CFStringRef kTISPropertyInputSourceCategory;
extern const CFStringRef kTISPropertyInputSourceIsSelectCapable;
extern const CFStringRef kTISCategoryKeyboardInputSource;

CFIndex CFArrayGetCount(CFArrayRef array);
CFTypeRef CFArrayGetValueAtIndex(CFArrayRef array, CFIndex index);
bool CFStringGetCString(CFStringRef str, char *buffer, CFIndex size, uint32_t encoding);
bool CFEqual(CFTypeRef a, CFTypeRef b);
bool CFBooleanGetValue(CFTypeRef boolean);
void CFRelease(CFTypeRef cf);
extern const CFStringRef kCFRunLoopDefaultMode;
int32_t CFRunLoopRunInMode(CFStringRef mode, double seconds, bool returnAfterSourceHandled);
]]

---Лениво загрузить FFI и системные фреймворки.
---@return boolean ok
---@return string|nil err
function M.load()
	if carbon then
		return true
	end
	if load_error then
		return false, load_error
	end

	local ok, err = pcall(function()
		ffi = require("ffi")
		if ffi.os ~= "OSX" then
			error("macOS is required, current OS: " .. ffi.os)
		end

		-- При повторном require типы могут быть уже объявлены, поэтому
		-- cdef выполняем только если TISInputSourceRef ещё не существует.
		if not pcall(ffi.typeof, "TISInputSourceRef") then
			ffi.cdef(CDEF)
		end

		-- Загружаем именно системные фреймворки, а не ищем их по PATH:
		-- так поведение не зависит от окружения пользователя.
		carbon = ffi.load("/System/Library/Frameworks/Carbon.framework/Carbon")
		cf = ffi.load("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
	end)

	if not ok then
		-- Сбрасываем частично загруженные значения, чтобы повторный вызов
		-- не использовал неполное состояние.
		carbon = nil
		cf = nil
		load_error = tostring(err)
		return false, load_error
	end

	return true
end

---Обновить внутренний кэш TIS.
--
-- TIS кэширует текущий input source внутри процесса и обновляет кэш
-- через CFRunLoop-нотификации. Neovim живёт в libuv, а не в CFRunLoop,
-- поэтому без этого ручное переключение раскладки пользователем может
-- остаться незамеченным до следующего события.
local function refresh()
	for _ = 1, 16 do
		if cf.CFRunLoopRunInMode(cf.kCFRunLoopDefaultMode, 0, true) ~= RUN_LOOP_HANDLED_SOURCE then
			break
		end
	end
end

---Преобразовать TISInputSourceRef в строковый ID.
-- Владелец source остаётся у вызывающего; здесь ничего не освобождаем.
---@param source TISInputSourceRef|nil
---@return string|nil
local function source_id(source)
	if source == nil then
		return nil
	end

	local value = carbon.TISGetInputSourceProperty(source, carbon.kTISPropertyInputSourceID)
	if value == nil then
		return nil
	end

	local buffer = ffi.new("char[256]")
	if not cf.CFStringGetCString(ffi.cast("CFStringRef", value), buffer, 256, UTF8) then
		return nil
	end
	return ffi.string(buffer)
end

---Взять ownership у результата TIS*Copy* и сразу освободить его.
-- TISCopy* возвращает объект, которым владеет вызывающий, поэтому
-- CFRelease обязателен, иначе получим утечку на каждом событии.
---@param source TISInputSourceRef|nil
---@return string|nil
local function copied_source_id(source)
	if source == nil then
		return nil
	end

	local id = source_id(source)
	cf.CFRelease(source)
	return id
end

---Выполнить fn для каждого доступного input source.
-- fn возвращает true, если обход нужно прекратить.
---@param fn fun(source: TISInputSourceRef): boolean|nil
local function each_source(fn)
	local list = carbon.TISCreateInputSourceList(nil, false)
	if list == nil then
		return
	end

	-- pcall нужен, чтобы гарантированно освободить CFArray даже если
	-- внутри fn возникнет ошибка Lua.
	local ok, err = pcall(function()
		local count = tonumber(cf.CFArrayGetCount(list))
		for i = 0, count - 1 do
			local source = ffi.cast("TISInputSourceRef", cf.CFArrayGetValueAtIndex(list, i))
			if fn(source) then
				break
			end
		end
	end)

	cf.CFRelease(list)
	if not ok then
		error(err)
	end
end

---ID текущего input source.
---@return string|nil
function M.current()
	if not M.load() then
		return nil
	end
	refresh()
	return copied_source_id(carbon.TISCopyCurrentKeyboardInputSource())
end

---ID текущей ASCII-совместимой клавиатурной раскладки.
-- На практике при активной русской раскладке это ABC/US: именно
-- эту раскладку нужно включать в Normal режиме.
---@return string|nil
function M.default()
	if not M.load() then
		return nil
	end
	refresh()
	return copied_source_id(carbon.TISCopyCurrentASCIICapableKeyboardLayoutInputSource())
end

---Выбрать input source по строковому ID.
---@param id string
---@return boolean
function M.select(id)
	if type(id) ~= "string" or id == "" then
		return false
	end
	if not M.load() then
		return false
	end

	refresh()
	local selected = false
	each_source(function(source)
		if source_id(source) == id then
			-- TISSelectInputSource возвращает OSStatus: 0 — успех.
			selected = carbon.TISSelectInputSource(source) == 0
			return true
		end
	end)

	return selected
end

---Список доступных selectable keyboard layouts.
---@return string[]
function M.list()
	local ids = {}
	if not M.load() then
		return ids
	end

	refresh()
	each_source(function(source)
		local category = carbon.TISGetInputSourceProperty(source, carbon.kTISPropertyInputSourceCategory)
		local selectable = carbon.TISGetInputSourceProperty(source, carbon.kTISPropertyInputSourceIsSelectCapable)

		if
			category ~= nil
			and cf.CFEqual(category, carbon.kTISCategoryKeyboardInputSource)
			and selectable ~= nil
			and cf.CFBooleanGetValue(selectable)
		then
			local id = source_id(source)
			if id then
				table.insert(ids, id)
			end
		end
	end)

	return ids
end

return M
