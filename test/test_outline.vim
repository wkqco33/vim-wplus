" test/test_outline.vim — Test code outline LSP symbols integration and hierarchical parsing

function! Test_outline_parse_lsp_symbols_hierarchical() abort
    let l:raw_lsp = [
        \ {
        \   'name': 'MyClass',
        \   'kind': 5,
        \   'range': {'start': {'line': 1, 'character': 0}, 'end': {'line': 10, 'character': 0}},
        \   'children': [
        \     {
        \       'name': 'my_method',
        \       'kind': 6,
        \       'range': {'start': {'line': 3, 'character': 4}, 'end': {'line': 5, 'character': 4}}
        \     }
        \   ]
        \ },
        \ {
        \   'name': 'top_level_func',
        \   'kind': 12,
        \   'range': {'start': {'line': 12, 'character': 0}, 'end': {'line': 15, 'character': 0}}
        \ }
        \ ]

    let l:parsed = wplus#outline#_test_parse_lsp_symbols(l:raw_lsp)
    call assert_equal(3, len(l:parsed), 'Three symbols should be parsed including children')
    
    call assert_equal('MyClass', l:parsed[0].name)
    call assert_equal('c', l:parsed[0].kind)
    call assert_equal(2, l:parsed[0].lnum)

    call assert_equal('  my_method', l:parsed[1].name)
    call assert_equal('m', l:parsed[1].kind)
    call assert_equal(4, l:parsed[1].lnum)

    call assert_equal('top_level_func', l:parsed[2].name)
    call assert_equal('f', l:parsed[2].kind)
    call assert_equal(13, l:parsed[2].lnum)
endfunction

function! Test_outline_parse_flat_symbol_information() abort
    let l:raw_flat = [
        \ {
        \   'name': 'global_var',
        \   'kind': 13,
        \   'location': {'range': {'start': {'line': 0, 'character': 0}}}
        \ }
        \ ]

    let l:parsed = wplus#outline#_test_parse_lsp_symbols(l:raw_flat)
    call assert_equal(1, len(l:parsed))
    call assert_equal('global_var', l:parsed[0].name)
    call assert_equal('v', l:parsed[0].kind)
    call assert_equal(1, l:parsed[0].lnum)
endfunction
