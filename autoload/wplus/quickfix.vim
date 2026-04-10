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

    " Build unique file list from quickfix
    let l:files = {}
    for l:item in l:qflist
        if l:item.bufnr > 0
            let l:files[l:item.bufnr] = 1
        endif
    endfor

    let l:count = 0
    for l:bufnr in keys(l:files)
        let l:fname = bufname(str2nr(l:bufnr))
        if empty(l:fname) | continue | endif
        execute 'keepjumps keeppatterns bufdo if bufnr("%") == ' . l:bufnr
            \ . ' | silent! %s/' . escape(l:from, '/') . '/'
            \ . escape(l:to, '/') . '/g | let g:_wplus_rc = v:count | endif'
        let l:count += get(g:, '_wplus_rc', 0)
        unlet! g:_wplus_rc
    endfor

    " Simpler approach: use cdo
    execute 'cdo keepjumps s/' . escape(l:from, '/') . '/' . escape(l:to, '/') . '/ge | update'
    echomsg '[wplus] project replace done: ' . l:from . ' → ' . l:to
endfunction
