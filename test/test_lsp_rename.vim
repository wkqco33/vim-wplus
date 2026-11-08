" test/test_lsp_rename.vim — Test LSP rename preview helpers

function! Test_lsp_rename_prepare_valid() abort
    call wplus#lsp#setup()
    " A range result means the symbol is renameable.
    call assert_true(wplus#lsp#_test_prepare_rename_valid({'range': {'start': {'line': 0, 'character': 0}, 'end': {'line': 0, 'character': 3}}}), 'Range result should be valid')
    " A placeholder-only result is also valid.
    call assert_true(wplus#lsp#_test_prepare_rename_valid({'placeholder': 'foo'}), 'Placeholder result should be valid')
    " Empty / error results are invalid.
    call assert_false(wplus#lsp#_test_prepare_rename_valid({}), 'Empty result should be invalid')
    call assert_false(wplus#lsp#_test_prepare_rename_valid(v:null), 'Null result should be invalid')
endfunction

function! Test_lsp_rename_preview_lines() abort
    call wplus#lsp#setup()
    let l:edit = {
        \ 'changes': {
        \   'file:///tmp/a.go': [{
        \     'range': {'start': {'line': 1, 'character': 4}, 'end': {'line': 1, 'character': 10}},
        \     'newText': 'NewVar',
        \   }],
        \ }
        \ }
    let l:lines = wplus#lsp#_test_rename_preview_lines(l:edit)
    call assert_equal(1, len(l:lines), 'One change should yield one preview line')
    call assert_true(l:lines[0] =~# '/tmp/a.go', 'Preview should include the file path')
    call assert_true(l:lines[0] =~# '2:5', 'Preview should include 1-based line:col')
    call assert_true(l:lines[0] =~# 'NewVar', 'Preview should include the new text')
endfunction

function! Test_lsp_rename_preview_empty() abort
    call wplus#lsp#setup()
    call assert_equal([], wplus#lsp#_test_rename_preview_lines({}), 'Empty edit should produce no preview lines')
endfunction

function! Test_lsp_apply_text_edits_utf16_multibyte_and_col0() abort
    call wplus#lsp#setup()
    let l:tmp = tempname() . '.go'
    call writefile(['// 한글 주석 foo_bar end', 'foo_bar()'], l:tmp)
    execute 'edit ' . fnameescape(l:tmp)

    " In '// 한글 주석 foo_bar end':
    " '// ' is 3 chars (3 bytes)
    " '한글' is 2 UTF-16 code units (6 bytes)
    " ' ' is 1 char (1 byte)
    " '주석' is 2 UTF-16 code units (6 bytes)
    " ' ' is 1 char (1 byte)
    " So 'foo_bar' starts at UTF-16 character offset 9, ends at 16!
    " On line 1 ('foo_bar()'), 'foo_bar' starts at character 0, ends at 7.
    let l:edits = [
        \ {'range': {'start': {'line': 0, 'character': 9}, 'end': {'line': 0, 'character': 16}}, 'newText': 'renamed'},
        \ {'range': {'start': {'line': 1, 'character': 0}, 'end': {'line': 1, 'character': 7}}, 'newText': 'renamed'},
        \ ]
    call wplus#lsp#_test_apply_text_edits(l:tmp, l:edits)

    call assert_equal('// 한글 주석 renamed end', getline(1), 'UTF-16 character offsets after Korean text must map to right byte offsets')
    call assert_equal('renamed()', getline(2), 'Character offset 0 replacement must not duplicate line via [:-1]')

    bwipeout!
    call delete(l:tmp)
endfunction
