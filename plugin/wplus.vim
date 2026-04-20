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
        " Check if autoload file exists before calling setup to avoid errors
        if filereadable(expand('<sfile>:h:h') . '/autoload/wplus/' . s:module . '.vim')
            execute 'call wplus#' . s:module . '#setup()'
        endif
    endif
endfor

function! s:on_session_load() abort
    let l:cur_tab = tabpagenr()
    let l:cur_win = win_getid()
    
    " Iterate through all tabs and windows to trigger events for visible buffers
    for l:t in range(1, tabpagenr('$'))
        execute 'tabnext' l:t
        for l:w in range(1, winnr('$'))
            call win_gotoid(win_getid(l:w))
            silent! doautocmd FileType
            silent! doautocmd BufReadPost
        endfor
    endfor
    
    execute 'tabnext' l:cur_tab
    call win_gotoid(l:cur_win)
    redraw!
endfunction

augroup wplus_core
    autocmd!
    autocmd SessionLoadPost * call s:on_session_load()
augroup END
