" wplus/session.vim — Smart project-based session management

if exists('g:autoloaded_wplus_session') | finish | endif
let g:autoloaded_wplus_session = 1

let s:session_dir = expand('~/.vim/sessions')
let g:wplus_session_autoload = get(g:, 'wplus_session_autoload', 1)
let g:wplus_session_autosave = get(g:, 'wplus_session_autosave', 1)
let g:wplus_session_max_files = get(g:, 'wplus_session_max_files', 50)
let s:auto_loaded = 0

function! wplus#session#setup() abort
    if !isdirectory(s:session_dir)
        call mkdir(s:session_dir, 'p')
    endif

    command! WsessionSave call wplus#session#save()
    command! WsessionLoad call wplus#session#load()

    augroup WplusSession
        autocmd!
        autocmd VimEnter * call s:auto_load()
        autocmd VimLeavePre * call s:auto_save()
    augroup END
endfunction

function! s:get_session_path() abort
    let l:root = getcwd()
    " Replace non-alphanumeric chars with underscore for filename
    let l:name = substitute(l:root, '[^a-zA-Z0-9]', '_', 'g') . '.vim'
    return s:session_dir . '/' . l:name
endfunction

function! s:list_session_files() abort
    if !isdirectory(s:session_dir)
        return []
    endif

    let l:files = map(readdir(s:session_dir), 's:session_dir . "/" . v:val')
    let l:files = filter(l:files, 'filereadable(v:val)')
    call sort(l:files, {a, b -> getftime(a) == getftime(b) ? 0 : (getftime(a) > getftime(b) ? -1 : 1)})
    return l:files
endfunction

function! s:cleanup_sessions() abort
    let l:files = s:list_session_files()
    if g:wplus_session_max_files <= 0 || len(l:files) <= g:wplus_session_max_files
        return
    endif

    for l:file in l:files[g:wplus_session_max_files :]
        call delete(l:file)
    endfor
endfunction

function! s:has_normal_buffers() abort
    for l:buf in getbufinfo({'bufloaded': 1})
        if getbufvar(l:buf.bufnr, '&buftype') ==# '' && !empty(bufname(l:buf.bufnr))
            return 1
        endif
    endfor
    return 0
endfunction

function! wplus#session#save() abort
    if !isdirectory(getcwd()) || !s:has_normal_buffers() | return | endif

    let l:path = s:get_session_path()
    try
        execute 'mksession! ' . fnameescape(l:path)
    catch
        return
    endtry
    call s:cleanup_sessions()
endfunction

function! wplus#session#load() abort
    let l:path = s:get_session_path()
    if filereadable(l:path)
        let s:auto_loaded = 1
        try
            execute 'source ' . fnameescape(l:path)
        catch
            return
        endtry
        echo "[wplus] session restored for: " . getcwd()
    endif
endfunction

function! s:auto_load() abort
    if g:wplus_session_autoload && argc() == 0 && !s:auto_loaded
        call wplus#session#load()
    endif
endfunction

function! s:auto_save() abort
    if g:wplus_session_autosave
        call wplus#session#save()
    endif
endfunction
