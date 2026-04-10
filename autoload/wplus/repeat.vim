" wplus/repeat.vim — make plugin operations repeatable with '.'
" Compatible with tpope/vim-repeat API: repeat#set(seq, count)

if exists('g:autoloaded_wplus_repeat') | finish | endif
let g:autoloaded_wplus_repeat = 1

let s:seq   = ''
let s:count = 1

function! wplus#repeat#setup() abort
    " Override the . command to replay our stored sequence when set
    nnoremap <silent> . :<C-u>call wplus#repeat#run(v:count)<CR>
endfunction

" Called by plugin operations to register a repeatable sequence.
" Usage: call wplus#repeat#set("\<Plug>MyMap", v:count1)
function! wplus#repeat#set(seq, count) abort
    let s:seq   = a:seq
    let s:count = a:count
    " Also register with vim-repeat if it happens to be installed
    silent! call repeat#set(a:seq, a:count)
endfunction

function! wplus#repeat#run(count) abort
    if empty(s:seq)
        " Fall back to built-in '.' behaviour
        normal! .
        return
    endif
    let cnt = a:count > 0 ? a:count : s:count
    execute 'normal ' . cnt . s:seq
endfunction
