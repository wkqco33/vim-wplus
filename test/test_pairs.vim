" test_pairs.vim — auto-pair behaviour, end-to-end through feedkeys.
"
" These assertions describe what the module is supposed to do, not how it does
" it, so they survive the internal fixes in Phase 4.

call wplus#pairs#setup()

function! s:fresh() abort
    enew!
    setlocal buftype=nofile noswapfile
    %delete _
endfunction

" ── auto-close ────────────────────────────────────────────────────────────

call s:fresh()
call feedkeys("i(\<Esc>", 'x')
call assert_equal('()', getline(1), 'open paren auto-closes')

call s:fresh()
call feedkeys("i[\<Esc>", 'x')
call assert_equal('[]', getline(1), 'open bracket auto-closes')

" ── skip over the closing char instead of inserting a second one ──────────

call s:fresh()
call feedkeys("i()\<Esc>", 'x')
call assert_equal('()', getline(1), 'typing the closer skips over it')

" ── backspace deletes the whole pair ─────────────────────────────────────
" Phase 0 baseline: RED. s:char_before() is off by one (pairs.vim:19-22), so
" the opener is not recognised and only '(' is deleted, leaving ')'.

call s:fresh()
call feedkeys("i(\<BS>\<Esc>", 'x')
call assert_equal('', getline(1), 'backspace inside an empty pair deletes both')

call s:fresh()
call feedkeys("i{\<BS>\<Esc>", 'x')
call assert_equal('', getline(1), 'backspace inside an empty brace pair deletes both')

" ── apostrophe must not auto-pair after a word character ─────────────────
" Phase 0 baseline: RED. wplus#pairs#open() only inspects the char *after* the
" cursor (pairs.vim:51-52), never the one before, so "don'" becomes "don''".

call s:fresh()
call feedkeys("idon'\<Esc>", 'x')
call assert_equal("don'", getline(1), 'apostrophe after a word does not pair')

call s:fresh()
call feedkeys("iit's\<Esc>", 'x')
call assert_equal("it's", getline(1), 'apostrophe mid-word does not pair')

" A quote at the start of a word still pairs -- that is the useful case.
call s:fresh()
call feedkeys("i'\<Esc>", 'x')
call assert_equal("''", getline(1), 'leading quote still auto-pairs')

bwipeout!
