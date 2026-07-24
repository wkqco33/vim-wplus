" wplus/gitgutter.vim — sign-column git diff markers (replaces vim-gitgutter)
" Uses job_start() for async git diff; sign_place() to mark changes.

if exists('g:autoloaded_wplus_gitgutter') | finish | endif
let g:autoloaded_wplus_gitgutter = 1

let g:wplus_gitgutter_sign_add    = get(g:, 'wplus_gitgutter_sign_add',    '┃')
let g:wplus_gitgutter_sign_change = get(g:, 'wplus_gitgutter_sign_change', '┃')
let g:wplus_gitgutter_sign_delete = get(g:, 'wplus_gitgutter_sign_delete', '▁')

let s:sign_group = 'wplus_gitgutter'
let s:pending    = {}   " bufnr → job handle
let s:job_data   = {}   " job → {bufnr, lines}

function! s:git_relpath(root, file) abort
    return a:file[: len(a:root)] ==# a:root . '/' ? a:file[len(a:root) + 1 :] : a:file
endfunction

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

" ── unified-diff hunk parser → list of {new_start, new_count, lines} ─────

function! s:parse_hunks(lines) abort
    let l:hunks = []
    let l:current = {}
    for l:line in a:lines
        if l:line =~# '^@@'
            if !empty(l:current)
                call add(l:hunks, l:current)
            endif
            let l:m = matchlist(l:line, '^@@ -\d\+\%(,\d\+\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
            if !empty(l:m)
                let l:current = {
                    \ 'new_start': str2nr(l:m[1]),
                    \ 'new_count': empty(l:m[2]) ? 1 : str2nr(l:m[2]),
                    \ 'lines': [l:line],
                    \ }
            else
                let l:current = {}
            endif
        elseif !empty(l:current)
            call add(l:current.lines, l:line)
        endif
    endfor
    if !empty(l:current)
        call add(l:hunks, l:current)
    endif
    return l:hunks
endfunction

" ── async refresh ─────────────────────────────────────────────────────────

function! s:channel_key(channel) abort
    try
        let l:info = ch_info(a:channel)
        return string(get(l:info, 'id', a:channel))
    catch
        return string(a:channel)
    endtry
endfunction

function! wplus#gitgutter#refresh(bufnr) abort
    let bufnr = a:bufnr == 0 ? bufnr('%') : a:bufnr
    let file  = bufname(bufnr)
    if empty(file) || !filereadable(file) | return | endif
    if get(g:, 'wplus_gitgutter_disable_on_large_files', 1)
        if getfsize(file) > get(g:, 'wplus_gitgutter_file_size_limit', 500000) | return | endif
    endif
    let root = wplus#util#find_git_root(fnamemodify(file, ':p:h'))
    if empty(root)
        silent! call sign_unplace(s:sign_group, {'buffer': bufnr})
        call setbufvar(bufnr, 'wplus_git_branch', '')
        return
    endif
    let relfile = s:git_relpath(root, fnamemodify(file, ':p'))

    " Kill previous pending job for this buffer
    if has_key(s:pending, bufnr)
        try | call job_stop(s:pending[bufnr]) | catch | endtry
        unlet s:pending[bufnr]
    endif

    let lines  = []
    let Cb = function('s:on_diff_complete')
    let job = job_start(['git', '-C', root, 'diff', '--unified=0', 'HEAD', '--', relfile], {
        \ 'out_cb':  {_, l -> add(lines, l)},
        \ 'close_cb': Cb,
        \ 'err_cb':  {_ch, _msg -> 0},
        \ })

    let s:pending[bufnr] = job
    " Store data for close_cb to access
    let s:job_data[s:channel_key(job_getchannel(job))] = {'bufnr': bufnr, 'lines': lines}
    " Also capture branch name while we're here
    call s:update_branch(bufnr, root)
endfunction

function! s:on_diff_complete(channel) abort
    " Find job data for this channel
    let l:key = s:channel_key(a:channel)
    if has_key(s:job_data, l:key)
        let data = remove(s:job_data, l:key)
        call s:on_diff_done(data.bufnr, data.lines, a:channel)
    endif
endfunction

function! s:on_diff_done(bufnr, lines, job) abort
    if has_key(s:pending, a:bufnr)
        unlet s:pending[a:bufnr]
    endif
    if !bufloaded(a:bufnr) | return | endif
    " Clear old signs
    silent! call sign_unplace(s:sign_group, {'buffer': a:bufnr})
    let hunks = s:parse_diff(a:lines)
    let info = getbufinfo(a:bufnr)
    if empty(info) | return | endif
    let buflen = info[0].linecount
    
    " Batch sign placement for better performance
    let l:signs = []
    let id = 1000
    for h in hunks
        if h.lnum >= 1 && h.lnum <= buflen
            call add(l:signs, {'id': id, 'group': s:sign_group, 'name': h.type, 'buffer': a:bufnr, 'lnum': h.lnum})
            let id += 1
        endif
    endfor
    if !empty(l:signs)
        call sign_placelist(l:signs)
    endif
    
    " Store hunk data for navigation/preview/staging
    call setbufvar(a:bufnr, 'wplus_gitgutter_hunks', s:parse_hunks(a:lines))
    " Store file header lines (before first @@) for patch construction
    let l:header = []
    for l:line in a:lines
        if l:line =~# '^@@' | break | endif
        call add(l:header, l:line)
    endfor
    call setbufvar(a:bufnr, 'wplus_gitgutter_diff_header', l:header)
    " Trigger statusline refresh for diagnostic counts
    if exists('#User#WplusGitGutterUpdate')
        doautocmd User WplusGitGutterUpdate
    endif
endfunction

function! s:update_branch(bufnr, root) abort
    let lines = []
    let job = job_start(['git', '-C', a:root, 'rev-parse', '--abbrev-ref', 'HEAD'], {
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

" ── hunk helpers ──────────────────────────────────────────────────────────

function! s:find_hunk_at(lnum) abort
    let l:hunks = getbufvar(bufnr('%'), 'wplus_gitgutter_hunks', [])
    for l:h in l:hunks
        let l:end = l:h.new_start + max([l:h.new_count - 1, 0])
        if a:lnum >= l:h.new_start && a:lnum <= l:end
            return l:h
        endif
    endfor
    return {}
endfunction

function! wplus#gitgutter#next_hunk() abort
    let l:hunks = getbufvar(bufnr('%'), 'wplus_gitgutter_hunks', [])
    let l:lnum = line('.')
    for l:h in l:hunks
        if l:h.new_start > l:lnum
            execute l:h.new_start
            return
        endif
    endfor
    call wplus#util#warn_msg('gitgutter', 'No more hunks')
endfunction

function! wplus#gitgutter#prev_hunk() abort
    let l:hunks = getbufvar(bufnr('%'), 'wplus_gitgutter_hunks', [])
    let l:lnum = line('.')
    let l:found = {}
    for l:h in l:hunks
        if l:h.new_start < l:lnum
            let l:found = l:h
        endif
    endfor
    if !empty(l:found)
        execute l:found.new_start
    else
        call wplus#util#warn_msg('gitgutter', 'No previous hunks')
    endif
endfunction

function! wplus#gitgutter#preview_hunk() abort
    let l:h = s:find_hunk_at(line('.'))
    if empty(l:h)
        call wplus#util#warn_msg('gitgutter', 'No hunk at cursor')
        return
    endif
    call popup_atcursor(l:h.lines, {
        \ 'title': ' Hunk Preview ',
        \ 'padding': [0,1,0,1],
        \ 'border': [1,1,1,1],
        \ 'moved': 'any',
        \ 'highlight': 'Normal',
        \ 'borderhighlight': ['Special'],
        \ 'maxwidth': float2nr(&columns * 0.7),
        \ 'maxheight': 20,
        \ })
endfunction

function! wplus#gitgutter#stage_hunk() abort
    let l:bufnr = bufnr('%')
    let l:h = s:find_hunk_at(line('.'))
    if empty(l:h)
        call wplus#util#warn_msg('gitgutter', 'No hunk at cursor')
        return
    endif
    let l:file = fnamemodify(bufname(l:bufnr), ':p')
    let l:root = wplus#util#find_git_root(fnamemodify(l:file, ':h'))
    if empty(l:root)
        call wplus#util#error_msg('gitgutter', 'Not in a git repository')
        return
    endif
    let l:header = getbufvar(l:bufnr, 'wplus_gitgutter_diff_header', [])
    if empty(l:header)
        call wplus#util#error_msg('gitgutter', 'No diff header available — save the file first')
        return
    endif
    let l:tmp = tempname()
    call writefile(l:header + l:h.lines, l:tmp)
    let l:out = system('git -C ' . shellescape(l:root) . ' apply --cached ' . shellescape(l:tmp))
    call delete(l:tmp)
    if v:shell_error != 0
        call wplus#util#error_msg('gitgutter', 'Stage failed: ' . trim(l:out))
    else
        call wplus#util#info_msg('gitgutter', 'Hunk staged')
        call wplus#gitgutter#refresh(l:bufnr)
    endif
endfunction

function! wplus#gitgutter#revert_hunk() abort
    let l:bufnr = bufnr('%')
    let l:h = s:find_hunk_at(line('.'))
    if empty(l:h)
        call wplus#util#warn_msg('gitgutter', 'No hunk at cursor')
        return
    endif
    let l:file = fnamemodify(bufname(l:bufnr), ':p')
    let l:root = wplus#util#find_git_root(fnamemodify(l:file, ':h'))
    if empty(l:root)
        call wplus#util#error_msg('gitgutter', 'Not in a git repository')
        return
    endif
    let l:header = getbufvar(l:bufnr, 'wplus_gitgutter_diff_header', [])
    if empty(l:header)
        call wplus#util#error_msg('gitgutter', 'No diff header available — save the file first')
        return
    endif
    let l:tmp = tempname()
    call writefile(l:header + l:h.lines, l:tmp)
    let l:out = system('git -C ' . shellescape(l:root) . ' apply --reverse ' . shellescape(l:tmp))
    call delete(l:tmp)
    if v:shell_error != 0
        call wplus#util#error_msg('gitgutter', 'Revert failed: ' . trim(l:out))
    else
        silent execute 'edit!'
        call wplus#util#info_msg('gitgutter', 'Hunk reverted')
        call wplus#gitgutter#refresh(l:bufnr)
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
        autocmd BufDelete * call s:on_buf_delete()
        autocmd ColorScheme * call s:init_highlights()
        autocmd VimLeavePre * call s:cleanup_jobs()
    augroup END

    command! WplusGitStageHunk call wplus#gitgutter#stage_hunk()
    command! WplusGitRevertHunk call wplus#gitgutter#revert_hunk()

    nnoremap <silent> ]h :call wplus#gitgutter#next_hunk()<CR>
    nnoremap <silent> [h :call wplus#gitgutter#prev_hunk()<CR>
    nnoremap <silent> <leader>hp :call wplus#gitgutter#preview_hunk()<CR>
    nnoremap <silent> <leader>hs :call wplus#gitgutter#stage_hunk()<CR>
    nnoremap <silent> <leader>hr :call wplus#gitgutter#revert_hunk()<CR>
endfunction

function! s:on_buf_delete() abort
    let l:bufnr = str2nr(expand('<abuf>'))
    if has_key(s:pending, l:bufnr)
        try
            call job_stop(s:pending[l:bufnr])
        catch
        endtry
        unlet s:pending[l:bufnr]
    endif
endfunction

function! s:cleanup_jobs() abort
    for l:bufnr in keys(s:pending)
        try
            call job_stop(s:pending[l:bufnr])
        catch
        endtry
    endfor
    let s:pending = {}
endfunction
