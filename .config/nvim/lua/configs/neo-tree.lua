local neo_tree = require("neo-tree")

-- Флаг: показывать ли количество строк.
-- Выключено по умолчанию: подсчёт не выполняется вообще,
-- пока пользователь явно не включит его комбинацией клавиш.
vim.g.neo_tree_show_lines = false

-- Кэш: path -> count
local line_count_cache = {}

-- Асинхронный подсчёт через внешний wc -l (или find на Windows).
-- Не блокирует UI даже на многомегабайтных файлах.
local function get_line_count_async(path, callback)
	local cmd
	if vim.fn.has("win32") == 1 then
		cmd = { "cmd", "/c", "find", "/c", "/v", '""', path }
	else
		cmd = { "wc", "-l", path }
	end

	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if not data or not data[1] then
				return
			end
			local count
			if vim.fn.has("win32") == 1 then
				count = tonumber(data[1]:match("(%d+)%s*$"))
			else
				count = tonumber(data[1]:match("^%s*(%d+)"))
			end
			if count then
				callback(count)
			end
		end,
		on_stderr = function() end,
	})
end

neo_tree.setup({
	sources = { "filesystem", "buffers", "git_status" },
	filesystem = {
		filtered_items = {
			visible = true,
			hide_dotfiles = false,
			hide_gitignored = false,
		},
		follow_current_file = { enabled = true },
		use_libuv_file_watcher = true,

		-- Кастомный компонент: рендерит количество строк только когда
		-- флаг включён. Иначе возвращает {}, и место под него не резервируется.
		components = {
			line_count = function(config, node, _)
				if not vim.g.neo_tree_show_lines or node.type ~= "file" then
					return {}
				end

				local path = node:get_id()
				local cached = line_count_cache[path]

				if cached then
					return {
						text = " " .. cached .. "L",
						highlight = config.highlight or "NeoTreeDimText",
					}
				end

				-- Ещё не посчитано — запускаем фоновое задание
				-- и на этот кадр показываем заглушку.
				get_line_count_async(path, function(count)
					line_count_cache[path] = count
					vim.schedule(function()
						require("neo-tree.sources.filesystem.commands").refresh(
							require("neo-tree.sources.manager").get_state("filesystem")
						)
					end)
				end)

				return {
					text = " ...",
					highlight = config.highlight or "NeoTreeDimText",
				}
			end,
		},

		-- Рендерер файла: имя слева, количество строк справа
		renderers = {
			file = {
				{ "indent" },
				{ "icon" },
				{
					"container",
					width = "100%",
					content = {
						{ "name", zindex = 10 },
						{ "line_count", zindex = 20, align = "right" },
					},
				},
			},
		},

		window = {
			mappings = {
				["L"] = "toggle_line_count",
			},
		},
	},

	window = { width = 30 },

	-- Пользовательская команда: переключает флаг, сбрасывает кэш
	-- (чтобы данные были свежими) и перерисовывает дерево.
	commands = {
		toggle_line_count = function(state)
			vim.g.neo_tree_show_lines = not vim.g.neo_tree_show_lines

			if vim.g.neo_tree_show_lines then
				line_count_cache = {}
			end

			local status = vim.g.neo_tree_show_lines and "включено" or "выключено"
			vim.notify("Количество строк: " .. status, vim.log.levels.INFO)

			require("neo-tree.sources.manager").refresh(state)
		end,
	},
})

vim.keymap.set("n", "<C-n>", function()
	vim.cmd("Neotree toggle")
end, { desc = "Toggle file tree" })
