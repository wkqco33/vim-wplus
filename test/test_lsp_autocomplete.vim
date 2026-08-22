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

function! Test_lsp_autocomplete_rejects_stale_cursor() abort
    call wplus#lsp#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=go
    call setline(1, 'fmt.')
    call cursor(1, 5)
    let l:req = {'bufnr': bufnr('%'), 'uri': 'file://' . expand('%:p'), 'changedtick': b:changedtick, 'lnum': 1, 'col': 5}
    call cursor(1, 4)
    call assert_false(wplus#lsp#_test_completion_context_valid(l:req), 'Completion response must be discarded after cursor movement')
    bwipeout!
endfunction

function! Test_lsp_autocomplete_rejects_non_insert_mode() abort
    call wplus#lsp#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=go
    call setline(1, 'fmt.')
    call cursor(1, 5)
    let l:req = {'bufnr': bufnr('%'), 'uri': 'file://' . expand('%:p'), 'changedtick': b:changedtick, 'lnum': 1, 'col': 5}
    call assert_false(wplus#lsp#_test_completion_context_valid(l:req), 'Completion response must be discarded outside Insert mode')
    bwipeout!
endfunction

function! Test_lsp_autocomplete_does_not_trigger_on_insert_enter() abort
    call wplus#lsp#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python
    let b:wplus_lsp_insert_enter_tick = b:changedtick
    call assert_false(wplus#lsp#_test_insert_changed(bufnr('%')), 'Entering Insert mode alone must not trigger completion')
    let b:wplus_lsp_insert_enter_tick = b:changedtick - 1
    call assert_true(wplus#lsp#_test_insert_changed(bufnr('%')), 'Completion should trigger after an actual edit')
    bwipeout!
endfunction

function! Test_lsp_autocomplete_requires_a_completion_prefix() abort
    call wplus#lsp#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python
    call setline(1, '')
    call cursor(1, 1)
    call assert_false(wplus#lsp#_test_completion_input_available(), 'Empty input must not open the completion popup')
    call setline(1, '    ')
    call cursor(1, 5)
    call assert_false(wplus#lsp#_test_completion_input_available(), 'Whitespace-only input must not open the completion popup')
    call setline(1, 'abs')
    call cursor(1, 4)
    call assert_true(wplus#lsp#_test_completion_input_available(), 'A typed identifier should allow completion')
    call setline(1, 'value.')
    call cursor(1, 7)
    call assert_true(wplus#lsp#_test_completion_input_available(), 'A member trigger should allow completion')
    bwipeout!
endfunction

function! Test_lsp_autocomplete_only_uses_server_trigger_characters() abort
    call wplus#lsp#setup()
    call wplus#lsp#_test_set_caps('python', {'completionProvider': {'triggerCharacters': ['.']}})
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python
    call setline(1, 'a')
    call cursor(1, 2)
    call assert_false(wplus#lsp#_test_auto_completion_trigger_available('python'), 'A plain identifier must not open a global completion list')
    " In the ex test harness the normal-mode cursor sits on the character
    " where Insert mode would place the cursor after the trigger.
    call setline(1, 'value..')
    call cursor(1, 7)
    call assert_true(wplus#lsp#_test_auto_completion_trigger_available('python'), 'A server trigger character should open member completion')
    bwipeout!
endfunction
