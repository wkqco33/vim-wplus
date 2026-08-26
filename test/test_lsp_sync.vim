" test/test_lsp_sync.vim — Test LSP incremental (range-based) didChange sync

" Compute the minimal changed range between two line lists. Returns a dict
" {start, end, text, rangeLength} with 0-based LSP line numbers, or {} when
" the documents are identical. 'end' is exclusive; 'text' is the replacement
" for old_lines[start:end] (with trailing newline); 'rangeLength' is the
" character length of the replaced old text.
function! Test_lsp_sync_no_change_returns_empty() abort
    call wplus#lsp#setup()
    let l:r = wplus#lsp#_test_compute_change_range(['a', 'b', 'c'], ['a', 'b', 'c'])
    call assert_equal({}, l:r, 'Identical documents must produce no change')
endfunction

function! Test_lsp_sync_edit_middle_line() abort
    call wplus#lsp#setup()
    let l:r = wplus#lsp#_test_compute_change_range(['a', 'b', 'c'], ['a', 'B', 'c'])
    call assert_equal(1, l:r.start, 'start should be the edited line')
    call assert_equal(2, l:r.end, 'end should be start+1 for a single-line edit')
    call assert_equal("B\n", l:r.text, 'text should be the new line with trailing newline')
    call assert_equal(2, l:r.rangeLength, 'rangeLength should be the old line plus newline')
endfunction

function! Test_lsp_sync_insert_line() abort
    call wplus#lsp#setup()
    " Inserting 'X' before old line 2 is a zero-width range at line 2 in the
    " old document: {start:2, end:2}, text "X\n", rangeLength 0.
    let l:r = wplus#lsp#_test_compute_change_range(['a', 'b', 'c'], ['a', 'b', 'X', 'c'])
    call assert_equal(2, l:r.start, 'insertion point line')
    call assert_equal(2, l:r.end, 'end should equal start for a pure insertion')
    call assert_equal("X\n", l:r.text, 'text should be the inserted line')
    call assert_equal(0, l:r.rangeLength, 'pure insertion replaces zero old characters')
endfunction

function! Test_lsp_sync_delete_line() abort
    call wplus#lsp#setup()
    " Deleting old line 1 ('b') replaces "b\n" with "" over {start:1, end:2}.
    let l:r = wplus#lsp#_test_compute_change_range(['a', 'b', 'c'], ['a', 'c'])
    call assert_equal(1, l:r.start, 'deletion starts at the removed line')
    call assert_equal(2, l:r.end, 'end should be the removed line + 1')
    call assert_equal("", l:r.text, 'text should be empty for a pure deletion')
    call assert_equal(2, l:r.rangeLength, 'rangeLength should cover the removed line plus newline')
endfunction

function! Test_lsp_sync_append_at_end() abort
    call wplus#lsp#setup()
    " Appending 'b' after old line 0 is a zero-width range at {line:1, char:0}.
    let l:r = wplus#lsp#_test_compute_change_range(['a'], ['a', 'b'])
    call assert_equal(1, l:r.start, 'append starts after the last old line')
    call assert_equal(1, l:r.end, 'end should equal start for a pure append')
    call assert_equal("b\n", l:r.text, 'text should be the appended line')
    call assert_equal(0, l:r.rangeLength, 'append replaces zero old characters')
endfunction

function! Test_lsp_sync_edit_first_line() abort
    call wplus#lsp#setup()
    let l:r = wplus#lsp#_test_compute_change_range(['a', 'b'], ['A', 'b'])
    call assert_equal(0, l:r.start, 'start should be 0 for a first-line edit')
    call assert_equal(1, l:r.end, 'end should be 1')
    call assert_equal("A\n", l:r.text, 'text should be the new first line')
    call assert_equal(2, l:r.rangeLength, 'rangeLength should be the old first line plus newline')
endfunction

function! Test_lsp_sync_multi_line_edit() abort
    call wplus#lsp#setup()
    let l:old = ['a', 'b', 'c', 'd', 'e']
    let l:new = ['a', 'X', 'Y', 'e']
    let l:r = wplus#lsp#_test_compute_change_range(l:old, l:new)
    call assert_equal(1, l:r.start, 'start should be the first differing line')
    call assert_equal(4, l:r.end, 'end should be the last differing line + 1')
    call assert_equal("X\nY\n", l:r.text, 'text should be the new block')
    " old replaced text is lines 1..3 = 'b','c','d' plus 3 newlines
    call assert_equal(6, l:r.rangeLength, 'rangeLength should cover the replaced old block')
endfunction

function! Test_lsp_sync_flush_changes() abort
    call wplus#lsp#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python
    call setline(1, ['def foo():', '    pass'])
    let l:buf = bufnr('%')
    
    " Set a mock pending timer
    let l:timer = timer_start(10000, {-> 0})
    call setbufvar(l:buf, 'wplus_lsp_change_timer', l:timer)
    
    call wplus#lsp#flush_changes(l:buf)
    
    let l:remaining_timer = getbufvar(l:buf, 'wplus_lsp_change_timer', -1)
    call assert_equal(-1, l:remaining_timer, 'flush_changes must stop and reset the pending change timer')
    
    bwipeout!
endfunction

