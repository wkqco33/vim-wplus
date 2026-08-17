" wplus/ai/ui.vim — AI preview popup and split result management

if exists('g:autoloaded_wplus_ai_ui') | finish | endif
let g:autoloaded_wplus_ai_ui = 1

let s:ai_preview_apply = v:null

" Show a:lines in a centered popup highlighted as a:ft. On accept, call
" a:ApplyFn (a zero-arg partial with all context already bound); on
" discard, drop it. Used by every AI command below so a
" response is never written to a buffer/register without explicit accept.
function! wplus#ai#ui#open_preview(ft, lines, ApplyFn) abort
    let s:ai_preview_apply = a:ApplyFn
    if !exists('*popup_create')
        if !empty(a:ApplyFn) | call a:ApplyFn() | endif
        return
    endif
    let l:header = '[wplus-ai] Enter/a = apply   Esc/q = discard'
    let l:width  = float2nr(&columns * 0.6)
    let l:height = min([len(a:lines) + 2, float2nr(&lines * 0.6)])
    let l:winid = popup_create([l:header, repeat('─', max([min([l:width - 4, 60]), 1]))] + a:lines, {
        \ 'title': ' AI Preview ',
        \ 'line': (&lines - l:height) / 2,
        \ 'col': (&columns - l:width) / 2,
        \ 'minwidth': l:width, 'maxwidth': l:width,
        \ 'minheight': l:height, 'maxheight': l:height,
        \ 'border': [1, 1, 1, 1],
        \ 'padding': [0, 1, 0, 1],
        \ 'filter': 'wplus#ai#preview_filter',
        \ 'mapping': 0,
        \ })
    call setbufvar(winbufnr(l:winid), '&filetype', a:ft)
endfunction

function! wplus#ai#ui#preview_filter(winid, key) abort
    call popup_close(a:winid)
    let l:Apply = s:ai_preview_apply
    let s:ai_preview_apply = v:null
    if a:key ==# "\<CR>" || a:key ==? 'a'
        if !empty(l:Apply) | call l:Apply() | endif
    else
        call wplus#util#info_msg('ai', 'discarded')
    endif
    return 1
endfunction

" Open a dedicated read-only split to display AI review/explain output.
function! wplus#ai#ui#open_result_split(ft, lines, title) abort
    " Reuse an existing wplus-ai-result window if one is visible.
    for l:win in range(1, winnr('$'))
        if getwinvar(l:win, 'wplus_ai_result', 0)
            execute l:win . 'wincmd w'
            setlocal modifiable
            silent %delete _
            call setline(1, a:lines)
            setlocal nomodifiable
            return
        endif
    endfor
    botright 15new
    let w:wplus_ai_result = 1
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    execute 'setlocal filetype=' . a:ft
    setlocal modifiable
    call setline(1, a:lines)
    setlocal nomodifiable
    execute 'setlocal statusline=\ 🤖\ ' . escape(a:title, ' \')
    nnoremap <buffer> <silent> q :close<CR>
endfunction

function! s:apply_insert_after(bufnr, lnum, lines) abort
    if !bufloaded(a:bufnr) | return | endif
    call appendbufline(a:bufnr, a:lnum, a:lines)
    call wplus#util#info_msg('ai', 'response inserted')
endfunction

function! s:apply_replace_range(bufnr, start, end, lines) abort
    if !bufloaded(a:bufnr) | return | endif
    call deletebufline(a:bufnr, a:start, a:end)
    call appendbufline(a:bufnr, a:start - 1, a:lines)
    call wplus#util#info_msg('ai', 'replaced')
endfunction

function! s:apply_commit(msg) abort
    call setreg('"', a:msg)
    if has('clipboard') | silent! call setreg('+', a:msg) | endif
    if &filetype ==# 'gitcommit'
        call append(0, split(a:msg, "\n"))
        call wplus#util#info_msg('ai', 'commit message inserted')
    else
        call wplus#util#info_msg('ai', 'commit message copied to register "')
    endif
endfunction

function! wplus#ai#ui#preview_insert_after(bufnr, lnum, content) abort
    let l:lines = split(a:content, "\n")
    if empty(l:lines) | call wplus#util#warn_msg('ai', 'empty response') | return | endif
    call wplus#ai#ui#open_preview(getbufvar(a:bufnr, '&filetype'), l:lines,
        \ function('s:apply_insert_after', [a:bufnr, a:lnum, l:lines]))
endfunction

function! wplus#ai#ui#preview_replace_range(bufnr, start, end, content) abort
    let l:lines = split(a:content, "\n")
    if empty(l:lines) | call wplus#util#warn_msg('ai', 'empty response') | return | endif
    call wplus#ai#ui#open_preview(getbufvar(a:bufnr, '&filetype'), l:lines,
        \ function('s:apply_replace_range', [a:bufnr, a:start, a:end, l:lines]))
endfunction

function! wplus#ai#ui#preview_commit(content) abort
    let l:msg = wplus#ai#security#clean_commit_message(a:content)
    if empty(l:msg) | call wplus#util#warn_msg('ai', 'empty commit message') | return | endif
    call wplus#ai#ui#open_preview('gitcommit', split(l:msg, "\n"), function('s:apply_commit', [l:msg]))
endfunction

function! wplus#ai#ui#show_review_result(ft, content, title) abort
    call wplus#ai#ui#open_result_split('markdown', split(a:content, "\n"), a:title)
endfunction
