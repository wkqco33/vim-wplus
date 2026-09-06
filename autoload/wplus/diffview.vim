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

" ── diff buffer rendering ─────────────────────────────────────────────────

function! s:parse_diff_location(lines, lnum) abort
    if a:lnum < 1 || a:lnum > len(a:lines)
        return {}
    endif

    let l:hunk_idx = -1
    let l:new_start = 0
    let l:i = a:lnum - 1
    while l:i >= 0
        let l:line = a:lines[l:i]
        if l:line =~# '^@@'
            let l:m = matchlist(l:line, '^@@ -\d\+\%(,\d\+\)\? +\(\d\+\)')
            if !empty(l:m)
                let l:hunk_idx = l:i
                let l:new_start = str2nr(l:m[1])
                break
            endif
        endif
        let l:i -= 1
    endwhile

    if l:hunk_idx == -1 | return {} | endif

    let l:offset = 0
    let l:curr = l:hunk_idx + 1
    while l:curr < a:lnum - 1
        let l:prefix = a:lines[l:curr][0]
        if l:prefix !=# '-'
            let l:offset += 1
        endif
        let l:curr += 1
    endwhile

    let l:cur_line = a:lines[a:lnum - 1]
    let l:target_lnum = max([1, l:new_start + (l:cur_line[0] ==# '-' ? max([l:offset - 1, 0]) : l:offset)])

    let l:target_file = ''
    let l:i = l:hunk_idx
    while l:i >= 0
        let l:line = a:lines[l:i]
        if l:line =~# '^+++ '
            let l:target_file = substitute(l:line, '^+++ [ab]/', '', '')
            break
        endif
        let l:i -= 1
    endwhile

    if empty(l:target_file) | return {} | endif
    return {'file': l:target_file, 'lnum': l:target_lnum}
endfunction

function! s:on_jump() abort
    let l:target = s:parse_diff_location(getline(1, '$'), line('.'))
    if empty(l:target) || empty(l:target.file)
        return
    endif
    let l:root = get(b:, 'wplus_diff_root', '')
    let l:path = !empty(l:root) ? l:root . '/' . l:target.file : l:target.file
    
    wincmd p
    if bufnr('%') == s:diff_buf
        execute 'wincmd w'
    endif
    execute 'edit +' . l:target.lnum . ' ' . fnameescape(l:path)
endfunction

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
    nnoremap <buffer> <silent> <CR> :call <SID>on_jump()<CR>
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

    let l:root = wplus#util#find_git_root(fnamemodify(l:file, ':h'))
    if empty(l:root) | call wplus#util#warn_msg('diffview', 'Not a git repository') | return | endif

    let l:rel  = wplus#util#relpath(l:root, l:file)
    let l:args = get(a:, 1, '') ==# 'all'
        \ ? ['git', '-C', l:root, 'diff', 'HEAD']
        \ : ['git', '-C', l:root, 'diff', 'HEAD', '--', l:rel]

    call s:open_diff_buf()
    let b:wplus_diff_root = l:root

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

function! wplus#diffview#open_staged() abort
    let l:file = expand('%:p')
    if empty(l:file) | call wplus#util#warn_msg('diffview', 'No file') | return | endif

    let l:root = wplus#util#find_git_root(fnamemodify(l:file, ':h'))
    if empty(l:root) | call wplus#util#warn_msg('diffview', 'Not a git repository') | return | endif

    let l:rel  = wplus#util#relpath(l:root, l:file)
    let l:args = ['git', '-C', l:root, 'diff', '--staged', 'HEAD', '--', l:rel]

    call s:open_diff_buf()
    let b:wplus_diff_root = l:root

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

function! wplus#diffview#_test_parse_diff_location(lines, lnum) abort
    return s:parse_diff_location(a:lines, a:lnum)
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#diffview#setup() abort
    command! WdiffviewFile   call wplus#diffview#open()
    command! WdiffviewRepo   call wplus#diffview#open_all()
    command! WdiffviewStaged call wplus#diffview#open_staged()
    nnoremap <silent> <leader>gd :call wplus#diffview#open()<CR>
    nnoremap <silent> <leader>gD :call wplus#diffview#open_all()<CR>
endfunction
