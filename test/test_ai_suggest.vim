" test_ai_suggest.vim — Ghost Text context and output quality.

function! Test_ai_suggest_rapid_window_accepts_float_calculation() abort
    " Regression: max([0.5, ...]) passed a Float to Vim's Number-only max().
    call assert_equal(0.5, wplus#ai#suggest#_test_rapid_window(100))
    call assert_equal(0.8, wplus#ai#suggest#_test_rapid_window(400))
endfunction

function! Test_ai_suggest_prompt_has_language_and_cursor_contract() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'openai'
    let g:wplus_ai_model = 'test-model'
    let g:wplus_ai_api_key = 'dummy-key'
    let g:wplus_ai_completion_model = ''
    let g:wplus_ai_ollama_fim = 0

    enew
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python
    call setline(1, ['def greet(name):', '    return '])
    call cursor(2, 12)

    let l:data = json_decode(wplus#ai#_test_build_suggest_payload('def greet(name):\n    return ', ''))
    let l:system = l:data.messages[0].content
    let l:user = l:data.messages[1].content
    call assert_match('for python', l:system, 'Completion prompt should identify the buffer language')
    call assert_match('<CURSOR>', l:user, 'Chat fallback should provide an unambiguous cursor marker')
    call assert_match('Do not repeat', l:user, 'Chat fallback should explicitly forbid prefix/suffix repetition')

    bwipeout!
endfunction

function! Test_ai_suggest_context_keeps_definition_line() abort
    call wplus#ai#setup()
    enew
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python
    call setline(1, ['def greet(name):', '    return name'])
    call cursor(2, 17)
    let l:prefix = wplus#ai#context#get_prefix(2, 17, 50)
    call assert_match('def greet', l:prefix, 'Prefix should include the enclosing definition')
    bwipeout!
endfunction

function! Test_ai_suggest_trims_echoed_context() abort
    call wplus#ai#setup()
    let l:clean = wplus#ai#security#trim_suggest_content("return value\n}", '}', '    return ')
    call assert_equal('value', l:clean, 'Suggestion should remove echoed prefix and suffix text')
    let l:indented = wplus#ai#security#clean_suggest_content("\n    if ready:\n        return value\n")
    call assert_equal("\n    if ready:\n        return value\n", l:indented, 'Suggestion cleanup must preserve code whitespace')
endfunction

function! Test_ai_fim_unsupported_errors_are_detected() abort
    call wplus#ai#setup()
    call assert_true(wplus#ai#provider#is_fim_unsupported_error('model does not support suffix'), 'Ollama suffix capability errors should trigger chat fallback')
    call assert_true(wplus#ai#provider#is_fim_unsupported_error('insert is not supported for this model'), 'Ollama insert capability errors should trigger chat fallback')
    call assert_false(wplus#ai#provider#is_fim_unsupported_error('connection timeout'), 'Transport errors are not FIM capability errors')
endfunction

function! Test_ai_code_command_uses_completion_model() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'openai'
    let g:wplus_ai_model = 'command-model'
    let g:wplus_ai_completion_model = 'completion-model'
    let g:wplus_ai_api_key = 'dummy-key'
    let l:data = json_decode(wplus#ai#_test_build_completion_payload('complete this'))
    call assert_equal('completion-model', l:data.model, 'Code completion commands should use the completion model')
    let g:wplus_ai_completion_model = ''
endfunction

function! Test_ai_completion_model_controls_token_parameter() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'openai'
    let g:wplus_ai_model = 'gpt-4o'
    let g:wplus_ai_completion_model = 'gpt-5-mini'
    let g:wplus_ai_api_key = 'dummy-key'
    let l:data = json_decode(wplus#ai#_test_build_suggest_payload('x', ''))
    call assert_true(has_key(l:data, 'max_completion_tokens'), 'Completion model token parameter should be selected independently')
    call assert_false(has_key(l:data, 'max_tokens'), 'Completion payload must not use legacy token parameter for gpt-5')
    let g:wplus_ai_completion_model = ''
endfunction
