" test/test_ai_providers.vim — Test AI provider table and payload generation

function! Test_ai_providers_payload_tokens_and_temp() abort
    call wplus#ai#setup()
    let g:wplus_ai_suggest_max_tokens = 777
    let g:wplus_ai_suggest_temperature = 0.123

    for l:provider in ['openai', 'claude', 'azure', 'ollama', 'gemini']
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
        elseif l:provider ==# 'gemini'
            call assert_equal(777, l:data.generationConfig.maxOutputTokens, 'Gemini maxOutputTokens mismatch')
            call assert_equal(0.123, l:data.generationConfig.temperature, 'Gemini temperature mismatch')
        else
            let l:max_tok = get(l:data, 'max_tokens', get(l:data, 'max_completion_tokens', 0))
            call assert_equal(777, l:max_tok, l:provider . ' max_tokens mismatch')
            call assert_equal(0.123, l:data.temperature, l:provider . ' temperature mismatch')
        endif
    endfor
endfunction

function! Test_ai_gemini_extract_and_error() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'gemini'
    let g:wplus_ai_model = 'gemini-2.0-flash'
    let g:wplus_ai_api_key = 'test-key'
    
    let l:sample_resp = {
        \ 'candidates': [{
        \   'content': {
        \     'parts': [{'text': 'print("hello gemini")'}]
        \   }
        \ }]
        \ }
    call assert_equal('print("hello gemini")', wplus#ai#provider#extract_content(l:sample_resp))

    let l:error_resp = {'error': {'message': 'Invalid API Key'}}
    call assert_equal('Invalid API Key', wplus#ai#provider#extract_error(l:error_resp))
endfunction

function! Test_ai_suggest_payload_includes_scope_and_symbols() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'openai'
    let g:wplus_ai_model = 'test-model'
    let g:wplus_ai_api_key = 'dummy-key'
    let g:wplus_ai_ollama_fim = 0

    enew
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python
    call setline(1, [
        \ 'def helper():',
        \ '    return 1',
        \ '',
        \ 'def foo():',
        \ '    x = helper()',
        \ '    ',
        \ ])
    call cursor(6, 1)

    let l:payload_str = wplus#ai#_test_build_suggest_payload('def foo():', '')
    let l:data = json_decode(l:payload_str)
    let l:user = l:data['messages'][-1].content
    call assert_match('def foo', l:user, 'Current scope should be injected into the suggest prompt')
    call assert_match('helper', l:user, 'Workspace symbols should be injected into the suggest prompt')

    bwipeout!
endfunction

function! Test_ai_completion_model_separate_from_default() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'openai'
    let g:wplus_ai_model = 'deepseek-v4-flash'
    let g:wplus_ai_api_key = 'dummy-key'
    let g:wplus_ai_completion_model = 'qwen2.5-coder:3b'
    let g:wplus_ai_ollama_fim = 0

    " Command payload (commit/comment/refactor) must use the default model.
    let l:cmd_str = wplus#ai#_test_build_request_payload('Explain this code')
    let l:cmd = json_decode(l:cmd_str)
    call assert_equal('deepseek-v4-flash', l:cmd.model, 'Command requests should use the default model')

    " Suggest payload (chat path) must use the completion model.
    let l:sug_str = wplus#ai#_test_build_suggest_payload('def foo():', '')
    let l:sug = json_decode(l:sug_str)
    call assert_equal('qwen2.5-coder:3b', l:sug.model, 'Suggest (chat) should use the completion model')

    let g:wplus_ai_completion_model = ''
endfunction

function! Test_ai_suggest_accepts_completion_only_model() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'openai'
    let g:wplus_ai_api_key = 'dummy-key'
    let g:wplus_ai_model = ''
    let g:wplus_ai_completion_model = 'qwen2.5-coder:3b'
    call assert_true(wplus#ai#http#_test_suggest_ready(), 'Ghost Text should work when only the completion model is configured')
    let g:wplus_ai_completion_model = ''
endfunction

function! Test_ai_completion_model_falls_back_to_default() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'openai'
    let g:wplus_ai_model = 'deepseek-v4-flash'
    let g:wplus_ai_api_key = 'dummy-key'
    let g:wplus_ai_ollama_fim = 0
    let g:wplus_ai_completion_model = ''

    let l:sug_str = wplus#ai#_test_build_suggest_payload('def foo():', '')
    let l:sug = json_decode(l:sug_str)
    call assert_equal('deepseek-v4-flash', l:sug.model, 'Suggest should fall back to default model when completion model unset')
endfunction

function! Test_ai_completion_model_used_in_ollama_fim() abort
    call wplus#ai#setup()
    let g:wplus_ai_provider = 'ollama'
    let g:wplus_ai_model = 'deepseek-v4-flash'
    let g:wplus_ai_completion_model = 'qwen2.5-coder:3b'
    let g:wplus_ai_ollama_fim = 1

    let l:payload_str = wplus#ai#_test_build_suggest_payload('def foo():', '    return')
    let l:data = json_decode(l:payload_str)
    call assert_equal('qwen2.5-coder:3b', l:data.model, 'Ollama FIM should use the completion model')
    call assert_equal('def foo():', l:data.prompt, 'FIM prompt should be the prefix')
    call assert_equal('    return', l:data.suffix, 'FIM suffix should be preserved')

    let g:wplus_ai_completion_model = ''
endfunction

function! Test_ai_ollama_thinking_setting_is_enabled_in_payload() abort
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

function! Test_ai_suggest_rejects_stale_and_noise_content() abort
    call wplus#ai#setup()
    call assert_equal('', wplus#ai#security#clean_suggest_content('@'), 'A lone @ is not a useful ghost-text suggestion')
    call assert_equal('', wplus#ai#security#clean_suggest_content('  @  '), 'Whitespace around noise must also be rejected')
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
    call assert_true(l:prompt =~# 'concise', 'Commit prompt should request a concise message')
    call assert_true(l:prompt =~# 'single-line', 'Commit prompt should prefer a single-line summary')
    call assert_false(l:prompt =~# 'structured and detailed', 'Commit prompt should not request detailed messages')
    call assert_false(l:prompt =~# 'all significant modified modules/files', 'Commit prompt should not enumerate every changed file')
    call assert_true(l:prompt =~# 'src/main\.rs', 'Prompt should include diff stat')
    call assert_true(l:prompt =~# 'diff --git', 'Prompt should include diff content')
endfunction

function! Test_ai_commit_prompt_adapts_to_change_scale() abort
    call wplus#ai#setup()
    " Small change: keep concise single-line guidance.
    let l:small_stat = " src/main.rs | 10 +++++-----\n 1 file changed, 5 insertions(+), 5 deletions(-)"
    let l:small_diff = "diff --git a/src/main.rs b/src/main.rs\n--- a/src/main.rs\n+++ b/src/main.rs\n@@ -1,3 +1,3 @@"
    let l:small_prompt = wplus#ai#_test_build_commit_prompt(l:small_stat, l:small_diff)
    call assert_true(l:small_prompt =~# 'single-line', 'Small changes should prefer a single-line summary')

    " Large change: request a detailed body that covers the full scope.
    let l:large_stat = " src/a.rs | 100 +++++++++++\n src/b.rs | 200 +++++++++++\n src/c.rs | 300 +++++++++++\n src/d.rs | 400 +++++++++++\n src/e.rs | 500 +++++++++++\n 5 files changed, 1500 insertions(+), 0 deletions(-)"
    let l:large_diff = "diff --git a/src/a.rs b/src/a.rs\n--- a/src/a.rs\n+++ b/src/a.rs\n@@ -1,3 +1,3 @@"
    let l:large_prompt = wplus#ai#_test_build_commit_prompt(l:large_stat, l:large_diff)
    call assert_true(l:large_prompt =~# 'extensive', 'Large changes should request a detailed body')
    call assert_true(l:large_prompt =~# 'bullets', 'Large changes should request bullet points')
    call assert_true(l:large_prompt =~# 'full scope', 'Large changes should cover the full scope')
endfunction

function! Test_ai_commit_diff_truncates_at_file_boundary() abort
    call wplus#ai#setup()
    let l:diff = "diff --git a/a.rs b/a.rs\n--- a/a.rs\n+++ b/a.rs\n@@ -1,3 +1,3 @@\n+line1\n"
        \ . "diff --git a/b.rs b/b.rs\n--- a/b.rs\n+++ b/b.rs\n@@ -1,3 +1,3 @@\n+line2\n"
        \ . "diff --git a/c.rs b/c.rs\n--- a/c.rs\n+++ b/c.rs\n@@ -1,3 +1,3 @@\n+line3\n"
    " Limit that lands inside the second file: must keep only the first file.
    let l:cut = wplus#ai#_test_truncate_diff(l:diff, 80)
    call assert_true(l:cut =~# 'diff --git a/a\.rs', 'Truncated diff should keep the first file')
    call assert_false(l:cut =~# 'diff --git a/b\.rs', 'Truncated diff must not cut mid-file into the second file')
endfunction
