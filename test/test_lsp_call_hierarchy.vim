" test/test_lsp_call_hierarchy.vim — Test call hierarchy result conversion

function! Test_lsp_call_hierarchy_incoming_empty() abort
    call wplus#lsp#setup()
    call assert_equal([], wplus#lsp#_test_incoming_calls_to_qf([]), 'Empty incoming calls should yield no quickfix entries')
endfunction

function! Test_lsp_call_hierarchy_incoming() abort
    call wplus#lsp#setup()
    let l:result = [{
        \ 'from': {'name': 'Caller', 'kind': 12, 'uri': 'file:///tmp/a.go'},
        \ 'fromRanges': [{'start': {'line': 2, 'character': 4}, 'end': {'line': 2, 'character': 10}}],
        \ }]
    let l:qf = wplus#lsp#_test_incoming_calls_to_qf(l:result)
    call assert_equal(1, len(l:qf), 'One incoming call should yield one entry')
    call assert_equal('/tmp/a.go', l:qf[0].filename, 'filename should be decoded')
    call assert_equal(3, l:qf[0].lnum, 'lnum should be 1-based from the call range')
    call assert_equal(5, l:qf[0].col, 'col should be 1-based from the call range')
    call assert_equal('Caller', l:qf[0].text, 'text should be the caller name')
endfunction

function! Test_lsp_call_hierarchy_outgoing_empty() abort
    call wplus#lsp#setup()
    call assert_equal([], wplus#lsp#_test_outgoing_calls_to_qf([]), 'Empty outgoing calls should yield no quickfix entries')
endfunction

function! Test_lsp_call_hierarchy_outgoing() abort
    call wplus#lsp#setup()
    let l:result = [{
        \ 'to': {'name': 'Callee', 'kind': 12, 'uri': 'file:///tmp/b.go',
        \        'selectionRange': {'start': {'line': 5, 'character': 0}, 'end': {'line': 5, 'character': 6}}},
        \ 'fromRanges': [{'start': {'line': 1, 'character': 0}, 'end': {'line': 1, 'character': 6}}],
        \ }]
    let l:qf = wplus#lsp#_test_outgoing_calls_to_qf(l:result)
    call assert_equal(1, len(l:qf), 'One outgoing call should yield one entry')
    call assert_equal('/tmp/b.go', l:qf[0].filename, 'filename should be the callee file')
    call assert_equal(6, l:qf[0].lnum, 'lnum should be 1-based from the callee selectionRange')
    call assert_equal('Callee', l:qf[0].text, 'text should be the callee name')
endfunction
