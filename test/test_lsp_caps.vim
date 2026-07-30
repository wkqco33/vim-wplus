" test/test_lsp_caps.vim — Test LSP capabilities gating and workspace edits

function! Test_lsp_capability_gating() abort
    call wplus#lsp#setup()

    " Set capabilities for 'go' where hoverProvider is false and definitionProvider is true
    call wplus#lsp#_test_set_caps('go', {
        \ 'hoverProvider': v:false,
        \ 'definitionProvider': v:true,
        \ })

    call assert_false(wplus#lsp#_test_supports('go', 'textDocument/hover'), 'Hover should be unsupported')
    call assert_true(wplus#lsp#_test_supports('go', 'textDocument/definition'), 'Definition should be supported')
endfunction

function! Test_lsp_workspace_edit_two_files_preserves_current_buffer() abort
    call wplus#lsp#setup()
    let l:tmpdir = tempname()
    call mkdir(l:tmpdir, 'p')

    let l:file_a = l:tmpdir . '/a.go'
    let l:file_b = l:tmpdir . '/b.go'
    let l:cur_file = l:tmpdir . '/cur.go'

    call writefile(['package main', 'var OldVar = 1'], l:file_a)
    call writefile(['package main', 'var Test = OldVar'], l:file_b)
    call writefile(['package main', 'func main() {}'], l:cur_file)

    " Open cur.go as current buffer
    execute 'edit' fnameescape(l:cur_file)
    let l:cur_buf = bufnr('%')

    let l:uri_a = 'file://' . substitute(fnamemodify(l:file_a, ':p'), '\\', '/', 'g')
    let l:uri_b = 'file://' . substitute(fnamemodify(l:file_b, ':p'), '\\', '/', 'g')

    let l:edit = {
        \ 'changes': {
        \   l:uri_a: [{
        \     'range': {'start': {'line': 1, 'character': 4}, 'end': {'line': 1, 'character': 10}},
        \     'newText': 'NewVar',
        \   }],
        \   l:uri_b: [{
        \     'range': {'start': {'line': 1, 'character': 11}, 'end': {'line': 1, 'character': 17}},
        \     'newText': 'NewVar',
        \   }],
        \ }
        \ }

    call wplus#lsp#_test_apply_workspace_edit(l:edit)

    " Assert current buffer is still cur.go and unchanged
    call assert_equal(l:cur_buf, bufnr('%'), 'Current buffer should remain unchanged')
    call assert_equal('func main() {}', getline(2), 'Current buffer content should be untouched')

    " Check modified lines in file_a and file_b buffers
    let l:buf_a = bufnr(fnamemodify(l:file_a, ':p'))
    let l:buf_b = bufnr(fnamemodify(l:file_b, ':p'))

    call assert_true(l:buf_a != -1, 'Buffer A should be loaded')
    call assert_true(l:buf_b != -1, 'Buffer B should be loaded')

    call assert_equal('var NewVar = 1', getbufline(l:buf_a, 2)[0], 'File A edit failed')
    call assert_equal('var Test = NewVar', getbufline(l:buf_b, 2)[0], 'File B edit failed')

    " Cleanup
    call delete(l:file_a)
    call delete(l:file_b)
    call delete(l:cur_file)
    call delete(l:tmpdir, 'rf')
endfunction
