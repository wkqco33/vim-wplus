" wplus/gitgutter.vim — sign-column git diff markers (replaces vim-gitgutter)
" Uses job_start() for async git diff; sign_place() to mark changes.

if exists('g:autoloaded_wplus_gitgutter') | finish | endif
let g:autoloaded_wplus_gitgutter = 1

let g:wplus_gitgutter_sign_add    = get(g:, 'wplus_gitgutter_sign_add',    '┃')
let g:wplus_gitgutter_sign_change = get(g:, 'wplus_gitgutter_sign_change', '┃')
let g:wplus_gitgutter_sign_delete = get(g:, 'wplus_gitgutter_sign_delete', '▁')

let s:sign_group = 'wplus_gitgutter'
let s:pending    = {}   " bufnr → job handle

" ── sign definitions ──────────────────────────────────────────────────────

function! s:define_signs() abort
    call sign_define('WplusGGAdd',    {'text': g:wplus_gitgutter_sign_add,    'texthl': 'WplusGGAdd'})
    call sign_define('WplusGGChange', {'text': g:wplus_gitgutter_sign_change, 'texthl': 'WplusGGChange'})
    call sign_define('WplusGGDelete', {'text': g:wplus_gitgutter_sign_delete, 'texthl': 'WplusGGDelete'})
endfunction

function! s:init_highlights() abort
    hi WplusGGAdd    ctermfg=142 guifg=#b8bb26
    hi WplusGGChange ctermfg=214 guifg=#fabd2f
    hi WplusGGDelete ctermfg=167 guifg=#fb4934
endfunction

" ── unified-diff parser → list of {lnum, type} ────────────────────────────

function! s:parse_diff(lines) abort
    let hunks = []
    let new_lnum = 0
    for line in a:lines
        if line =~# '^@@'
            " @@ -old_start[,old_count] +new_start[,new_count] @@
            let m = matchlist(line, '^@@ -\d\+\%(,\d\+\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
            if !empty(m)
                let new_lnum = str2nr(m[1])
            endif
        elseif line[0] ==# '+'
            call add(hunks, {'lnum': new_lnum, 'type': 'WplusGGAdd'})
            let new_lnum += 1
        elseif line[0] ==# '-'
            " deleted lines don't advance new file lnum
            if new_lnum > 0
                call add(hunks, {'lnum': new_lnum, 'type': 'WplusGGDelete'})
            endif
        elseif line[0] ==# ' '
            let new_lnum += 1
        endif
    endfor
    " Merge adjacent adds that also had a delete → change
    let result = []
    let i = 0
    while i < len(hunks)
        let h = hunks[i]
        if h.type ==# 'WplusGGDelete' && i + 1 < len(hunks) && hunks[i + 1].type ==# 'WplusGGAdd' && hunks[i + 1].lnum == h.lnum
            call add(result, {'lnum': h.lnum, 'type': 'WplusGGChange'})
            let i += 2
            continue
        endif
        call add(result, h)
        let i += 1
    endwhile
    return result
endfunction

" ── async refresh ─────────────────────────────────────────────────────────

function! wplus#gitgutter#refresh(bufnr) abort
    let bufnr = a:bufnr == 0 ? bufnr('%') : a:bufnr
    let file  = bufname(bufnr)
    if empty(file) || !filereadable(file) | return | endif

    " Kill previous pending job for this buffer
    if has_key(s:pending, bufnr)
        try | call job_stop(s:pending[bufnr]) | catch | endtry
        unlet s:pending[bufnr]
    endif

    let lines  = []
    let Cb = function('s:on_diff_done', [bufnr, lines])
    let job = job_start(['git', 'diff', '--unified=0', 'HEAD', '--', file], {
        \ 'out_cb':  {_, l -> add(lines, l)},
        \ 'close_cb': Cb,
        \ 'err_cb':  {_ch, _msg -> 0},
        \ })
    let s:pending[bufnr] = job
    " Also capture branch name while we're here
    call s:update_branch(bufnr, file)
endfunction

function! s:on_diff_done(bufnr, lines, chan) abort
    unlet! s:pending[a:bufnr]
    if !bufloaded(a:bufnr) | return | endif
    " Clear old signs
    silent! call sign_unplace(s:sign_group, {'buffer': a:bufnr})
    let hunks = s:parse_diff(a:lines)
    let info = getbufinfo(a:bufnr)
    if empty(info) | return | endif
    let buflen = info[0].linecount
    let id = 1000
    for h in hunks
        if h.lnum >= 1 && h.lnum <= buflen
            silent! call sign_place(id, s:sign_group, h.type, a:bufnr, {'lnum': h.lnum})
            let id += 1
        endif
    endfor
    " Trigger statusline refresh for diagnostic counts
    if exists('#User#WplusGitGutterUpdate')
        doautocmd User WplusGitGutterUpdate
    endif
endfunction

function! s:update_branch(bufnr, file) abort
    let lines = []
    call job_start(['git', '-C', fnamemodify(a:file, ':h'), 'rev-parse', '--abbrev-ref', 'HEAD'], {
        \ 'out_cb':  {_, l -> add(lines, l)},
        \ 'close_cb': {_ -> s:set_branch(a:bufnr, lines)},
        \ 'err_cb':  {_ch, _msg -> 0},
        \ })
endfunction

function! s:set_branch(bufnr, lines) abort
    if bufloaded(a:bufnr) && !empty(a:lines)
        call setbufvar(a:bufnr, 'wplus_git_branch', trim(a:lines[0]))
        " nudge statusline redraw
        redrawstatus
    endif
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#gitgutter#setup() abort
    call s:init_highlights()
    call s:define_signs()

    augroup wplus_gitgutter
        autocmd!
        autocmd BufReadPost,BufWritePost,InsertLeave *
            \ call wplus#gitgutter#refresh(bufnr('%'))
        autocmd ColorScheme * call s:init_highlights()
    augroup END
endfunction
