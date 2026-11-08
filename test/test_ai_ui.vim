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

function! s:mock_review_send(prompt, Callback, ...) abort
    call a:Callback("1. Check nil pointer\n2. Add unit test")
endfunction

function! Test_ai_review_and_explain_populate_result_buffer_body() abort
    call wplus#ai#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=go
    call setline(1, ['package main', 'func main() {}'])

    call wplus#ai#_test_set_send_interceptor(function('s:mock_review_send'))
    try
        1,2call wplus#ai#review()
        call assert_equal(1, get(w:, 'wplus_ai_result', 0), 'Result split window should be focused')
        call assert_equal(['1. Check nil pointer', '2. Add unit test'], getline(1, '$'),
            \ 'AI Review buffer body must contain the review content, not the title')
        call assert_true(&l:statusline =~# 'AI Code Review', 'Statusline should contain the review title')
    finally
        call wplus#ai#_test_clear_send_interceptor()
    endtry

    close
    bwipeout!
endfunction
