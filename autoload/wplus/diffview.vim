" wplus/diffview.vim — Git diff viewer + hunk navigation
" Mappings:
"   <leader>gd  — open diff for current file (git diff HEAD)
"   <leader>gD  — open full repo diff (git diff HEAD)
"   ]h          — next hunk (uses gitgutter signs)
"   [h          — prev hunk

if exists('g:autoloaded_wplus_diffview') | finish | endif
let g:autoloaded_wplus_diffview = 1

let s:buf_name = '__WplusDiff__'
let s:diff_buf = -1
let s:job      = v:null

" ── git helpers (same pattern as gitgutter.vim) ───────────────────────────

function! s:git_root(file) abort
    let l:dir = fnamemodify(a:file, ':h')
    let l:out = systemlist('git -C ' . shellescape(l:dir) .
        \ ' rev-parse --show-toplevel ' . wplus#util#null_redirect())
    return v:shell_error == 0 && !empty(l:out) ? trim(l:out[0]) : ''
endfunction

" ── diff buffer rendering ─────────────────────────────────────────────────

function! s:open_diff_buf() abort
    let l:existing = bufnr(s:buf_name)
    execute 'botright vsplit'
    if l:existing != -1 && bufexists(l:existing)
        execute 'buffer' l:existing
    else
        enew
        silent! execute 'file ' . s:buf_name
    endif
    let s:diff_buf = bufnr('%')
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    setlocal nonumber norelativenumber nowrap
    setfiletype diff
    nnoremap <buffer> <silent> q :close<CR>
endfunction

function! s:fill_buf(lines) abort
    let l:winid = bufwinid(s:diff_buf)
    if l:winid == -1 | return | endif
    call win_execute(l:winid, 'setlocal modifiable')
    call win_execute(l:winid, 'silent %delete _')
    call setbufline(s:diff_buf, 1, empty(a:lines) ? ['(no changes)'] : a:lines)
    call win_execute(l:winid, 'setlocal nomodifiable')
    call win_execute(l:winid, 'call cursor(1, 1)')
endfunction

" ── open diff (async) ─────────────────────────────────────────────────────

function! wplus#diffview#open(...) abort
    let l:file = expand('%:p')
    if empty(l:file) | call wplus#util#warn_msg('diffview', 'No file') | return | endif

    let l:root = s:git_root(l:file)
    if empty(l:root) | call wplus#util#warn_msg('diffview', 'Not a git repository') | return | endif

    let l:rel  = wplus#util#relpath(l:root, l:file)
    let l:args = get(a:, 1, '') ==# 'all'
        \ ? ['git', '-C', l:root, 'diff', 'HEAD']
        \ : ['git', '-C', l:root, 'diff', 'HEAD', '--', l:rel]

    call s:open_diff_buf()

    if s:job isnot v:null
        try | call job_stop(s:job) | catch | endtry
    endif

    let l:lines = []
    let s:job = job_start(l:args, {
        \ 'out_cb':   {_, l -> add(l:lines, l)},
        \ 'close_cb': {_ -> s:fill_buf(l:lines)},
        \ 'err_cb':   {_ch, _msg -> 0},
        \ })
endfunction

function! wplus#diffview#open_all() abort
    call wplus#diffview#open('all')
endfunction

" ── setup ─────────────────────────────────────────────────────────────────
"
" Hunk navigation (]h / [h) belongs to the gitgutter module, which owns the
" authoritative hunk list in b:wplus_gitgutter_hunks. This module used to define
" ]h/[h as well and -- being set up later -- silently won, replacing gitgutter's
" implementation with one that read gitgutter's *signs* back out of the sign
" column. That made the winning implementation depend on the losing module being
" enabled. diffview is now a pure viewer.

function! wplus#diffview#setup() abort
    command! WdiffviewFile call wplus#diffview#open()
    command! WdiffviewRepo call wplus#diffview#open_all()
    nnoremap <silent> <leader>gd :call wplus#diffview#open()<CR>
    nnoremap <silent> <leader>gD :call wplus#diffview#open_all()<CR>
endfunction
