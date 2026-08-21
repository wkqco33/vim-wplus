" test/test_lsp_organize_imports.vim — Test organize-imports code action selection

function! Test_lsp_organize_imports_finds_matching_action() abort
    call wplus#lsp#setup()
    let l:result = [
        \ {'title': 'Refactor', 'kind': 'refactor.rewrite'},
        \ {'title': 'Organize Imports', 'kind': 'source.organizeImports', 'edit': {'changes': {}}},
        \ ]
    let l:action = wplus#lsp#_test_find_organize_imports_action(l:result)
    call assert_equal('Organize Imports', l:action.title, 'Should pick the organizeImports action')
endfunction

function! Test_lsp_organize_imports_falls_back_to_first() abort
    call wplus#lsp#setup()
    let l:result = [
        \ {'title': 'Quick Fix', 'kind': 'quickfix', 'edit': {'changes': {}}},
        \ ]
    let l:action = wplus#lsp#_test_find_organize_imports_action(l:result)
    call assert_equal('Quick Fix', l:action.title, 'Should fall back to the first action when none matches')
endfunction

function! Test_lsp_organize_imports_empty() abort
    call wplus#lsp#setup()
    call assert_equal({}, wplus#lsp#_test_find_organize_imports_action([]), 'Empty result should yield no action')
endfunction
