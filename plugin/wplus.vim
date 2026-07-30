" vim-wplus: All-in-one vim plugin (dependency-free replacement)
" Requires: Vim 9.1+ with +job +channel +popupwin +signs

if exists('g:loaded_wplus') | finish | endif
let g:loaded_wplus = 1

" Register text property types
if !hlexists('WplusAISuggest')
    if hlexists('Comment')
        highlight default link WplusAISuggest Comment
    else
        highlight default WplusAISuggest ctermfg=244 guifg=#7c6f64
    endif
endif
if has('textprop') && empty(prop_type_get('WplusAISuggest'))
    call prop_type_add('WplusAISuggest', {'highlight': 'WplusAISuggest'})
endif

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
    if exists('g:wplus_harpoon_max_slots')
        if type(g:wplus_harpoon_max_slots) != v:t_number || g:wplus_harpoon_max_slots < 1
            let g:wplus_harpoon_max_slots = 4
            echomsg '[wplus] Warning: wplus_harpoon_max_slots must be a positive number, reset to 4'
        endif
    endif
    if exists('g:wplus_scratch_height')
        if type(g:wplus_scratch_height) != v:t_number || g:wplus_scratch_height < 1
            let g:wplus_scratch_height = 15
            echomsg '[wplus] Warning: wplus_scratch_height must be a positive number, reset to 15'
        endif
    endif
    if exists('g:wplus_history_max')
        if type(g:wplus_history_max) != v:t_number || g:wplus_history_max < 1
            let g:wplus_history_max = 50
            echomsg '[wplus] Warning: wplus_history_max must be a positive number, reset to 50'
        endif
    endif
    if exists('g:wplus_fold_level')
        if type(g:wplus_fold_level) != v:t_number || g:wplus_fold_level < 0
            let g:wplus_fold_level = 99
            echomsg '[wplus] Warning: wplus_fold_level must be a non-negative number, reset to 99'
        endif
    endif
    if exists('g:wplus_fold_column')
        if type(g:wplus_fold_column) != v:t_number || g:wplus_fold_column < 0
            let g:wplus_fold_column = 0
            echomsg '[wplus] Warning: wplus_fold_column must be a non-negative number, reset to 0'
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

let g:wplus_load_errors = get(g:, 'wplus_load_errors', [])

" Modules are set up in this order; later entries win on any keymap collision.
"
" Not listed here, deliberately:
"   repeat  - autoloaded shim only, has no setup(). See autoload/wplus/repeat.vim.
let s:modules = ['theme', 'commentary', 'pairs', 'altfile', 'indent', 'statusline', 'tabline', 'gitgutter', 'blame', 'illuminate', 'surround', 'format', 'yankhighlight', 'textobj', 'bufdelete', 'quickfix', 'grep', 'root', 'terminal', 'lsp', 'finder', 'explorer', 'session', 'todo', 'conflict', 'ai', 'multicursor', 'register', 'outline', 'diffview', 'harpoon', 'marks', 'scratch', 'run', 'project', 'history', 'fold', 'health']

" Validate user configuration
call s:validate_config()

" Load and setup modules
for s:module in s:modules
    let s:toggle = 'wplus_' . s:module . '_enabled'
    let g:[s:toggle] = get(g:, s:toggle, 1)
    if get(g:, s:toggle, 1)
        try
            execute 'call wplus#' . s:module . '#setup()'
        catch
            let l:err = '[wplus] Failed to load module ' . s:module . ': ' . v:exception
            call add(g:wplus_load_errors, l:err)
            echomsg l:err
        endtry
    endif
endfor
unlet s:module s:toggle

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
