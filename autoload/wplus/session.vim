" wplus/session.vim — Session management (autoload/autosave)

if exists('g:autoloaded_wplus_session') | finish | endif
let g:autoloaded_wplus_session = 1

" ── variables ─────────────────────────────────────────────────────────────

let g:wplus_session_autoload = get(g:, 'wplus_session_autoload', get(g:, 'wplus_session_auto_restore', 1))
let g:wplus_session_autosave = get(g:, 'wplus_session_autosave', get(g:, 'wplus_session_auto_save', 1))
let g:wplus_session_max_files = get(g:, 'wplus_session_max_files', 50)
let s:session_dir = expand('~/.vim/sessions')

" ── public API ────────────────────────────────────────────────────────────

function! wplus#session#setup() abort
    if !isdirectory(s:session_dir)
        call mkdir(s:session_dir, 'p', 0700)
    elseif exists('*setfperm')
        call setfperm(s:session_dir, 'rwx------')
    endif
    " terminal 버퍼는 Windows에서 복원 시 hang 유발
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
    " (e.g. tagbar#RestoreSession, NERDTree, etc.)
    for l:winnr in range(1, winnr('$'))
        let l:bt = getwinvar(l:winnr, '&buftype')
        let l:ft = getwinvar(l:winnr, '&filetype')
        if l:ft =~# '^\(tagbar\|nerdtree\|netrw\)$' || l:bt ==# 'nofile' || l:bt ==# 'terminal'
            " :windo accepts no range, so `execute l:winnr . 'windo close'` threw
            " E481 on every VimLeavePre that had a sidebar open -- uncaught, and
            " right in the middle of session saving.
            try
                execute l:winnr . 'wincmd w'
                close
            catch
                " last window, or already gone -- nothing to close
            endtry
            break
        endif
    endfor
endfunction

function! s:save_session() abort
    " Skip if in special buffer or no real buffers
    if &buftype != '' || empty(bufname('%')) | return | endif
    " Skip if session file is empty (e.g. just started and no file opened)
    if argc() == 0 && line2byte('$') == -1 && bufnr('$') == 1 | return | endif

    call s:close_plugin_windows()
    let l:file = s:get_session_name()
    execute 'mksession! ' . fnameescape(l:file)
endfunction

function! s:load_session() abort
    " Only load if starting Vim with no arguments and empty buffer
    if argc() > 0 || line2byte('$') != -1 || bufnr('$') > 1 | return | endif

    let l:file = s:get_session_name()
    if filereadable(l:file)
        try
            execute 'source ' . fnameescape(l:file)
        catch
            call wplus#util#warn_msg('session', 'session load error: ' . v:exception)
        endtry
    endif
endfunction

function! s:delete_session() abort
    let l:file = s:get_session_name()
    if filereadable(l:file)
        call delete(l:file)
        echo "Wplus: Session deleted for current project."
    endif
endfunction
