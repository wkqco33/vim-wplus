" test/test_marks.vim — Test visual marks indicator including global A-Z marks

function! Test_marks_list_includes_global_marks() abort
    enew!
    setlocal buftype=nofile noswapfile
    call setline(1, ['line 1', 'line 2 with mark', 'line 3'])

    " Set local mark 'a' and global mark 'M'
    call cursor(2, 1)
    normal! ma
    normal! mM

    let l:items = wplus#marks#_test_get_mark_items()
    let l:marks_found = map(copy(l:items), 'v:val[0]')

    call assert_true(index(l:marks_found, 'a') >= 0, "Local mark 'a' should be listed")
    call assert_true(index(l:marks_found, 'M') >= 0, "Global mark 'M' should be listed")

    delmarks a M
    bwipeout!
endfunction
