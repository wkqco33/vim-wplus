" test_pairs.vim — auto-pair behaviour.
"
" The <expr> handlers are called directly with the buffer in a known state and
" their returned key sequence is asserted. Driving them through feedkeys() is
" unreliable under -es: an <expr> insert mapping can be evaluated before the
" preceding typed characters have been flushed into the buffer, so the handler
" sees an empty line and every "is there a word before the cursor" test is
" vacuously false. Calling the handler is what actually pins the logic.
"
" Cursor positions below are mid-line, where normal-mode col() matches the
" insert-mode column the handler would see.

call wplus#pairs#setup()

function! s:at(text, col) abort
    enew!
    setlocal buftype=nofile noswapfile
    call setline(1, a:text)
    call cursor(1, a:col)
endfunction

" ── mappings are installed ────────────────────────────────────────────────

call assert_notequal('', maparg('(', 'i'), '( is mapped in insert mode')
call assert_notequal('', maparg('<BS>', 'i'), '<BS> is mapped in insert mode')

" ── auto-close ────────────────────────────────────────────────────────────

enew! | setlocal buftype=nofile
call feedkeys("i(\<Esc>", 'x')
call assert_equal('()', getline(1), 'open paren auto-closes')

enew! | setlocal buftype=nofile
call feedkeys("i[\<Esc>", 'x')
call assert_equal('[]', getline(1), 'open bracket auto-closes')

" ── closing char skips instead of duplicating ─────────────────────────────

" buffer ")", cursor on ")": typing ")" should step over it
call s:at(')', 1)
call assert_equal("\<Right>", wplus#pairs#close(')'),
    \ 'typing a closer that is already there skips over it')

" nothing to skip: insert it
call s:at('ab', 2)
call assert_equal(')', wplus#pairs#close(')'),
    \ 'closer is inserted when the next char is not it')

" ── backspace deletes the whole pair ─────────────────────────────────────
" Regression: s:char_before() read col('.') - 3 instead of col('.') - 2, so the
" opener was never recognised and only "(" was deleted, leaving ")".

call s:at('()', 2)
call assert_equal("\<BS>\<Del>", wplus#pairs#backspace(),
    \ 'backspace between ( and ) deletes both')

call s:at('{}', 2)
call assert_equal("\<BS>\<Del>", wplus#pairs#backspace(),
    \ 'backspace between { and } deletes both')

call s:at('ab', 2)
call assert_equal("\<BS>", wplus#pairs#backspace(),
    \ 'backspace between two ordinary chars deletes one')

" ── apostrophe must not auto-pair next to a word ─────────────────────────
" Regression: wplus#pairs#open() only inspected the char *after* the cursor, so
" typing "don'" produced "don''".

" buffer "don ", cursor on the space -> char before is 'n'
call s:at('don ', 4)
call assert_equal("'", wplus#pairs#open("'", "'"),
    \ "apostrophe after a word character does not pair")

" buffer "its", cursor on 's' -> before is 't', after is 's'
call s:at('its', 3)
call assert_equal("'", wplus#pairs#open("'", "'"),
    \ 'apostrophe mid-word does not pair')

" a quote with non-word context on both sides still pairs -- the useful case
call s:at('  ', 2)
call assert_equal("'" . "'" . "\<Left>", wplus#pairs#open("'", "'"),
    \ 'quote surrounded by whitespace auto-pairs')

" brackets pair regardless of adjacent word characters: f( -> f()
call s:at('f ', 2)
call assert_equal("()\<Left>", wplus#pairs#open('(', ')'),
    \ 'bracket after a word character still pairs')

" ── escaped quote is inserted literally ──────────────────────────────────

call s:at('a\ ', 3)
call assert_equal("'", wplus#pairs#open("'", "'"),
    \ 'quote after a backslash is not paired')

" ── completion menu is never disturbed ───────────────────────────────────
" pumvisible() is 0 outside insert mode, so this asserts the non-pum path only;
" the guard itself is a single early return.

call s:at('()', 2)
call assert_equal("\<BS>\<Del>", wplus#pairs#backspace(),
    \ 'pair-delete still works when no popup menu is visible')

bwipeout!
