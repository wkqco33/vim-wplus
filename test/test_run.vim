" test/test_run.vim — Test run module (errorformat parsing, test command overrides)

function! Test_run_qf_add_parses_errorformat() abort
    call setqflist([], 'r')
    let l:orig_efm = &errorformat
    let &errorformat = '%f:%l:%m'

    " Call the qf_add helper
    call wplus#run#_test_qf_add('autoload/wplus/run.vim:42: syntax error')

    let l:qf = getqflist()
    call assert_equal(1, len(l:qf), 'One entry should be added')
    call assert_equal(1, l:qf[0].valid, 'Entry matching errorformat must have valid=1 for jump navigation')
    call assert_equal(42, l:qf[0].lnum, 'Line number should be parsed')

    let &errorformat = l:orig_efm
    call setqflist([], 'r')
endfunction

function! Test_run_test_command_resolution() abort
    let g:wplus_test_commands = {'test_marker.txt': 'my_custom_test_runner'}
    let l:cmd = wplus#run#_test_resolve_test_cmd('/some/path', ['test_marker.txt'])
    call assert_equal('my_custom_test_runner', l:cmd, 'Custom test command should override or resolve')
    let g:wplus_test_commands = {}
endfunction
