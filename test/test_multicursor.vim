" test/test_multicursor.vim — Unit tests for multicursor module

function! Test_multicursor_add_next_and_clear() abort
    call wplus#multicursor#setup()
    enew!
    setlocal buftype=nofile noswapfile
    call setline(1, ['foo bar foo', 'foo baz foo'])
    call cursor(1, 1)

    " First add_next selects current word 'foo'
    call wplus#multicursor#add_next()
    
    " Second add_next selects next 'foo'
    call wplus#multicursor#add_next()

    " Clear all cursors
    call wplus#multicursor#clear()

    bwipeout!
endfunction

function! Test_multicursor_select_all_and_delete() abort
    call wplus#multicursor#setup()
    enew!
    setlocal buftype=nofile noswapfile
    call setline(1, ['item A item', 'item B item'])
    call cursor(1, 1)

    " Select all occurrences of 'item'
    call wplus#multicursor#select_all()

    " Perform delete
    call wplus#multicursor#delete()

    let l:lines = getline(1, '$')
    call assert_equal([' A ', ' B '], l:lines, 'All occurrences of "item" should be deleted')

    bwipeout!
endfunction
