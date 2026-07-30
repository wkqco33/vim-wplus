" test_surround.vim — delete/change surrounding characters.
"
" The pair table stores what to *insert* (the open-bracket triggers add padding:
" ys( gives "( x )"), but matching against buffer text must use the bare
" one-character delimiters. Conflating the two broke ds/cs on every bracket.

call wplus#surround#setup()

function! s:buf(text, col) abort
    enew!
    setlocal buftype=nofile noswapfile
    call setline(1, a:text)
    call cursor(1, a:col)
endfunction

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

bwipeout!
