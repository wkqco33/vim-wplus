" test/test_ai_ui.vim — Safe behavior when the preview UI is unavailable

function! s:record_preview_apply() abort
    let g:wplus_test_preview_applied = get(g:, 'wplus_test_preview_applied', 0) + 1
endfunction

function! Test_ai_missing_preview_never_applies_response_implicitly() abort
    call wplus#ai#setup()
    let g:wplus_test_preview_applied = 0

    call wplus#ai#ui#_test_missing_popup(function('s:record_preview_apply'))

    call assert_equal(0, g:wplus_test_preview_applied,
        \ 'A missing preview UI must not apply an AI response without explicit acceptance')
    unlet g:wplus_test_preview_applied
endfunction
