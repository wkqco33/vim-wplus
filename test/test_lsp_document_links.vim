" test/test_lsp_document_links.vim — Test document link lookup

function! Test_lsp_document_links_empty() abort
    call wplus#lsp#setup()
    call assert_equal({}, wplus#lsp#_test_find_document_link_at([], 1, 1), 'No links should yield no match')
endfunction

function! Test_lsp_document_links_finds_link_at_cursor() abort
    call wplus#lsp#setup()
    let l:links = [{
        \ 'range': {'start': {'line': 0, 'character': 5}, 'end': {'line': 0, 'character': 20}},
        \ 'target': 'https://example.com/foo',
        \ }]
    " Cursor at line 1, col 10 (inside the link range 6..20).
    let l:link = wplus#lsp#_test_find_document_link_at(l:links, 1, 10)
    call assert_equal('https://example.com/foo', l:link.target, 'Should find the link containing the cursor')
endfunction

function! Test_lsp_document_links_no_match_outside_range() abort
    call wplus#lsp#setup()
    let l:links = [{
        \ 'range': {'start': {'line': 0, 'character': 5}, 'end': {'line': 0, 'character': 20}},
        \ 'target': 'https://example.com/foo',
        \ }]
    " Cursor at line 1, col 2 (before the link range).
    call assert_equal({}, wplus#lsp#_test_find_document_link_at(l:links, 1, 2), 'Position before the link should not match')
endfunction
