" wplus/util.vim — Utility functions for error handling and common operations

if exists('g:autoloaded_wplus_util') | finish | endif
let g:autoloaded_wplus_util = 1

" Standard error message format: [module] message
function! wplus#util#error(message) abort
    echohl ErrorMsg
    echomsg a:message
    echohl None
endfunction

function! wplus#util#warn(message) abort
    echohl WarningMsg
    echomsg a:message
    echohl None
endfunction

function! wplus#util#info(message) abort
    echohl None
    echomsg a:message
endfunction

" Log message with module prefix
function! wplus#util#error_msg(module, message) abort
    call wplus#util#error('[wplus-' . a:module . '] ' . a:message)
endfunction

function! wplus#util#warn_msg(module, message) abort
    call wplus#util#warn('[wplus-' . a:module . '] ' . a:message)
endfunction

function! wplus#util#info_msg(module, message) abort
    call wplus#util#info('[wplus-' . a:module . '] ' . a:message)
endfunction

function! wplus#util#null_redirect() abort
    return has('win32') ? '2>nul' : '2>/dev/null'
endfunction

" Strip a:root prefix from a:file to get a path relative to the repo root.
" git commands (rev-parse --show-toplevel, etc.) always return '/'-separated
" paths, while expand('%:p')/fnamemodify() return native paths ('\' on
" Windows unless 'shellslash' is set). Normalize both to '/' before comparing
" so the prefix match works regardless of which style either side used.
function! wplus#util#relpath(root, file) abort
    let l:root = substitute(a:root, '\\', '/', 'g')
    let l:file = substitute(a:file, '\\', '/', 'g')
    return l:file[: len(l:root)] ==# l:root . '/' ? l:file[len(l:root) + 1 :] : a:file
endfunction

let s:git_root_cache = {}

function! wplus#util#clear_git_root_cache() abort
    let s:git_root_cache = {}
endfunction

function! wplus#util#channel_key(ch_or_job) abort
    if type(a:ch_or_job) == v:t_job
        return string(job_getchannel(a:ch_or_job))
    endif
    return string(a:ch_or_job)
endfunction

function! wplus#util#find_git_root(dir) abort
    if a:dir =~# '^\\\\' || a:dir =~# '^//' | return '' | endif
    if has_key(s:git_root_cache, a:dir) | return s:git_root_cache[a:dir] | endif
    let l:curr = a:dir
    let l:prev = ''
    while l:curr !=# l:prev
        if isdirectory(l:curr . '/.git')
            let s:git_root_cache[a:dir] = l:curr
            return l:curr
        endif
        let l:prev = l:curr
        let l:curr = fnamemodify(l:curr, ':h')
    endwhile
    let s:git_root_cache[a:dir] = ''
    return ''
endfunction

function! wplus#util#ensure_bufloaded(path) abort
    let l:abs = fnamemodify(a:path, ':p')
    if bufnr(l:abs) == -1
        silent execute 'badd ' . fnameescape(l:abs)
    endif
    let l:bufnr = bufnr(l:abs)
    if !bufloaded(l:bufnr)
        call bufload(l:bufnr)
    endif
    return l:bufnr
endfunction

function! wplus#util#popup_options(overrides) abort
    let l:opts = {
        \ 'border': [1, 1, 1, 1],
        \ 'padding': [0, 1, 0, 1],
        \ 'wrap': 1,
        \ 'maxwidth': 80,
        \ }
    if type(a:overrides) == v:t_dict
        call extend(l:opts, a:overrides)
    endif
    return l:opts
endfunction

augroup WplusUtil
    autocmd!
    autocmd DirChanged * call wplus#util#clear_git_root_cache()
augroup END
