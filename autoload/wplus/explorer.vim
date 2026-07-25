" wplus/explorer.vim — Minimal file explorer sidebar with tree view

if exists('g:autoloaded_wplus_explorer') | finish | endif
let g:autoloaded_wplus_explorer = 1

let s:explorer_buf = -1
let s:expanded = {} " path -> 1 (expanded)
let s:tree_data = [] " List of {path, level, is_dir, name}
let g:wplus_explorer_max_entries = get(g:, 'wplus_explorer_max_entries', 1000)
let g:wplus_explorer_max_depth = get(g:, 'wplus_explorer_max_depth', 8)
let s:truncated = 0
let s:entry_count = 0
let s:dir_cache = {}
let s:visited_paths = {} " Track visited realpath to detect symlink loops

function! s:normalize_dir(path) abort
    let l:path = simplify(fnamemodify(a:path, ':p'))
    if l:path !=# '/'
        let l:path = substitute(l:path, '/\+$', '', '')
    endif
    return l:path
endfunction

function! s:get_dir_entries(path) abort
    if has_key(s:dir_cache, a:path)
        return copy(s:dir_cache[a:path])
    endif

    try
        let l:files = readdir(a:path)
    catch
        return []
    endtry

    let l:p = a:path
    call sort(l:files, {a, b -> isdirectory(l:p . '/' . a) == isdirectory(l:p . '/' . b) ? (a ==# b ? 0 : (a ># b ? 1 : -1)) : (isdirectory(l:p . '/' . a) ? -1 : 1)})
    let s:dir_cache[a:path] = copy(l:files)
    return l:files
endfunction

function! s:invalidate_cache(path) abort
    let l:prefix = s:normalize_dir(a:path)
    for l:key in keys(copy(s:dir_cache))
        if l:key ==# l:prefix || l:key[: len(l:prefix)] ==# l:prefix . '/'
            unlet s:dir_cache[l:key]
        endif
    endfor
endfunction

function! wplus#explorer#toggle() abort
    let l:winid = bufwinid(s:explorer_buf)
    if l:winid != -1
        let l:cur_win = win_getid()
        if win_gotoid(l:winid)
            close
            if l:cur_win != l:winid
                call win_gotoid(l:cur_win)
            endif
        endif
    else
        call s:open_explorer()
    endif
endfunction

function! s:open_explorer() abort
    let l:path = getcwd()
    let l:buf = bufnr('^WplusExplorer$')
    if l:buf != -1 && bufexists(l:buf)
        execute 'topleft 30vsplit'
        execute 'buffer' l:buf
    else
        execute 'topleft 30vsplit'
        enew
        silent! file WplusExplorer
    endif
    let s:explorer_buf = bufnr('%')
    setfiletype wplus-explorer
    call s:init_buffer()
    call s:render(l:path)
endfunction

function! s:init_buffer() abort
    setlocal buftype=nofile bufhidden=hide noswapfile
    setlocal nobuflisted nomodifiable nonumber norelativenumber
    setlocal cursorline winfixwidth nowrap

    " Syntax highlighting
    syntax clear
    syntax match WplusExplorerRoot /^\%(\a:[\\\/]\|\/\).*$/
    syntax match WplusExplorerDir /^ \+▸.*/
    syntax match WplusExplorerDirOpen /^ \+▾.*/
    
    highlight default link WplusExplorerRoot Title
    highlight default link WplusExplorerDir  Directory
    highlight default link WplusExplorerDirOpen Directory

    nnoremap <buffer> <CR>  :call <SID>on_enter()<CR>
    nnoremap <buffer> a     :call <SID>on_add()<CR>
    nnoremap <buffer> d     :call <SID>on_delete()<CR>
    nnoremap <buffer> r     :call <SID>on_rename()<CR>
    nnoremap <buffer> q     :close<CR>
    nnoremap <buffer> R     :call <SID>refresh()<CR>
endfunction

function! s:on_session_load() abort
    " Give Vim a moment to settle after session load
    call timer_start(50, {-> s:do_restore_explorer()})
endfunction

function! s:do_restore_explorer() abort
    let l:cur_win = win_getid()
    for l:w in range(1, winnr('$'))
        let l:buf = winbufnr(l:w)
        " Find explorer window by name
        if bufname(l:buf) =~# 'WplusExplorer'
            let s:explorer_buf = l:buf
            call win_gotoid(win_getid(l:w))
            setfiletype wplus-explorer
            call s:init_buffer()
            call s:render(getcwd())
            call win_gotoid(l:cur_win)
            redraw!
            return
        endif
    endfor
endfunction

function! s:render(root) abort
    let s:current_root = s:normalize_dir(a:root)
    let s:tree_data = []
    let s:truncated = 0
    let s:entry_count = 0
    let s:visited_paths = {}
    call s:build_tree(s:current_root, 0)
    
    let l:winw = winwidth(bufwinid(s:explorer_buf))
    let l:lines = [s:current_root]
    for l:item in s:tree_data
        let l:indent = repeat('  ', l:item.level + 1)
        let l:prefix = l:item.is_dir ? (get(s:expanded, l:item.path, 0) ? '▾ ' : '▸ ') : '  '
        let l:avail = l:winw - len(l:indent) - len(l:prefix)
        let l:name = len(l:item.name) > l:avail ? l:item.name[: l:avail - 2] . '…' : l:item.name
        call add(l:lines, l:indent . l:prefix . l:name)
    endfor
    if s:truncated
        call add(l:lines, '  ... truncated ...')
    endif
    
    setlocal modifiable
    silent %delete _
    call setline(1, l:lines)
    setlocal nomodifiable
endfunction

function! s:build_tree(path, level) abort
    if s:entry_count >= g:wplus_explorer_max_entries || a:level >= g:wplus_explorer_max_depth
        let s:truncated = 1
        return
    endif

    let l:realpath = resolve(a:path)
    " Detect symlink loops
    if has_key(s:visited_paths, l:realpath)
        return
    endif
    let s:visited_paths[l:realpath] = 1

    let l:files = s:get_dir_entries(a:path)
    
    for l:f in l:files
        if l:f ==# '.git' | continue | endif
        if s:entry_count >= g:wplus_explorer_max_entries
            let s:truncated = 1
            return
        endif
        let l:full = a:path . '/' . l:f
        let l:is_dir = isdirectory(l:full)
        call add(s:tree_data, {'path': l:full, 'level': a:level, 'is_dir': l:is_dir, 'name': l:f})
        let s:entry_count += 1
        
        if l:is_dir && get(s:expanded, l:full, 0)
            call s:build_tree(l:full, a:level + 1)
        endif
    endfor
endfunction

function! s:on_enter() abort
    let l:lnum = line('.')
    if l:lnum == 1 | return | endif
    let l:item = s:tree_data[l:lnum - 2]
    
    if l:item.is_dir
        if get(s:expanded, l:item.path, 0)
            unlet s:expanded[l:item.path]
        else
            let s:expanded[l:item.path] = 1
        endif
        call s:render(s:current_root)
        execute l:lnum
    else
        wincmd l
        execute 'edit' fnameescape(l:item.path)
    endif
endfunction

function! s:on_add() abort
    let l:lnum = line('.')
    let l:parent = l:lnum == 1 ? s:current_root : s:tree_data[l:lnum - 2].path
    if !isdirectory(l:parent) | let l:parent = fnamemodify(l:parent, ':h') | endif
    
    let l:name = input('New file/dir: ')
    if empty(l:name) | return | endif
    let l:full_path = l:parent . '/' . l:name
    if l:name =~ '/$'
        call mkdir(l:full_path, 'p')
    else
        call writefile([], l:full_path)
    endif
    call s:invalidate_cache(l:parent)
    call s:refresh()
endfunction

function! s:on_delete() abort
    let l:lnum = line('.')
    if l:lnum == 1 | return | endif
    let l:item = s:tree_data[l:lnum - 2]
    if confirm("Delete " . l:item.name . "?", "&Yes\n&No") == 1
        call delete(l:item.path, 'rf')
        call s:invalidate_cache(fnamemodify(l:item.path, ':h'))
        call s:refresh()
    endif
endfunction

function! s:on_rename() abort
    let l:lnum = line('.')
    if l:lnum == 1 | return | endif
    let l:item = s:tree_data[l:lnum - 2]
    let l:new_name = input('Rename to: ', l:item.name)
    if empty(l:new_name) || l:new_name == l:item.name | return | endif
    call rename(l:item.path, fnamemodify(l:item.path, ':h') . '/' . l:new_name)
    call s:invalidate_cache(fnamemodify(l:item.path, ':h'))
    call s:refresh()
endfunction

function! s:refresh() abort
    call s:invalidate_cache(s:current_root)
    call s:render(s:current_root)
endfunction

function! wplus#explorer#setup() abort
    command! WexplorerToggle call wplus#explorer#toggle()
    nnoremap <silent> <leader>e :WexplorerToggle<CR>

    augroup WplusExplorer
        autocmd!
        autocmd SessionLoadPost * call s:on_session_load()
    augroup END
endfunction
