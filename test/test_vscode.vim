" test/test_vscode.vim — Test the VS Code-aligned keymap layer

function! Test_vscode_disabled_by_default() abort
    call wplus#vscode#setup()
    call assert_equal(0, g:wplus_vscode_keymaps, 'VS Code keymaps should be off by default')
    call assert_equal('', maparg('<F12>', 'n'), 'No mappings should be installed when disabled')
endfunction

function! Test_vscode_lsp_mappings() abort
    let g:wplus_vscode_keymaps = 1
    call wplus#vscode#setup()
    call assert_true(maparg('<F12>', 'n') =~# 'WlspDefinition', 'F12 should map to definition')
    call assert_true(maparg('<S-F12>', 'n') =~# 'WlspReferences', 'Shift+F12 should map to references')
    call assert_true(maparg('<A-F12>', 'n') =~# 'WlspPeekDefinition', 'Alt+F12 should map to peek definition')
    call assert_true(maparg('<F2>', 'n') =~# 'WlspRename', 'F2 should map to rename')
    call assert_true(maparg('<C-.>', 'n') =~# 'WlspCodeAction', 'Ctrl+. should map to code action')
    call assert_true(maparg('<C-S-M>', 'n') =~# 'WlspProblems', 'Ctrl+Shift+M should map to problems')
    call assert_true(maparg('<C-T>', 'n') =~# 'WlspSymbols', 'Ctrl+T should map to workspace symbols')
    call assert_true(maparg('<C-Space>', 'i') =~# 'WlspCompletion', 'Ctrl+Space should map to completion in insert mode')
    unlet! g:wplus_vscode_keymaps
endfunction

function! Test_vscode_search_and_ui_mappings() abort
    let g:wplus_vscode_keymaps = 1
    call wplus#vscode#setup()
    call assert_true(maparg('<C-S-F>', 'n') =~# 'WgrepWord', 'Ctrl+Shift+F should map to grep')
    call assert_true(maparg('<C-p>', 'n') =~# 'WfindFiles', 'Ctrl+P should map to file finder')
    call assert_true(maparg('<C-S-O>', 'n') =~# 'WoutlineToggle', 'Ctrl+Shift+O should map to outline')
    call assert_true(maparg('<C-S-E>', 'n') =~# 'WexplorerToggle', 'Ctrl+Shift+E should map to explorer')
    call assert_true(maparg('<C-S-K>', 'n') =~# 'dd', 'Ctrl+Shift+K should delete the line')
    unlet! g:wplus_vscode_keymaps
endfunction

function! Test_vscode_terminal_mapping_target_command_exists() abort
    let g:wplus_vscode_keymaps = 1
    call wplus#terminal#setup()
    call wplus#vscode#setup()
    let l:cmd = matchstr(maparg('<C-`>', 'n'), ':\zs\w\+\ze<CR>')
    call assert_true(!empty(l:cmd), 'Ctrl+` should map to an ex command')
    call assert_equal(2, exists(':' . l:cmd), 'Mapped terminal command must exist: :' . l:cmd)
    unlet! g:wplus_vscode_keymaps
endfunction

