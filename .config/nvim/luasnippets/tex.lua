local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local fmta = require("luasnip.extras.fmt").fmta
local rep = require("luasnip.extras").rep

return {
  s({trig = "be", dscr = "begin & end"},
    fmta([[\begin{<>}
	<>
\end{<>}]], { i(1, "blockname"), i(2, "something"), rep(1) })
  ),

  s({trig = "betab", dscr = "begin & end in tabl"},
    fmta([[\begin{tabular}{<>}
	\hline
	<>\\
	\hline
\end{tabular}]], { i(1, "| or ||, c or l or r, also p={x cm}"), i(2, "Line and sep &") })
  ),

  s({trig = "tabl", dscr = "tabl line"},
    fmta([[\hline
<>\\]], { i(1, "Line and sep &") })
  ),

  s({trig = "lstg", dscr = "lst inline git-style"},
    fmta([[\lstinline[style=git-style]|<>|]], { i(1) })
  ),

  s({trig = "belst", dscr = "begin & end lstlisting"},
    fmta([[\begin{lstlisting}
	<>
\end{lstlisting}]], { i(1) })
  ),

  s({trig = "belstg", dscr = "begin & end lstlisting git-style"},
    fmta([[\begin{lstlisting}[style=git-style]
	<>
\end{lstlisting}]], { i(1) })
  ),

  s({trig = "col", dscr = "color string"},
    fmta([[{\color{<>}<>} <>]], { i(1, "Color"), i(2, "Text"), i(3, "Next") })
  ),

  s({trig = "tcol", dscr = "text color"},
    fmta([[\textcolor{<>}{<>} <>]], { i(1, "Color"), i(2, "Text"), i(3, "Next") })
  ),
}

