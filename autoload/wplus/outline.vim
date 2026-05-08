" wplus/outline.vim — Code outline sidebar using ctags (replaces tagbar)
" Requires: ctags (universal-ctags or exuberant-ctags)
" Mappings:
"   <leader>o  — toggle outline sidebar
"   <CR>       — jump to symbol (inside sidebar)
"   R          — refresh
"   q          — close

if exists('g:autoloaded_wplus_outline') | finish | endif
let g:autoloaded_wplus_outline = 1

let s:buf_name  = '__WplusOutline__'
let s:outline_buf = -1
let s:symbols   = []   " [{name, kind, lnum}, ...]
let s:src_buf   = -1   " buffer being outlined

" kind 코드 → 표시 기호 (ctags universal/exuberant 공통)
let s:kind_icon = {
    \ 'f': 'f', 'F': 'f', 'm': 'm', 'M': 'm',
    \ 'c': 'c', 'C': 'c', 's': 's', 'S': 's',
    \ 't': 't', 'T': 't', 'g': 'g',
    \ 'v': 'v', 'V': 'v', 'e': 'e',
    \ 'n': 'n', 'p': 'f', 'i': 'i',
    \ }

" ── ctags 파싱 ────────────────────────────────────────────────────────────

function! s:get_symbols(file) abort
    if !executable('ctags') | return [] | endif
    let l:raw = systemlist(
        \ 'ctags -f - --sort=no --fields=+nK ' . shellescape(a:file) . ' ' . wplus#util#null_redirect())
    let l:syms = []
    for l:line in l:raw
        if l:line[0] ==# '!' | continue | endif
        let l:parts = split(l:line, "\t")
        if len(l:parts) < 3 | continue | endif
        let l:name = l:parts[0]
        let l:lnum = 0
        let l:kind = '?'
        for l:field in l:parts[3:]
            if l:field =~# '^line:'
                let l:lnum = str2nr(l:field[5:])
            elseif l:field =~# '^kind:'
                let l:kind = l:field[5:]
            elseif len(l:field) == 1
                let l:kind = l:field
            endif
        endfor
        if l:lnum > 0
            call add(l:syms, {'name': l:name, 'kind': l:kind, 'lnum': l:lnum})
        endif
    endfor
    return sort(l:syms, {a, b -> a.lnum - b.lnum})
endfunction

" ── 렌더링 ────────────────────────────────────────────────────────────────

function! s:render() abort
    let l:winid = bufwinid(s:outline_buf)
    if l:winid == -1 | return | endif

    let l:file = bufname(s:src_buf)
    let l:short = fnamemodify(l:file, ':t')
    let l:lines = ['[' . l:short . ']']
    for l:sym in s:symbols
        let l:icon = get(s:kind_icon, l:sym.kind, '?')
        call add(l:lines, printf('  %s  %s', l:icon, l:sym.name))
    endfor
    if empty(s:symbols)
        call add(l:lines, '  (no symbols found)')
    endif

    call win_execute(l:winid, 'setlocal modifiable')
    call win_execute(l:winid, 'silent %delete _')
    call setbufline(s:outline_buf, 1, l:lines)
    call win_execute(l:winid, 'setlocal nomodifiable')
endfunction

" ── 사이드바 초기화 ───────────────────────────────────────────────────────

function! s:init_buffer() abort
    setlocal buftype=nofile bufhidden=hide noswapfile
    setlocal nobuflisted nomodifiable nonumber norelativenumber
    setlocal cursorline winfixwidth nowrap

    syntax clear
    syntax match WplusOutlineHeader /^\[.*\]$/
    syntax match WplusOutlineKind   /^\s\+\S/
    hi default link WplusOutlineHeader Title
    hi default link WplusOutlineKind   Keyword

    nnoremap <buffer> <silent> <CR> :call <SID>on_jump()<CR>
    nnoremap <buffer> <silent> R    :call <SID>on_refresh()<CR>
    nnoremap <buffer> <silent> q    :close<CR>
endfunction

function! s:on_jump() abort
    let l:lnum = line('.')
    if l:lnum <= 1 || l:lnum > len(s:symbols) + 1 | return | endif
    let l:sym = s:symbols[l:lnum - 2]
    " Jump to source buffer
    let l:src_winid = bufwinid(s:src_buf)
    if l:src_winid == -1
        wincmd l
    else
        call win_gotoid(l:src_winid)
    endif
    call cursor(l:sym.lnum, 1)
    normal! zz
endfunction

function! s:on_refresh() abort
    let l:file = expand('#' . s:src_buf . ':p')
    let s:symbols = s:get_symbols(l:file)
    call s:render()
endfunction

" ── 토글 ──────────────────────────────────────────────────────────────────

function! wplus#outline#toggle() abort
    let l:winid = bufwinid(s:outline_buf)
    if l:winid != -1
        let l:cur = win_getid()
        if win_gotoid(l:winid)
            close
            if l:cur != l:winid | call win_gotoid(l:cur) | endif
        endif
        return
    endif
    call s:open()
endfunction

function! s:open() abort
    let s:src_buf = bufnr('%')
    let l:file    = expand('%:p')
    let s:symbols = s:get_symbols(l:file)

    let l:existing = bufnr(s:buf_name)
    execute 'topleft 30vsplit'
    if l:existing != -1 && bufexists(l:existing)
        execute 'buffer' l:existing
    else
        enew
        silent! execute 'file ' . s:buf_name
    endif
    let s:outline_buf = bufnr('%')
    call s:init_buffer()
    call s:render()

    augroup wplus_outline_src
        autocmd!
        execute 'autocmd BufWritePost <buffer=' . s:src_buf . '> call wplus#outline#refresh()'
    augroup END
endfunction

function! wplus#outline#refresh() abort
    if s:src_buf == -1 | return | endif
    let l:file = expand('#' . s:src_buf . ':p')
    let s:symbols = s:get_symbols(l:file)
    call s:render()
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#outline#setup() abort
    command! WoutlineToggle call wplus#outline#toggle()
    nnoremap <silent> <leader>o :WoutlineToggle<CR>
endfunction
