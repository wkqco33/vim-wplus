" test/test_lsp_navigation.vim — Test typeDefinition/implementation gating

function! Test_lsp_navigation_capability_gating() abort
    call wplus#lsp#setup()
    call wplus#lsp#_test_set_caps('go', {
        \ 'typeDefinitionProvider': v:true,
        \ 'implementationProvider': v:false,
        \ })
    call assert_true(wplus#lsp#_test_supports('go', 'textDocument/typeDefinition'), 'typeDefinition should be supported')
    call assert_false(wplus#lsp#_test_supports('go', 'textDocument/implementation'), 'implementation should be unsupported')
endfunction

function! Test_lsp_navigation_goto_location_list() abort
    call wplus#lsp#setup()
    let l:tmpdir = tempname()
    call mkdir(l:tmpdir, 'p')
    let l:file = l:tmpdir . '/a.go'
    call writefile(['package main', 'var X = 1', 'var Y = 2'], l:file)
    execute 'edit ' . fnameescape(l:file)

    " A list of locations should jump to the first one.
    let l:result = [{
        \ 'uri': 'file://' . substitute(fnamemodify(l:file, ':p'), '\\', '/', 'g'),
        \ 'range': {'start': {'line': 1, 'character': 4}, 'end': {'line': 1, 'character': 5}},
        \ }]
    call wplus#lsp#_test_goto_location(l:result)
    call assert_equal(2, line('.'), 'Should jump to the first location line')
    call assert_equal(5, col('.'), 'Should jump to the first location col')

    call delete(l:file)
    call delete(l:tmpdir, 'rf')
endfunction
