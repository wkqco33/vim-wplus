" vim-wplus: All-in-one vim plugin (dependency-free replacement)
" Requires: Vim 9.1+ with +job +channel +popupwin +signs

if exists('g:loaded_wplus') | finish | endif
let g:loaded_wplus = 1

let s:modules = [
    \ 'commentary', 'pairs', 'repeat', 'altfile', 'indent', 'statusline',
    \ 'tabline', 'gitgutter', 'blame', 'illuminate', 'whichkey', 'undotree',
    \ 'surround', 'format', 'yankhighlight', 'textobj', 'bufdelete', 'quickfix',
    \ 'grep', 'root', 'terminal', 'lsp', 'finder', 'explorer', 'session', 'todo',
    \ 'colorscheme', 'snippet', 'conflict', 'ai',
    \ ]

" Validate user configuration
call s:validate_config()

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

function! s:validate_config() abort
    " Validate numeric settings
    if exists('g:wplus_explorer_max_entries')
        if type(g:wplus_explorer_max_entries) != v:t_number || g:wplus_explorer_max_entries < 1
            let g:wplus_explorer_max_entries = 1000
            echomsg '[wplus] Warning: wplus_explorer_max_entries must be a positive number, reset to 1000'
        endif
    endif
    if exists('g:wplus_explorer_max_depth')
        if type(g:wplus_explorer_max_depth) != v:t_number || g:wplus_explorer_max_depth < 1
            let g:wplus_explorer_max_depth = 8
            echomsg '[wplus] Warning: wplus_explorer_max_depth must be a positive number, reset to 8'
        endif
    endif
    if exists('g:wplus_undotree_width')
        if type(g:wplus_undotree_width) != v:t_number || g:wplus_undotree_width < 1
            let g:wplus_undotree_width = 30
            echomsg '[wplus] Warning: wplus_undotree_width must be a positive number, reset to 30'
        endif
    endif
    if exists('g:wplus_blame_delay')
        if type(g:wplus_blame_delay) != v:t_number || g:wplus_blame_delay < 0
            let g:wplus_blame_delay = 500
            echomsg '[wplus] Warning: wplus_blame_delay must be a non-negative number, reset to 500'
        endif
    endif
    if exists('g:wplus_illuminate_delay')
        if type(g:wplus_illuminate_delay) != v:t_number || g:wplus_illuminate_delay < 0
            let g:wplus_illuminate_delay = 200
            echomsg '[wplus] Warning: wplus_illuminate_delay must be a non-negative number, reset to 200'
        endif
    endif
    if exists('g:wplus_yank_duration')
        if type(g:wplus_yank_duration) != v:t_number || g:wplus_yank_duration < 0
            let g:wplus_yank_duration = 250
            echomsg '[wplus] Warning: wplus_yank_duration must be a non-negative number, reset to 250'
        endif
    endif
    
    " Validate string settings
    if exists('g:wplus_indent_char')
        if type(g:wplus_indent_char) != v:t_string || len(g:wplus_indent_char) == 0
            let g:wplus_indent_char = '▏'
            echomsg '[wplus] Warning: wplus_indent_char must be a non-empty string, reset to ▏'
        endif
    endif
    if exists('g:wplus_blame_prefix')
        if type(g:wplus_blame_prefix) != v:t_string
            let g:wplus_blame_prefix = '   '
            echomsg '[wplus] Warning: wplus_blame_prefix must be a string, reset to spaces'
        endif
    endif
    if exists('g:wplus_blame_template')
        if type(g:wplus_blame_template) != v:t_string
            let g:wplus_blame_template = '<author>, <date> • <summary>'
            echomsg '[wplus] Warning: wplus_blame_template must be a string, reset to default'
        endif
    endif
endfunction

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
