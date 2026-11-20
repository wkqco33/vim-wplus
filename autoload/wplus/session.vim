" wplus/session.vim — Session management (autoload/autosave)

if exists('g:autoloaded_wplus_session') | finish | endif
let g:autoloaded_wplus_session = 1

" ── variables ─────────────────────────────────────────────────────────────

let g:wplus_session_autoload = get(g:, 'wplus_session_autoload', get(g:, 'wplus_session_auto_restore', 1))
let g:wplus_session_autosave = get(g:, 'wplus_session_autosave', get(g:, 'wplus_session_auto_save', 1))
let g:wplus_session_max_files = get(g:, 'wplus_session_max_files', 50)
let s:session_dir = expand(get(g:, 'wplus_session_dir', '~/.vim/sessions'))

" mksession records every option, including the plugin load path. Restoring
" that value replaces the current Vim's 'runtimepath'/'packpath' with whatever
" the saving Vim had, so any autoload function that is still unloaded fails
" with E117 (e.g. tagbar's SessionLoadPost -> tagbar#RestoreSession).
let s:load_path_pattern = '^\s*se\%[t]\%[global]\s\+\%(runtimepath\|rtp\|packpath\|pp\)\s*='

" ── public API ────────────────────────────────────────────────────────────

function! wplus#session#setup() abort
    if !isdirectory(s:session_dir)
        call mkdir(s:session_dir, 'p', 0700)
    elseif exists('*setfperm')
        call setfperm(s:session_dir, 'rwx------')
    endif
    " Terminal buffers can cause hang on restore on Windows
    set sessionoptions-=terminal

    if g:wplus_session_autoload
        augroup WplusSessionLoad
            autocmd!
            " Use nested to allow BufRead/FileType autocmds to fire
            autocmd VimEnter * nested call s:load_session()
        augroup END
    endif
    
    if g:wplus_session_autosave
        augroup WplusSessionSave
            autocmd!
            autocmd VimLeavePre * call s:save_session()
        augroup END
    endif
    
    command! WsessionSave   call s:save_session()
    command! WsessionLoad   call s:load_session()
    command! WsessionDelete call s:delete_session()
endfunction

" ── internal ──────────────────────────────────────────────────────────────

function! s:get_session_name() abort
    let l:root = wplus#root#find_root()
    if empty(l:root) | let l:root = getcwd() | endif
    let l:root = resolve(fnamemodify(l:root, ':p'))
    " A readable basename is useful for inspection, while the hash prevents
    " collisions such as /a_b and /a/b sharing a session file.
    let l:base = substitute(fnamemodify(l:root, ':t'), '[^A-Za-z0-9_.-]', '_', 'g')
    let l:digest = exists('*sha256') ? sha256(l:root)[:15] : substitute(l:root, '[^A-Za-z0-9]', '_', 'g')[:31]
    return s:session_dir . '/' . l:base . '-' . l:digest . '.vim'
endfunction

function! s:close_plugin_windows() abort
    " Close sidebar/plugin windows that embed unrestorable state into sessions
    " (e.g. tagbar#RestoreSession, NERDTree, etc.). Iterate in reverse so
    " closing a window does not shift lower window numbers.
    for l:winnr in reverse(range(1, winnr('$')))
        let l:bt = getwinvar(l:winnr, '&buftype')
        let l:ft = getwinvar(l:winnr, '&filetype')
        if l:ft =~# '^\(tagbar\|nerdtree\|netrw\)$' || l:bt ==# 'nofile' || l:bt ==# 'terminal'
            try
                execute l:winnr . 'wincmd w'
                close
            catch
                " last window, or already gone -- nothing to close
            endtry
        endif
    endfor
endfunction

function! s:save_session() abort
    " Skip if in special buffer or no real buffers
    if &buftype != '' || empty(bufname('%')) | return | endif
    " Skip if session file is empty (e.g. just started and no file opened)
    if argc() == 0 && line2byte('$') == -1 && bufnr('$') == 1 | return | endif

    let l:listed = len(getbufinfo({'buflisted': 1}))
    if l:listed > get(g:, 'wplus_session_max_files', 50)
        return
    endif

    call s:close_plugin_windows()
    let l:file = s:get_session_name()
    execute 'mksession! ' . fnameescape(l:file)
    " Do not let this file pin the plugin load path for the next start.
    call s:sanitize_file(l:file)
endfunction

" Lines that must not travel between Vim instances (plugin load path).
function! s:strip_load_paths(lines) abort
    return filter(copy(a:lines), 'v:val !~# s:load_path_pattern')
endfunction

" Remove the load-path options from a session file in place. Returns the number
" of stripped lines; keeps the file mode because sessions can hold registers.
function! s:sanitize_file(path) abort
    let l:lines = readfile(a:path)
    let l:kept = s:strip_load_paths(l:lines)
    let l:stripped = len(l:lines) - len(l:kept)
    if l:stripped > 0
        let l:perm = getfperm(a:path)
        call writefile(l:kept, a:path)
        if !empty(l:perm) | call setfperm(a:path, l:perm) | endif
    endif
    return l:stripped
endfunction

" Source a:path with the load-path options removed. Sessions written by an
" older wplus (or by another Vim) are restored from a sanitized copy so the
" user's file is left untouched. Returns '' or the caught exception text.
function! s:restore_file(path) abort
    if !filereadable(a:path)
        return ''
    endif
    let l:lines = readfile(a:path)
    let l:kept = s:strip_load_paths(l:lines)
    let l:file = a:path
    let l:temp = ''
    if len(l:kept) != len(l:lines)
        let l:temp = tempname()
        call writefile(l:kept, l:temp)
        let l:file = l:temp
    endif
    try
        execute 'source ' . fnameescape(l:file)
        return ''
    catch
        return v:exception
    finally
        if !empty(l:temp) | call delete(l:temp) | endif
    endtry
endfunction

function! s:load_session() abort
    " Only load if starting Vim with no arguments and empty buffer
    if argc() > 0 || line2byte('$') != -1 || bufnr('$') > 1 | return | endif

    let l:err = s:restore_file(s:get_session_name())
    if !empty(l:err)
        call wplus#util#warn_msg('session', 'session load error: ' . l:err)
    endif
endfunction

function! s:delete_session() abort
    let l:file = s:get_session_name()
    if filereadable(l:file)
        call delete(l:file)
        echo "Wplus: Session deleted for current project."
    endif
endfunction


" ── test bridges ──────────────────────────────────────────────────────────
" Thin public wrappers so the restore path can be exercised without a real
" VimEnter; see test/test_session.vim.

function! wplus#session#_test_strip(lines) abort
    return s:strip_load_paths(a:lines)
endfunction

function! wplus#session#_test_restore(path) abort
    return s:restore_file(a:path)
endfunction

function! wplus#session#_test_sanitize_file(path) abort
    return s:sanitize_file(a:path)
endfunction

function! wplus#session#_test_session_dir() abort
    return s:session_dir
endfunction
