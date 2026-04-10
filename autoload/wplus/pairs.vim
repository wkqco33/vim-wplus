" wplus/pairs.vim — auto bracket/quote completion (replaces auto-pairs)
" Features: auto-close, auto-delete pair on backspace, skip closing char

if exists('g:autoloaded_wplus_pairs') | finish | endif
let g:autoloaded_wplus_pairs = 1

" Pair map: opener → closer
let s:pairs = get(g:, 'wplus_pairs_map', {
    \ '(': ')',
    \ '[': ']',
    \ '{': '}',
    \ '"': '"',
    \ "'": "'",
    \ '`': '`',
    \ })

" ── helpers ───────────────────────────────────────────────────────────────

function! s:char_before() abort
    let col = col('.') - 1
    return col > 0 ? getline('.')[col - 2] : ''
endfunction

function! s:char_at() abort
    return getline('.')[col('.') - 1]
endfunction

function! s:is_escaped() abort
    let col = col('.') - 1
    if col < 1 | return 0 | endif
    let line = getline('.')
    let backslashes = 0
    let i = col - 2
    while i >= 0 && line[i] ==# '\'
        let backslashes += 1
        let i -= 1
    endwhile
    return backslashes % 2 == 1
endfunction

" ── open key handler ──────────────────────────────────────────────────────

function! wplus#pairs#open(open, close) abort
    if s:is_escaped() | return a:open | endif
    " For symmetric pairs (quotes) check if we're closing
    if a:open ==# a:close
        if s:char_at() ==# a:close
            return "\<Right>"  " skip over
        endif
        " Don't auto-pair inside a word
        let after = s:char_at()
        if after =~# '\w' | return a:open | endif
    endif
    return a:open . a:close . "\<Left>"
endfunction

" ── close key handler ─────────────────────────────────────────────────────

function! wplus#pairs#close(close) abort
    if s:char_at() ==# a:close
        return "\<Right>"  " skip over existing closing char
    endif
    return a:close
endfunction

" ── backspace handler ─────────────────────────────────────────────────────

function! wplus#pairs#backspace() abort
    let before = s:char_before()
    let after  = s:char_at()
    if has_key(s:pairs, before) && s:pairs[before] ==# after
        return "\<BS>\<Del>"
    endif
    return "\<BS>"
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#pairs#setup() abort
    for [open, close] in items(s:pairs)
        " Symmetric pairs (quotes): one mapping handles both open & skip
        if open ==# close
            execute printf(
                \ 'inoremap <expr> %s wplus#pairs#open(%s, %s)',
                \ open, string(open), string(close))
        else
            execute printf(
                \ 'inoremap <expr> %s wplus#pairs#open(%s, %s)',
                \ open, string(open), string(close))
            execute printf(
                \ 'inoremap <expr> %s wplus#pairs#close(%s)',
                \ close, string(close))
        endif
    endfor
    inoremap <expr> <BS> wplus#pairs#backspace()
endfunction
