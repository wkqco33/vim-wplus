" test/test_todo.vim — Test todo module functionality and regex escaping

function! Test_todo_parse_grep_line() abort
    let l:line_with_col = 'autoload/wplus/todo.vim:42:10: TODO: fix something'
    let l:parsed = wplus#todo#_test_parse_grep_line(l:line_with_col)
    call assert_equal('autoload/wplus/todo.vim', l:parsed.file)
    call assert_equal(42, l:parsed.lnum)
    call assert_equal(10, l:parsed.col)
    call assert_equal('TODO: fix something', l:parsed.text)

    let l:line_no_col = 'autoload/wplus/todo.vim:55: FIXME: another bug'
    let l:parsed_no_col = wplus#todo#_test_parse_grep_line(l:line_no_col)
    call assert_equal('autoload/wplus/todo.vim', l:parsed_no_col.file)
    call assert_equal(55, l:parsed_no_col.lnum)
    call assert_equal(1, l:parsed_no_col.col)
    call assert_equal('FIXME: another bug', l:parsed_no_col.text)
endfunction

function! Test_todo_build_search_cmd_uses_literal_word_boundaries() abort
    let l:cmd = wplus#todo#_test_build_cmd('rg')
    call assert_true(type(l:cmd) == v:t_list, 'Command should be a list to avoid shell quoting issues')
    
    " Check that pattern does not contain ASCII 8 (backspace) and uses proper word boundary
    let l:pattern = l:cmd[-1]
    call assert_false(l:pattern =~# "\<C-h>", 'Pattern must not contain literal backspace character')
    call assert_true(l:pattern =~# '\\b', 'Pattern must contain escaped backslash-b word boundary')
    call assert_true(l:pattern =~# 'TODO', 'Pattern must contain keywords')
endfunction
