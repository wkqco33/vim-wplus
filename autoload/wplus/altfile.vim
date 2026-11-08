" wplus/altfile.vim — toggle between header and source file (replaces a.vim)
" :A  — open alternate file in current window
" :AV — open in vertical split
" :AS — open in horizontal split

if exists('g:autoloaded_wplus_altfile') | finish | endif
let g:autoloaded_wplus_altfile = 1

" Map of extension → list of candidate alternate extensions (in priority order)
let s:alt_map = {
    \ 'c':   ['h'],
    \ 'cpp': ['h', 'hpp'],
    \ 'cc':  ['h', 'hh', 'hpp'],
    \ 'cxx': ['h', 'hpp'],
    \ 'h':   ['c', 'cpp', 'cc', 'cxx', 'm'],
    \ 'hpp': ['cpp', 'cc', 'cxx'],
    \ 'm':   ['h'],
    \ }

function! s:find_alternate() abort
    let l:ext  = expand('%:e')
    let l:base = expand('%:p:r')
    let l:dir  = expand('%:p:h')
    let l:tail = expand('%:t:r')

    " 1. Go: foo.go <-> foo_test.go
    if l:ext ==# 'go'
        if l:tail =~# '_test$'
            return l:dir . '/' . substitute(l:tail, '_test$', '', '') . '.go'
        endif
        return l:dir . '/' . l:tail . '_test.go'
    endif

    " 2. Python: foo.py <-> test_foo.py / foo_test.py
    if l:ext ==# 'py'
        if l:tail =~# '^test_'
            return l:dir . '/' . substitute(l:tail, '^test_', '', '') . '.py'
        elseif l:tail =~# '_test$'
            return l:dir . '/' . substitute(l:tail, '_test$', '', '') . '.py'
        endif
        for l:cand in [l:dir . '/test_' . l:tail . '.py', l:dir . '/' . l:tail . '_test.py']
            if filereadable(l:cand) | return l:cand | endif
        endfor
        return l:dir . '/test_' . l:tail . '.py'
    endif

    " 3. Dart: foo.dart <-> foo_test.dart
    if l:ext ==# 'dart'
        if l:tail =~# '_test$'
            let l:src_name = substitute(l:tail, '_test$', '', '') . '.dart'
            let l:lib_cand = substitute(l:dir, '/test\(/\|$\)', '/lib\1', '') . '/' . l:src_name
            if filereadable(l:lib_cand) | return l:lib_cand | endif
            return l:dir . '/' . l:src_name
        endif
        let l:tst_cand = substitute(l:dir, '/lib\(/\|$\)', '/test\1', '') . '/' . l:tail . '_test.dart'
        if filereadable(l:tst_cand) | return l:tst_cand | endif
        return l:dir . '/' . l:tail . '_test.dart'
    endif

    " 4. C/C++/ObjC header <-> source
    if !has_key(s:alt_map, l:ext) | return '' | endif
    for l:target_ext in s:alt_map[l:ext]
        let l:candidate = l:base . '.' . l:target_ext
        if filereadable(l:candidate) | return l:candidate | endif
        " Also check src/ <-> include/ sibling directories
        let l:swap_dir = l:dir =~# '/src\(/\|$\)'
            \ ? substitute(l:dir, '/src\(/\|$\)', '/include\1', '')
            \ : (l:dir =~# '/include\(/\|$\)' ? substitute(l:dir, '/include\(/\|$\)', '/src\1', '') : '')
        if !empty(l:swap_dir)
            let l:alt_cand = l:swap_dir . '/' . l:tail . '.' . l:target_ext
            if filereadable(l:alt_cand) | return l:alt_cand | endif
        endif
    endfor
    " Return best guess even if it doesn't exist yet
    return l:base . '.' . s:alt_map[l:ext][0]
endfunction

function! wplus#altfile#jump(cmd) abort
    let l:alt = s:find_alternate()
    if empty(l:alt)
        echohl WarningMsg | echo 'wplus-altfile: no alternate file for ' . expand('%:e') | echohl None
        return
    endif
    let l:act = empty(a:cmd) ? 'edit' : a:cmd
    execute l:act . ' ' . fnameescape(l:alt)
endfunction

function! wplus#altfile#switch(cmd) abort
    call wplus#altfile#jump(a:cmd)
endfunction

function! wplus#altfile#setup() abort
    command! -bar A  call wplus#altfile#jump('edit')
    command! -bar AV call wplus#altfile#jump('vsplit')
    command! -bar AS call wplus#altfile#jump('split')
endfunction
