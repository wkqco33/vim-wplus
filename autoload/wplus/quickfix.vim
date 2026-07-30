" wplus/quickfix.vim — Quickfix/LocList toggle + navigation + project replace
"
" Quickfix:
"   <leader>xq  — toggle quickfix window
"   ]q / [q     — next/prev quickfix item
"   ]Q / [Q     — last/first quickfix item
"
" Location list (buffer-local, used by ALE/coc):
"   <leader>xl  — toggle location list
"   ]l / [l     — next/prev location item
"
" Project-wide search & replace:
"   <leader>xr  — prompt for pattern & replacement, runs across quickfix files

function! wplus#quickfix#setup() abort
    nnoremap <silent> <leader>xq :call wplus#quickfix#toggle_qf()<CR>
    nnoremap <silent> <leader>xl :call wplus#quickfix#toggle_loc()<CR>

    nnoremap <silent> ]q :call wplus#quickfix#nav_qf(1)<CR>
    nnoremap <silent> [q :call wplus#quickfix#nav_qf(-1)<CR>
    nnoremap <silent> ]Q :clast<CR>
    nnoremap <silent> [Q :cfirst<CR>

    nnoremap <silent> ]l :call wplus#quickfix#nav_loc(1)<CR>
    nnoremap <silent> [l :call wplus#quickfix#nav_loc(-1)<CR>

    nnoremap <leader>xr :call wplus#quickfix#project_replace()<CR>

    " Auto-open quickfix after grep/vimgrep
    augroup wplus_quickfix
        autocmd!
        autocmd QuickFixCmdPost [^l]* cwindow
        autocmd QuickFixCmdPost l*    lwindow
    augroup END
endfunction

" A bar has to be escaped too, not just the delimiter and backslash: inside
" :execute, an unescaped | ends the :substitute early, so the trailing
" '| update' was silently absorbed into the replacement text.
function! s:escape_sub_pattern(text) abort
    return escape(a:text, '\/|')
endfunction

function! s:escape_sub_replacement(text) abort
    return escape(a:text, '\/&~|')
endfunction

function! s:collect_quickfix_files(qflist) abort
    let l:files = {}
    for l:item in a:qflist
        let l:name = get(l:item, 'filename', '')
        if empty(l:name) && get(l:item, 'bufnr', 0) > 0
            let l:name = bufname(l:item.bufnr)
        endif
        if !empty(l:name)
            let l:files[fnamemodify(l:name, ':p')] = 1
        endif
    endfor
    return sort(keys(l:files))
endfunction

function! s:replace_mode() abort
    let l:choice = confirm('Replace mode?', '&Apply\n&Confirm\n&Preview\n&Cancel', 1)
    return l:choice == 1 ? 'apply' : (l:choice == 2 ? 'confirm' : (l:choice == 3 ? 'preview' : 'cancel'))
endfunction

function! s:preview_replace(files, from, to) abort
    echomsg printf('[wplus] preview: %d files, %s -> %s', len(a:files), a:from, a:to)
    if !empty(a:files)
        echo join(a:files[: min([len(a:files), 5]) - 1], "\n")
    endif
endfunction

function! wplus#quickfix#run_replace(mode, from, to) abort
    let l:qflist = getqflist()
    let l:files = s:collect_quickfix_files(l:qflist)
    if a:mode ==# 'preview'
        call s:preview_replace(l:files, a:from, a:to)
        return
    endif

    let l:pattern = s:escape_sub_pattern(a:from)
    let l:replacement = s:escape_sub_replacement(a:to)
    let l:flags = a:mode ==# 'confirm' ? 'gce' : 'ge'
    " Two separate :cfdo passes rather than one bar-joined command, so a bar in
    " the user's input cannot detach ':update' and leave every file unsaved.
    execute 'cfdo keepjumps keeppatterns silent %s/' . l:pattern . '/' . l:replacement . '/' . l:flags
    cfdo silent update
    echomsg '[wplus] project replace done: ' . a:from . ' → ' . a:to . ' (' . a:mode . ')'
endfunction

" ── quickfix toggle ───────────────────────────────────────────────────────

function! wplus#quickfix#toggle_qf() abort
    for l:win in range(1, winnr('$'))
        if getwinvar(l:win, '&buftype') ==# 'quickfix'
            let l:info = getwininfo(win_getid(l:win))[0]
            if !l:info.loclist
                cclose
                return
            endif
        endif
    endfor
    copen
endfunction

function! wplus#quickfix#toggle_loc() abort
    for l:win in range(1, winnr('$'))
        if getwinvar(l:win, '&buftype') ==# 'quickfix'
            let l:info = getwininfo(win_getid(l:win))[0]
            if l:info.loclist
                lclose
                return
            endif
        endif
    endfor
    silent! lopen
endfunction

" ── navigation with wrap ─────────────────────────────────────────────────

function! wplus#quickfix#nav_qf(dir) abort
    let l:list = getqflist()
    if empty(l:list) | return | endif
    if a:dir > 0
        try | cnext | catch | cfirst | endtry
    else
        try | cprev | catch | clast  | endtry
    endif
    normal! zz
endfunction

function! wplus#quickfix#nav_loc(dir) abort
    let l:list = getloclist(0)
    if empty(l:list) | return | endif
    if a:dir > 0
        try | lnext | catch | lfirst | endtry
    else
        try | lprev | catch | llast  | endtry
    endif
    normal! zz
endfunction

" ── project-wide search & replace ────────────────────────────────────────

function! wplus#quickfix#project_replace() abort
    let l:qflist = getqflist()
    if empty(l:qflist)
        echohl WarningMsg
        echomsg '[wplus] quickfix list is empty. Run :Rg or :grep first.'
        echohl None
        return
    endif

    let l:from = input('Search pattern  : ')
    if empty(l:from) | return | endif
    let l:to   = input('Replace with    : ')
    let l:mode = s:replace_mode()
    if l:mode ==# 'cancel' | return | endif
    call wplus#quickfix#run_replace(l:mode, l:from, l:to)
endfunction
