" vim-wplus: All-in-one vim plugin (dependency-free replacement)
" Requires: Vim 9.1+ with +job +channel +popupwin +signs

if exists('g:loaded_wplus') | finish | endif
let g:loaded_wplus = 1

" ── module toggles (set to 0 in vimrc before plugin loads to disable) ─────
let g:wplus_commentary_enabled = get(g:, 'wplus_commentary_enabled', 1)
let g:wplus_pairs_enabled      = get(g:, 'wplus_pairs_enabled',      1)
let g:wplus_repeat_enabled     = get(g:, 'wplus_repeat_enabled',     1)
let g:wplus_altfile_enabled    = get(g:, 'wplus_altfile_enabled',    1)
let g:wplus_indent_enabled     = get(g:, 'wplus_indent_enabled',     1)
let g:wplus_statusline_enabled = get(g:, 'wplus_statusline_enabled', 1)
let g:wplus_tabline_enabled    = get(g:, 'wplus_tabline_enabled',    1)
let g:wplus_gitgutter_enabled  = get(g:, 'wplus_gitgutter_enabled',  1)
let g:wplus_blame_enabled      = get(g:, 'wplus_blame_enabled',      1)
let g:wplus_illuminate_enabled = get(g:, 'wplus_illuminate_enabled', 1)
let g:wplus_whichkey_enabled   = get(g:, 'wplus_whichkey_enabled',   1)
let g:wplus_undotree_enabled   = get(g:, 'wplus_undotree_enabled',   1)
let g:wplus_surround_enabled      = get(g:, 'wplus_surround_enabled',      1)
let g:wplus_format_enabled        = get(g:, 'wplus_format_enabled',        1)
let g:wplus_yankhighlight_enabled = get(g:, 'wplus_yankhighlight_enabled', 1)
let g:wplus_textobj_enabled       = get(g:, 'wplus_textobj_enabled',       1)
let g:wplus_bufdelete_enabled     = get(g:, 'wplus_bufdelete_enabled',     1)
let g:wplus_quickfix_enabled      = get(g:, 'wplus_quickfix_enabled',      1)
let g:wplus_grep_enabled          = get(g:, 'wplus_grep_enabled',          1)
let g:wplus_root_enabled          = get(g:, 'wplus_root_enabled',          1)
let g:wplus_terminal_enabled      = get(g:, 'wplus_terminal_enabled',      1)
let g:wplus_lsp_enabled           = get(g:, 'wplus_lsp_enabled',           1)
let g:wplus_finder_enabled        = get(g:, 'wplus_finder_enabled',        1)
let g:wplus_explorer_enabled      = get(g:, 'wplus_explorer_enabled',      1)

" ── load modules ──────────────────────────────────────────────────────────
if g:wplus_commentary_enabled | call wplus#commentary#setup() | endif
if g:wplus_pairs_enabled      | call wplus#pairs#setup()      | endif
if g:wplus_repeat_enabled     | call wplus#repeat#setup()     | endif
if g:wplus_altfile_enabled    | call wplus#altfile#setup()    | endif
if g:wplus_indent_enabled     | call wplus#indent#setup()     | endif
if g:wplus_statusline_enabled | call wplus#statusline#setup() | endif
if g:wplus_tabline_enabled    | call wplus#tabline#setup()    | endif
if g:wplus_gitgutter_enabled  | call wplus#gitgutter#setup()  | endif
if g:wplus_blame_enabled      | call wplus#blame#setup()      | endif
if g:wplus_illuminate_enabled | call wplus#illuminate#setup() | endif
if g:wplus_whichkey_enabled   | call wplus#whichkey#setup()   | endif
if g:wplus_undotree_enabled   | call wplus#undotree#setup()   | endif
if g:wplus_surround_enabled      | call wplus#surround#setup()      | endif
if g:wplus_format_enabled        | call wplus#format#setup()        | endif
if g:wplus_yankhighlight_enabled | call wplus#yankhighlight#setup() | endif
if g:wplus_textobj_enabled       | call wplus#textobj#setup()       | endif
if g:wplus_bufdelete_enabled     | call wplus#bufdelete#setup()     | endif
if g:wplus_quickfix_enabled      | call wplus#quickfix#setup()      | endif
if g:wplus_grep_enabled          | call wplus#grep#setup()          | endif
if g:wplus_root_enabled          | call wplus#root#setup()          | endif
if g:wplus_terminal_enabled      | call wplus#terminal#setup()      | endif
if g:wplus_lsp_enabled           | call wplus#lsp#setup()           | endif
if g:wplus_finder_enabled        | call wplus#finder#setup()        | endif
if g:wplus_explorer_enabled      | call wplus#explorer#setup()      | endif
