" test/test_grep.vim — Test grep backend configuration and buffered results

function! Test_grep_backend_configured() abort
    let l:b = wplus#grep#backend()
    call assert_false(empty(l:b), 'A grep backend should be detected in modern test environment')
    call assert_true(has_key(l:b, 'name'), 'Backend must have a name')
    call assert_true(has_key(l:b, 'grepprg'), 'Backend must specify grepprg')
    call assert_true(has_key(l:b, 'format'), 'Backend must specify format')
endfunction

function! Test_grep_buffered_caddexpr() abort
    call setqflist([], 'r')
    let l:orig_efm = &errorformat
    let &errorformat = '%f:%l:%c:%m'

    " Feed entries through grep buffer test bridge
    call wplus#grep#_test_push_line('autoload/wplus/grep.vim:10:1: first match')
    call wplus#grep#_test_push_line('autoload/wplus/grep.vim:20:5: second match')
    call wplus#grep#_test_flush()

    let l:qf = getqflist()
    call assert_equal(2, len(l:qf), 'Both buffered matches should be flushed to quickfix')
    call assert_equal(10, l:qf[0].lnum)
    call assert_equal(20, l:qf[1].lnum)

    let &errorformat = l:orig_efm
    call setqflist([], 'r')
endfunction
