" wplus/root.vim — automatic project root detection

if exists('g:autoloaded_wplus_root') | finish | endif
let g:autoloaded_wplus_root = 1

let s:root_cache = {}

function! wplus#root#find_root() abort
    let l:dir = expand('%:p:h')
    " Skip empty, non-file, or special buffers
    if empty(l:dir) || !isdirectory(l:dir) || &buftype != '' | return '' | endif
    
    if has_key(s:root_cache, l:dir)
        return s:root_cache[l:dir]
    endif

    let l:markers = ['.git', 'go.mod', 'Makefile', 'package.json', 'Cargo.toml', '.geminiignore', '.wplus.vim']
    let l:curr = l:dir
    let l:prev = ''
    
    while l:curr != l:prev
        for l:marker in l:markers
            if filereadable(l:curr . '/' . l:marker) || isdirectory(l:curr . '/' . l:marker)
                let s:root_cache[l:dir] = l:curr
                return l:curr
            endif
        endfor
        let l:prev = l:curr
        let l:curr = fnamemodify(l:curr, ':h')
    endwhile
    
    let s:root_cache[l:dir] = ''
    return ''
endfunction

function! wplus#root#change_dir() abort
    let l:root = wplus#root#find_root()
    if !empty(l:root) && l:root != getcwd()
        " Use silent to avoid messages on every buffer switch
        silent! execute 'lcd ' . fnameescape(l:root)
    endif
endfunction

function! wplus#root#clear_cache() abort
    let s:root_cache = {}
endfunction

function! wplus#root#find_project_root() abort
    return wplus#root#find_root()
endfunction

function! wplus#root#setup() abort
    augroup WplusRoot
        autocmd!
        autocmd BufEnter,BufWinEnter * call wplus#root#change_dir()
        autocmd DirChanged           * call wplus#root#clear_cache()
    augroup END
endfunction
