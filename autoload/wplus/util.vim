" wplus/util.vim — Utility functions for error handling and common operations

if exists('g:autoloaded_wplus_util') | finish | endif
let g:autoloaded_wplus_util = 1

" Standard error message format: [module] message
function! wplus#util#error(message) abort
    echohl ErrorMsg
    echomsg a:message
    echohl None
endfunction

function! wplus#util#warn(message) abort
    echohl WarningMsg
    echomsg a:message
    echohl None
endfunction

function! wplus#util#info(message) abort
    echohl None
    echomsg a:message
endfunction

" Log message with module prefix
function! wplus#util#error_msg(module, message) abort
    call wplus#util#error('[wplus-' . a:module . '] ' . a:message)
endfunction

function! wplus#util#warn_msg(module, message) abort
    call wplus#util#warn('[wplus-' . a:module . '] ' . a:message)
endfunction

function! wplus#util#info_msg(module, message) abort
    call wplus#util#info('[wplus-' . a:module . '] ' . a:message)
endfunction
