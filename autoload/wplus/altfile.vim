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
    let ext  = expand('%:e')
    let base = expand('%:p:r')
    if !has_key(s:alt_map, ext) | return '' | endif
    for target_ext in s:alt_map[ext]
        let candidate = base . '.' . target_ext
        if filereadable(candidate) | return candidate | endif
    endfor
    " Return best guess even if it doesn't exist yet
    return base . '.' . s:alt_map[ext][0]
endfunction

function! wplus#altfile#jump(cmd) abort
    let alt = s:find_alternate()
    if empty(alt)
        echohl WarningMsg | echo 'wplus-altfile: no alternate file for ' . expand('%:e') | echohl None
        return
    endif
    execute a:cmd . ' ' . fnameescape(alt)
endfunction

function! wplus#altfile#setup() abort
    command! -bar A  call wplus#altfile#jump('edit')
    command! -bar AV call wplus#altfile#jump('vsplit')
    command! -bar AS call wplus#altfile#jump('split')
endfunction
