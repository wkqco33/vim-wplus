" test_surround.vim — delete/change surrounding characters.
"
" The pair table stores what to *insert* (the open-bracket triggers add padding:
" ys( gives "( x )"), but matching against buffer text must use the bare
" one-character delimiters. Conflating the two broke ds/cs on every bracket.

function! s:buf(text, col) abort
    enew!
    setlocal buftype=nofile noswapfile
    call setline(1, a:text)
    call cursor(1, a:col)
endfunction

function! Test_surround_behavior() abort
call wplus#surround#setup()

" ── delete surrounding ────────────────────────────────────────────────────

" cursor on 'bar' inside foo(bar)
call s:buf('foo(bar)', 6)
call feedkeys("ds)", 'x')
call assert_equal('foobar', getline(1), 'ds) removes both parens')

call s:buf('foo(bar)', 6)
call feedkeys("ds(", 'x')
call assert_equal('foobar', getline(1), 'ds( removes both parens')

call s:buf('foo[bar]', 6)
call feedkeys("ds]", 'x')
call assert_equal('foobar', getline(1), 'ds] removes both brackets')

call s:buf('foo{bar}', 6)
call feedkeys("ds}", 'x')
call assert_equal('foobar', getline(1), 'ds} removes both braces')

call s:buf('say "hello" now', 7)
call feedkeys('ds"', 'x')
call assert_equal('say hello now', getline(1), 'ds" removes both quotes')

" ── change surrounding ────────────────────────────────────────────────────
" Regression: this advanced by len(close) where close was the padded ' )',
" consuming one character too many and eating the char after the delimiter.

call s:buf('foo(bar)', 6)
call feedkeys('cs)"', 'x')
call assert_equal('foo"bar"', getline(1), 'cs)" swaps parens for quotes')

call s:buf('say "hello" now', 7)
call feedkeys("cs\"'", 'x')
call assert_equal("say 'hello' now", getline(1), "cs\"' swaps double for single quotes")

call s:buf('foo[bar]', 6)
call feedkeys('cs])', 'x')
call assert_equal('foo(bar)', getline(1), 'cs]) swaps brackets for parens, unpadded')

" A trailing character after the closing delimiter must survive.
call s:buf('foo(bar)X', 6)
call feedkeys('cs)]', 'x')
call assert_equal('foo[bar]X', getline(1), 'cs does not consume the char after the closer')

" ── no-op trigger removed ─────────────────────────────────────────────────
" 't' used to map to ['', ''], so dst/cst silently did nothing. With the entry
" gone it falls through to the [char, char] default rather than misbehaving.

call s:buf('foo(bar)', 6)
let s:before = getline(1)
call feedkeys('dst', 'x')
call assert_equal(s:before, getline(1), 'dst does not corrupt the line')

" ── column-1 delimiter regression ([: -1] slice bug) ──────────────────────
call s:buf('(bar)', 2)
call feedkeys("ds)", 'x')
call assert_equal('bar', getline(1), 'ds) at column 1 removes parens without duplicating line')

call s:buf('(bar)', 2)
call feedkeys('cs)"', 'x')
call assert_equal('"bar"', getline(1), 'cs)" at column 1 swaps parens for quotes without duplicating line')

call s:buf('hello', 1)
call feedkeys("veS\"", 'x')
call assert_equal('"hello"', getline(1), 'visual S" at column 1 surrounds word without duplicating line')

" ── multibyte UTF-8 surrounding ───────────────────────────────────────────
call s:buf('가나다', 1)
call feedkeys("veS\"", 'x')
call assert_equal('"가나다"', getline(1), 'visual S" surrounds multibyte UTF-8 text cleanly')

call s:buf('"가나다"', 4)
call feedkeys('cs"''', 'x')
call assert_equal("'가나다'", getline(1), 'cs swaps quotes around multibyte UTF-8 text cleanly')

call s:buf('"가나다"', 4)
call feedkeys('ds"', 'x')
call assert_equal('가나다', getline(1), 'ds removes quotes around multibyte UTF-8 text cleanly')

" ── ys{motion}{char} and yss{char} normal-mode operators ──────────────────
call s:buf('hello world', 1)
call feedkeys('ysiw"', 'x')
call assert_equal('"hello" world', getline(1), 'ysiw" surrounds word under cursor')

call s:buf('    hello world', 5)
call feedkeys('yss)', 'x')
call assert_equal('    (hello world)', getline(1), 'yss) surrounds entire line preserving indentation')

bwipeout!
endfunction
