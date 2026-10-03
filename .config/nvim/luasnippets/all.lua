local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep

return {
  -- Markdown-таблица
  s({trig = "c", dscr = "Kolonka"},
    fmta([=[| <> | <> |
|----|----|
| <> | <> |]=], { i(1), i(2), i(3), i(4) })
  ),

  -- Добавление пути в начало (высокий приоритет)
  s({trig = "ifpathb", dscr = "If not in PATH or FPATH"},
    fmta([=[if [[ ":${<>}:" != *":<>:"* ]] && [[ -d "<>" ]]; then
	export <>="<>:${<>}"
fi]=], {
      i(1, "PATH or FPATH"),
      i(2, "custom PATH or FPATH"),
      rep(2),
      rep(1),
      rep(2),
      rep(1),
    })
  ),

  -- Добавление пути в конец (низкий приоритет)
  s({trig = "ifpathe", dscr = "If not in PATH or FPATH"},
    fmta([=[if [[ ":${<>}:" != *":<>:"* ]] && [[ -d "<>" ]]; then
	export <>="${<>}:<>"
fi]=], {
      i(1, "PATH or FPATH"),
      i(2, "custom PATH or FPATH"),
      rep(2),
      rep(1),
      rep(1),
      rep(2),
    })
  ),

  -- Help для функции по -h/--help
  s({trig = "hforfunc", dscr = "Help for Func"},
    fmta([=[if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	cat <<EOF
<>
EOF
	return 0
fi]=], {
      i(1, "Some text about your Function"),
    })
  ),
}

