" vim-wplus: All-in-one vim plugin (dependency-free replacement)
" Requires: Vim 9.1+ with +job +channel +popupwin +signs

if exists('g:loaded_wplus') | finish | endif
let g:loaded_wplus = 1

let s:modules = [
    \ 'commentary', 'pairs', 'repeat', 'altfile', 'indent', 'statusline',
    \ 'tabline', 'gitgutter', 'blame', 'illuminate', 'whichkey', 'undotree',
    \ 'surround', 'format', 'yankhighlight', 'textobj', 'bufdelete', 'quickfix',
    \ 'grep', 'root', 'terminal', 'lsp', 'finder', 'explorer', 'session', 'todo',
    \ ]

for s:module in s:modules
    let s:toggle = 'wplus_' . s:module . '_enabled'
    let g:[s:toggle] = get(g:, s:toggle, 1)
    if get(g:, s:toggle, 0)
        execute 'call wplus#' . s:module . '#setup()'
    endif
endfor
