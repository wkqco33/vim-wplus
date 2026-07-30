" wplus/repeat.vim — forward repeatable operations to tpope/vim-repeat
"
" This module deliberately does NOT map '.'. It used to, and the mapping was
" unconditional and never cleared its stored sequence: after a single `gcc`,
" every subsequent '.' in the session replayed the comment toggle instead of
" the user's actual last change.
"
" Doing this correctly requires tracking b:changedtick to tell "the plugin ran
" last" from "a normal edit ran last" -- which is what vim-repeat already does.
" So we forward to it when present and otherwise leave '.' alone. Native '.'
" handling nothing is strictly better than '.' handling the wrong thing.

if exists('g:autoloaded_wplus_repeat') | finish | endif
let g:autoloaded_wplus_repeat = 1

" Register a repeatable sequence. Called by commentary and surround.
" No-op unless tpope/vim-repeat is installed.
"
" Usage: call wplus#repeat#set("\<Plug>MyMap", v:count1)
function! wplus#repeat#set(seq, count) abort
    silent! call repeat#set(a:seq, a:count)
endfunction
