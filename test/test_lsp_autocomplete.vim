" test/test_lsp_autocomplete.vim — Test LSP auto-completion trigger gating

function! Test_lsp_autocomplete_disabled_by_config() abort
    call wplus#lsp#setup()
    let g:wplus_lsp_auto_complete = 0
    call wplus#lsp#_test_set_caps('go', {'completionProvider': {'triggerCharacters': ['.']}})
    call assert_equal(0, wplus#lsp#_test_auto_complete_enabled('go'), 'Auto-complete must be off when g:wplus_lsp_auto_complete is 0')
    unlet! g:wplus_lsp_auto_complete
endfunction

function! Test_lsp_autocomplete_requires_server_support() abort
    call wplus#lsp#setup()
    let g:wplus_lsp_auto_complete = 1
    call wplus#lsp#_test_set_caps('go', {'completionProvider': v:false})
    call assert_equal(0, wplus#lsp#_test_auto_complete_enabled('go'), 'Auto-complete must be off when the server lacks completionProvider')
endfunction

function! Test_lsp_autocomplete_enabled_when_supported() abort
    call wplus#lsp#setup()
    let g:wplus_lsp_auto_complete = 1
    call wplus#lsp#_test_set_caps('go', {'completionProvider': {'triggerCharacters': ['.']}})
    call assert_equal(1, wplus#lsp#_test_auto_complete_enabled('go'), 'Auto-complete should be on when supported and enabled')
endfunction

function! Test_lsp_autocomplete_default_config() abort
    call wplus#lsp#setup()
    call assert_equal(1, g:wplus_lsp_auto_complete, 'Auto-complete should default to on')
    call assert_true(g:wplus_lsp_complete_delay > 0, 'Auto-complete delay should be a positive number')
endfunction
