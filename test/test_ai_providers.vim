" test/test_ai_providers.vim — Test AI provider table and payload generation

function! Test_ai_providers_payload_tokens_and_temp() abort
    call wplus#ai#setup()
    let g:wplus_ai_suggest_max_tokens = 777
    let g:wplus_ai_suggest_temperature = 0.123

    for l:provider in ['openai', 'claude', 'azure', 'ollama']
        let g:wplus_ai_provider = l:provider
        let g:wplus_ai_model = 'test-model'
        let g:wplus_ai_api_key = 'dummy-key'
        let g:wplus_ai_azure_resource = 'res'
        let g:wplus_ai_azure_deployment = 'dep'
        let g:wplus_ai_azure_api_version = '2023-05-15'

        let l:payload_str = wplus#ai#_test_build_suggest_payload('def foo():', '    pass')
        call assert_true(!empty(l:payload_str), 'Payload should not be empty for provider: ' . l:provider)
        let l:data = json_decode(l:payload_str)

        if l:provider ==# 'ollama'
            call assert_equal(777, l:data.options.num_predict, 'Ollama num_predict mismatch')
            call assert_equal(0.123, l:data.options.temperature, 'Ollama temperature mismatch')
        else
            let l:max_tok = get(l:data, 'max_tokens', get(l:data, 'max_completion_tokens', 0))
            call assert_equal(777, l:max_tok, l:provider . ' max_tokens mismatch')
            call assert_equal(0.123, l:data.temperature, l:provider . ' temperature mismatch')
        endif
    endfor
endfunction

function! Test_ai_unknown_provider_fails_loudly() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'antropic'  " Typo!
    let g:wplus_ai_api_key = 'test-key'

    let l:payload = wplus#ai#_test_build_suggest_payload('def foo():', '')
    call assert_equal('', l:payload, 'Unknown provider should return empty payload and log error')
endfunction

function! Test_ai_get_api_endpoint_without_arguments() abort
    call wplus#ai#setup()
    for l:provider in ['openai', 'claude', 'azure', 'ollama']
        let g:wplus_ai_provider = l:provider
        let g:wplus_ai_azure_resource = 'testres'
        let g:wplus_ai_azure_deployment = 'testdep'
        let g:wplus_ai_azure_api_version = '2023-05-15'

        let l:ep1 = wplus#ai#_test_get_api_endpoint()
        call assert_true(!empty(l:ep1), 'Endpoint without args should not be empty for provider: ' . l:provider)

        let l:ep2 = wplus#ai#_test_get_api_endpoint({'user': 'test'})
        call assert_equal(l:ep1, l:ep2, 'Endpoint with spec should match endpoint without args for provider: ' . l:provider)
    endfor
endfunction

function! Test_ai_commit_diff_max_bytes_default() abort
    call wplus#ai#setup()
    call assert_equal(32768, g:wplus_ai_commit_diff_max_bytes, 'Default commit diff max bytes should be 32768')
endfunction

function! Test_ai_large_payload_stdin_chunked() abort
    if !has('job')
        return
    endif
    call wplus#ai#setup()
    " Test sending a 150KB payload via chunked stdin writing
    let l:large_payload = repeat('X', 153600)
    let l:received = []
    let l:cmd = has('win32') ? ['more'] : ['cat']
    let l:job = job_start(l:cmd, {
        \ 'in_mode': 'raw',
        \ 'out_mode': 'raw',
        \ 'out_cb': {_ch, msg -> add(l:received, msg)},
        \ })
    if type(l:job) != v:t_job
        return
    endif
    call wplus#ai#_test_write_payload_stdin(l:job, l:large_payload)
    sleep 50m
    let l:total_len = len(join(l:received, ''))
    call assert_equal(153600, l:total_len, 'Large payload chunked write should send all 153600 bytes without E631 error')
    silent! call job_stop(l:job)
endfunction
