" test/test_lsp_workspace_symbols.vim — Test workspace/symbol result handling

function! Test_lsp_workspace_symbols_empty() abort
    call wplus#lsp#setup()
    call assert_equal([], wplus#lsp#_test_workspace_symbols_to_qf([]), 'Empty result should produce an empty quickfix list')
endfunction

function! Test_lsp_workspace_symbols_single() abort
    call wplus#lsp#setup()
    let l:result = [{
        \ 'name': 'MyFunc',
        \ 'kind': 12,
        \ 'location': {
        \   'uri': 'file:///tmp/a.go',
        \   'range': {'start': {'line': 3, 'character': 0}, 'end': {'line': 3, 'character': 10}},
        \ },
        \ }]
    let l:qf = wplus#lsp#_test_workspace_symbols_to_qf(l:result)
    call assert_equal(1, len(l:qf), 'One symbol should yield one quickfix entry')
    call assert_equal('/tmp/a.go', l:qf[0].filename, 'filename should be decoded from the URI')
    call assert_equal(4, l:qf[0].lnum, 'lnum should be 1-based')
    call assert_equal(1, l:qf[0].col, 'col should be 1-based')
    call assert_equal('MyFunc', l:qf[0].text, 'text should be the symbol name')
endfunction

function! Test_lsp_workspace_symbols_multiple() abort
    call wplus#lsp#setup()
    let l:result = [
        \ {'name': 'A', 'kind': 6, 'location': {'uri': 'file:///tmp/a.go', 'range': {'start': {'line': 0, 'character': 0}, 'end': {'line': 0, 'character': 1}}}},
        \ {'name': 'B', 'kind': 6, 'location': {'uri': 'file:///tmp/b.go', 'range': {'start': {'line': 5, 'character': 0}, 'end': {'line': 5, 'character': 1}}}},
        \ ]
    let l:qf = wplus#lsp#_test_workspace_symbols_to_qf(l:result)
    call assert_equal(2, len(l:qf), 'Two symbols should yield two quickfix entries')
    call assert_equal('A', l:qf[0].text, 'First entry should be A')
    call assert_equal('B', l:qf[1].text, 'Second entry should be B')
endfunction
