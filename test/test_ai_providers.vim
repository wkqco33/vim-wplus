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

function! Test_ai_ollama_thinking_setting_is_in_payload() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'ollama'
    let g:wplus_ai_model = 'thinking-model'
    let g:wplus_ai_ollama_think = 0
    let l:data = json_decode(wplus#ai#_test_build_suggest_payload('x', ''))
    call assert_equal(v:false, l:data.think, 'Ghost Text must disable Ollama thinking when configured off')
    let g:wplus_ai_ollama_think = 1
    let l:data = json_decode(wplus#ai#_test_build_suggest_payload('x', ''))
    call assert_equal(v:true, l:data.think, 'Ghost Text must preserve enabled Ollama thinking')
    let g:wplus_ai_ollama_think = 0
endfunction

function! Test_ai_sanitizes_control_characters() abort
    call wplus#ai#setup()
    let l:clean = wplus#ai#_test_sanitize_text("ok\tline\nnext\<Esc>\<C-U>")
    call assert_equal("ok\tline\nnext", l:clean, 'AI output must not contain control characters')
endfunction

function! Test_ai_blocks_sensitive_context() abort
    call wplus#ai#setup()
    let g:wplus_ai_block_sensitive_context = 1
    let g:wplus_ai_allow_sensitive_context = 0
    call assert_true(wplus#ai#_test_is_sensitive("api_key = 'abcdefghijklmnop'"), 'Credential-like assignments must be blocked')
    call assert_true(wplus#ai#_test_is_sensitive("-----BEGIN PRIVATE KEY-----\nbase64-secret-material\n-----END PRIVATE KEY-----"), 'Private keys must be blocked')
    let g:wplus_ai_allow_sensitive_context = 1
    call assert_false(wplus#ai#_test_is_sensitive("api_key = 'allowed-by-explicit-override'"), 'Explicit override should be honored')
    call assert_false(wplus#ai#_test_is_sensitive("let g:wplus_ai_api_key = ''               \" API 키 필수 설정"), 'Empty quotes with inline comments must not be blocked')
    call assert_false(wplus#ai#_test_is_sensitive("let g:wplus_ai_api_key = $OPENAI_API_KEY  \" 환경 변수 권장"), 'Environment variable references with comments must not be blocked')
    call assert_false(wplus#ai#_test_is_sensitive("g:wplus_ai_api_key\nAuthorization: Bearer ollama\nsecret-api-key-12345"), 'Documentation/config references must not be blocked')
    let g:wplus_ai_allow_sensitive_context = 1
    unlet! g:wplus_ai_allow_sensitive_context
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
    " Keep this below the platform pipe-buffer size. A synchronous Vimscript
    " callback cannot drain stdout while ch_sendraw() is blocked on E631; the
    " production request path also enforces bounded request sizes separately.
    let l:large_payload = repeat('X', 32768)
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
    call assert_equal(32768, l:total_len, 'Bounded payload should be sent without E631 error')
    silent! call job_stop(l:job)
endfunction

function! Test_ai_smart_tab_and_plug_mappings() abort
    call wplus#ai#setup()
    
    " Test smart_tab when no suggestion
    call wplus#ai#dismiss_suggestion()
    call assert_false(wplus#ai#has_suggestion(), 'Should have no suggestion')
    call assert_equal("\<Tab>", wplus#ai#smart_tab(), 'smart_tab should return <Tab> when no suggestion')

    " Test smart_tab when suggestion exists
    call wplus#ai#_test_set_suggestion('const answer = 42;')
    call assert_true(wplus#ai#has_suggestion(), 'Should have suggestion')
    call assert_equal('const answer = 42;', wplus#ai#smart_tab(), 'smart_tab should return suggestion')
    call assert_false(wplus#ai#has_suggestion(), 'Suggestion should be consumed after accept')

    " Test Plug mappings exist in insert mode
    call assert_true(!empty(maparg('<Plug>WaiAcceptSuggest', 'i')), '<Plug>WaiAcceptSuggest should be defined')
    call assert_true(!empty(maparg('<Plug>WaiAcceptWord', 'i')), '<Plug>WaiAcceptWord should be defined')
    call assert_true(!empty(maparg('<Plug>WaiSmartTab', 'i')), '<Plug>WaiSmartTab should be defined')
endfunction

function! Test_ai_clean_commit_message() abort
    call wplus#ai#setup()
    let l:raw_with_think = "<think>\nThinking about changes...\n</think>\nfeat(ai): add smart tab completion\n\n- Support smart tab\n- Fix commit prompt"
    let l:cleaned = wplus#ai#_test_clean_commit(l:raw_with_think)
    call assert_equal("feat(ai): add smart tab completion\n\n- Support smart tab\n- Fix commit prompt", l:cleaned, 'Should strip <think> tags')

    let l:raw_with_markdown = "```gitcommit\nfix(git): improve commit message generation\n\n- Add diff stat\n```"
    let l:cleaned2 = wplus#ai#_test_clean_commit(l:raw_with_markdown)
    call assert_equal("fix(git): improve commit message generation\n\n- Add diff stat", l:cleaned2, 'Should strip markdown fences')
endfunction

function! Test_ai_commit_prompt_structure() abort
    call wplus#ai#setup()
    let l:stat = " src/main.rs | 10 +++++-----\n 1 file changed, 5 insertions(+), 5 deletions(-)"
    let l:diff = "diff --git a/src/main.rs b/src/main.rs\n--- a/src/main.rs\n+++ b/src/main.rs\n@@ -1,3 +1,3 @@"
    let l:prompt = wplus#ai#_test_build_commit_prompt(l:stat, l:diff)
    
    call assert_true(l:prompt =~# 'Conventional Commits', 'Prompt should guide Conventional Commits')
    call assert_true(l:prompt =~# 'src/main\.rs', 'Prompt should include diff stat')
    call assert_true(l:prompt =~# 'diff --git', 'Prompt should include diff content')
endfunction
