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

" The character immediately left of the cursor, '' at start of line.
"
" col('.') is 1-based and, in insert mode, points at the position the next
" character will occupy -- so the char to its left is at 0-based index
" col('.') - 2. This used to compute an intermediate `col('.') - 1` and then
" index `[col - 2]`, reading col('.') - 3: one character too far left. That made
" wplus#pairs#backspace() test the wrong character and never delete a pair.
function! s:char_before() abort
    return col('.') > 1 ? getline('.')[col('.') - 2] : ''
endfunction

function! s:char_at() abort
    return getline('.')[col('.') - 1]
endfunction

" Is the cursor position preceded by an odd number of backslashes?
"
" Counts leftward from the character immediately before the cursor, which is at
" 0-based index col('.') - 2. This had the same off-by-one as s:char_before():
" it started at col('.') - 3 and so never saw a single escaping backslash.
function! s:is_escaped() abort
    if col('.') <= 1 | return 0 | endif
    let line = getline('.')
    let backslashes = 0
    let i = col('.') - 2
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
        " Don't auto-pair inside or right after a word: an apostrophe following a
        " word character is nearly always possessive or a contraction ("don't",
        " "it's"), not the start of a quoted string. Checking only the character
        " *after* the cursor missed this entirely and turned "don'" into "don''".
        if s:char_at() =~# '\w' || s:char_before() =~# '\w'
            return a:open
        endif
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
    " Never interfere with completion-menu navigation.
    if pumvisible()
        return "\<BS>"
    endif
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
