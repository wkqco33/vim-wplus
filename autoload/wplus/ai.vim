" wplus/ai.vim — AI assistant with OpenAI/Claude/Azure OpenAI integration

if exists('g:autoloaded_wplus_ai') | finish | endif
let g:autoloaded_wplus_ai = 1

let g:wplus_ai_provider = get(g:, 'wplus_ai_provider', 'openai') " 'openai', 'claude', 'azure', or 'ollama'
let g:wplus_ai_model = get(g:, 'wplus_ai_model', '')
let g:wplus_ai_api_key = get(g:, 'wplus_ai_api_key', '')
let g:wplus_ai_temperature = get(g:, 'wplus_ai_temperature', 0.7)
let g:wplus_ai_max_tokens = get(g:, 'wplus_ai_max_tokens', 2000)

" Azure-specific settings
let g:wplus_ai_azure_resource = get(g:, 'wplus_ai_azure_resource', '')  " e.g., 'my-resource'
let g:wplus_ai_azure_deployment = get(g:, 'wplus_ai_azure_deployment', '')  " e.g., 'gpt-4'
let g:wplus_ai_azure_api_version = get(g:, 'wplus_ai_azure_api_version', '2024-02-15-preview')

" Ollama-specific settings
let g:wplus_ai_ollama_host          = get(g:, 'wplus_ai_ollama_host',          'http://localhost:11434')
let g:wplus_ai_ollama_think         = get(g:, 'wplus_ai_ollama_think',         0)      " Reasoning/thinking mode toggle
let g:wplus_ai_ollama_keep_alive    = get(g:, 'wplus_ai_ollama_keep_alive',    '30m')  " Model memory retention duration ('30m', '-1', '0')
let g:wplus_ai_ollama_fim           = get(g:, 'wplus_ai_ollama_fim',           0)      " Fill-In-Middle prompt format for code models
let g:wplus_ai_ollama_options       = get(g:, 'wplus_ai_ollama_options',       {})     " Custom sampling options override
let g:wplus_ai_suggest_temperature  = get(g:, 'wplus_ai_suggest_temperature',  0.2)

" Ghost Text auto-suggestion settings
let g:wplus_ai_suggest_enabled = get(g:, 'wplus_ai_suggest_enabled', 1)
let g:wplus_ai_suggest_delay = get(g:, 'wplus_ai_suggest_delay', 500)
let g:wplus_ai_suggest_context_lines = get(g:, 'wplus_ai_suggest_context_lines', 50)
let g:wplus_ai_suggest_suffix_lines = get(g:, 'wplus_ai_suggest_suffix_lines', 20)
let g:wplus_ai_suggest_max_tokens = get(g:, 'wplus_ai_suggest_max_tokens', 500)
let g:wplus_ai_suggest_max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
let g:wplus_ai_suggest_debug = get(g:, 'wplus_ai_suggest_debug', 0)
let g:wplus_ai_tab_complete = get(g:, 'wplus_ai_tab_complete', 1)

" Network timeouts (seconds). Commands wait longer; suggestions abort faster.
let g:wplus_ai_timeout = get(g:, 'wplus_ai_timeout', 30)
let g:wplus_ai_suggest_timeout = get(g:, 'wplus_ai_suggest_timeout', 10)
let g:wplus_ai_commit_diff_max_bytes = get(g:, 'wplus_ai_commit_diff_max_bytes', 32768)
let g:wplus_ai_commit_max_tokens = get(g:, 'wplus_ai_commit_max_tokens', 2048)
let g:wplus_ai_commit_prompt = get(g:, 'wplus_ai_commit_prompt', '')
let g:wplus_ai_response_max_bytes = get(g:, 'wplus_ai_response_max_bytes', 1048576)
" Synchronous ch_sendraw() cannot safely drain very large child stdout while
" writing. Reject oversized requests before starting curl rather than hanging.
let g:wplus_ai_request_max_bytes = get(g:, 'wplus_ai_request_max_bytes', 262144)
let g:wplus_ai_block_sensitive_context = get(g:, 'wplus_ai_block_sensitive_context', 1)
let g:wplus_ai_sensitive_files = get(g:, 'wplus_ai_sensitive_files', [
    \ '.env', '.env.*', '*.pem', '*.key', '*.p12', '*.pfx',
    \ '*credential*', '*secret*', '*password*', '*token*',
    \ ])

let s:command_requests = {} " request_id -> {job, on_content, response_buffer, error_buffer}
let s:suggest_request = {} " {request_id, job, channel_key, bufnr, lnum, line, col, fim, response_buffer}
let s:suggest_request_id = 0  " monotonic id to defeat channel reuse races

" Ghost Text state
let s:suggest_content = '' " current suggestion content
let s:suggest_line = 0 " line where suggestion was requested
let s:suggest_col = 0 " column where suggestion was requested
let s:suggest_bufnr = 0 " buffer where suggestion was requested
let s:suggest_timer = v:null
let s:suggest_keystroke_count = 0 " keystroke counter for adaptive delay
let s:last_suggest_error = ''
let s:last_suggest_error_at = 0


let s:providers = {}
let s:fim_unsupported_models = {}

function! wplus#ai#register_provider(name, dict) abort
    let s:providers[a:name] = a:dict
endfunction

function! s:get_provider(name) abort
    if !has_key(s:providers, a:name)
        call wplus#util#error_msg('ai', 'Unknown AI provider: "' . a:name . '". Registered providers: ' . join(keys(s:providers), ', '))
        return {}
    endif
    return s:providers[a:name]
endfunction

function! s:azure_endpoint(spec) abort
    if empty(g:wplus_ai_azure_resource) || empty(g:wplus_ai_azure_deployment)
        call wplus#util#error_msg('ai', 'Azure: resource and deployment must be configured')
        return ''
    endif
    return 'https://' . g:wplus_ai_azure_resource . '.openai.azure.com/openai/deployments/'
                \ . g:wplus_ai_azure_deployment . '/chat/completions'
                \ . '?api-version=' . g:wplus_ai_azure_api_version
endfunction

function! s:ollama_endpoint(spec) abort
    return g:wplus_ai_ollama_host . '/api/chat'
endfunction

function! s:build_openai_payload(spec) abort
    let l:model = !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'gpt-3.5-turbo'
    let l:msgs = []
    if !empty(a:spec.system)
        call add(l:msgs, {'role': 'system', 'content': a:spec.system})
    endif
    call add(l:msgs, {'role': 'user', 'content': a:spec.user})
    let l:body = {
        \ 'model': l:model,
        \ 'messages': l:msgs,
        \ 'temperature': a:spec.temperature,
        \ }
    if s:uses_max_completion_tokens()
        let l:body.max_completion_tokens = a:spec.max_tokens
    else
        let l:body.max_tokens = a:spec.max_tokens
    endif
    return json_encode(l:body)
endfunction

function! s:build_claude_payload(spec) abort
    let l:model = !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'claude-3-sonnet-20240229'
    let l:body = {
        \ 'model': l:model,
        \ 'max_tokens': a:spec.max_tokens,
        \ 'messages': [{'role': 'user', 'content': a:spec.user}],
        \ 'temperature': a:spec.temperature,
        \ }
    if !empty(a:spec.system)
        let l:body.system = a:spec.system
    endif
    return json_encode(l:body)
endfunction

function! s:build_ollama_payload_spec(spec) abort
    let l:msgs = []
    if !empty(a:spec.system)
        call add(l:msgs, {'role': 'system', 'content': a:spec.system})
    endif
    call add(l:msgs, {'role': 'user', 'content': a:spec.user})
    " Must honor g:wplus_ai_ollama_think (default 0) here too, otherwise
    " thinking models (e.g. deepseek-v4-flash:0731-cloud) burn all tokens on
    " chain-of-thought and return empty content, so ghost text never renders.
    let l:body = {
        \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'codellama',
        \ 'think': g:wplus_ai_ollama_think ? v:true : v:false,
        \ 'stream': v:false,
        \ 'keep_alive': g:wplus_ai_ollama_keep_alive,
        \ 'messages': l:msgs,
        \ 'options': s:ollama_options(a:spec.max_tokens, a:spec.temperature),
        \ }
    return json_encode(l:body)
endfunction

function! s:extract_openai(json) abort
    if has_key(a:json, 'choices') && len(a:json.choices) > 0
        let l:choice = a:json.choices[0]
        let l:message = get(l:choice, 'message', {})
        let l:content = get(l:message, 'content', '')
        if type(l:content) == v:t_string
            return l:content
        endif
    endif
    return ''
endfunction

function! s:extract_claude(json) abort
    if has_key(a:json, 'content') && len(a:json.content) > 0
        let l:parts = []
        for l:item in a:json.content
            if type(l:item) == v:t_dict && has_key(l:item, 'text')
                call add(l:parts, l:item.text)
            endif
        endfor
        return join(l:parts, '')
    endif
    return ''
endfunction

function! s:extract_ollama(json) abort
    if has_key(a:json, 'message') && type(a:json.message) == v:t_dict
        return get(a:json.message, 'content', '')
    endif
    return ''
endfunction

function! s:error_openai(json) abort
    if has_key(a:json, 'error')
        if type(a:json.error) == v:t_dict
            return get(a:json.error, 'message', string(a:json.error))
        elseif type(a:json.error) == v:t_string
            return a:json.error
        endif
    endif
    return ''
endfunction

function! s:error_claude(json) abort
    if has_key(a:json, 'error')
        let l:err = a:json.error
        if type(l:err) == v:t_dict
            return get(l:err, 'message', string(l:err))
        endif
    endif
    return ''
endfunction

function! s:error_ollama(json) abort
    return get(a:json, 'error', '')
endfunction

call wplus#ai#register_provider('openai', {
    \ 'needs_key': 1,
    \ 'endpoint': {spec -> get(g:, 'wplus_ai_openai_endpoint', 'https://api.openai.com/v1/chat/completions')},
    \ 'headers': {key -> ['Content-Type: application/json', 'Authorization: Bearer ' . key]},
    \ 'payload': function('s:build_openai_payload'),
    \ 'extract': function('s:extract_openai'),
    \ 'error': function('s:error_openai'),
    \ })

call wplus#ai#register_provider('claude', {
    \ 'needs_key': 1,
    \ 'endpoint': {spec -> 'https://api.anthropic.com/v1/messages'},
    \ 'headers': {key -> ['Content-Type: application/json', 'x-api-key: ' . key, 'anthropic-version: 2023-06-01']},
    \ 'payload': function('s:build_claude_payload'),
    \ 'extract': function('s:extract_claude'),
    \ 'error': function('s:error_claude'),
    \ })

call wplus#ai#register_provider('azure', {
    \ 'needs_key': 1,
    \ 'endpoint': function('s:azure_endpoint'),
    \ 'headers': {key -> ['Content-Type: application/json', 'api-key: ' . key]},
    \ 'payload': function('s:build_openai_payload'),
    \ 'extract': function('s:extract_openai'),
    \ 'error': function('s:error_openai'),
    \ })

call wplus#ai#register_provider('ollama', {
    \ 'needs_key': 0,
    \ 'endpoint': function('s:ollama_endpoint'),
    \ 'headers': {key -> ['Content-Type: application/json', 'Authorization: Bearer ollama']},
    \ 'payload': function('s:build_ollama_payload_spec'),
    \ 'extract': function('s:extract_ollama'),
    \ 'error': function('s:error_ollama'),
    \ })

function! s:get_api_endpoint(...) abort
    let l:spec = a:0 >= 1 ? a:1 : {}
    let l:prov = s:get_provider(g:wplus_ai_provider)
    if empty(l:prov) | return '' | endif
    if type(l:prov.endpoint) == v:t_func
        return call(l:prov.endpoint, [l:spec])
    endif
    return l:prov.endpoint
endfunction

function! s:get_request_headers() abort
    let l:prov = s:get_provider(g:wplus_ai_provider)
    if empty(l:prov) | return [] | endif
    if l:prov.needs_key && empty(g:wplus_ai_api_key)
        call wplus#util#error_msg('ai', 'API key not configured for provider ' . g:wplus_ai_provider)
        return []
    endif
    if type(l:prov.headers) == v:t_func
        return call(l:prov.headers, [g:wplus_ai_api_key])
    endif
    return l:prov.headers
endfunction

function! s:channel_key(channel) abort
    return wplus#util#channel_key(a:channel)
endfunction

" Store headers in a private curl config file instead of argv. This prevents
" API keys from appearing in /proc/<pid>/cmdline and process listings.
function! s:write_curl_config(headers) abort
    let l:file = tempname()
    let l:lines = []
    for l:header in a:headers
        " curl config syntax accepts one header per line. Escape backslashes
        " and quotes so provider values cannot change the config structure.
        let l:value = substitute(substitute(l:header, '\\', '\\\\', 'g'), '"', '\\"', 'g')
        call add(l:lines, 'header = "' . l:value . '"')
    endfor
    if writefile(l:lines, l:file) != 0
        return ''
    endif
    if exists('*setfperm')
        call setfperm(l:file, 'rw-------')
    endif
    return l:file
endfunction

function! s:build_curl_command(endpoint, headers, ...) abort
    let l:timeout = a:0 >= 1 ? a:1 : g:wplus_ai_timeout
    let l:config = s:write_curl_config(a:headers)
    if empty(l:config)
        return {'cmd': [], 'config': ''}
    endif
    return {'cmd': ['curl', '-s', '-S', '--max-time', string(l:timeout),
                \ '--config', l:config, '-X', 'POST', '-d', '@-', a:endpoint],
                \ 'config': l:config}
endfunction

function! s:cleanup_curl_config(file) abort
    if !empty(a:file)
        silent! call delete(a:file)
    endif
endfunction

" payload를 stdin으로 chunk단위로 안전하게 전송하고 stdin 닫기 (E631 파이프 버퍼 오버플로우 방지)
function! s:write_payload_stdin(job, payload) abort
    let l:ch = job_getchannel(a:job)
    if type(l:ch) != v:t_channel || ch_status(l:ch) !=# 'open'
        return
    endif
    let l:len = len(a:payload)
    let l:chunk_size = 4096
    let l:offset = 0
    while l:offset < l:len
        let l:end = min([l:offset + l:chunk_size - 1, l:len - 1])
        let l:chunk = a:payload[l:offset : l:end]
        let l:retries = 0
        let l:written = 0
        while l:retries < 50
            try
                call ch_sendraw(l:ch, l:chunk)
                let l:written = 1
                break
            catch /E631/
                let l:retries += 1
                execute 'sleep 2m'
            endtry
        endwhile
        if !l:written
            call wplus#util#error_msg('ai', 'channel write failed: pipe buffer full or process closed stdin')
            break
        endif
        let l:offset += l:chunk_size
    endwhile
    call ch_close_in(l:ch)
endfunction

function! s:extract_response_content(json) abort
    if g:wplus_ai_provider ==# 'ollama'
        " native /api/chat 응답: {"message": {"content": ...}}
        if has_key(a:json, 'message') && type(a:json.message) == v:t_dict
            return get(a:json.message, 'content', '')
        endif
        return ''
    endif
    if g:wplus_ai_provider ==# 'claude'
        if has_key(a:json, 'content') && len(a:json.content) > 0
            let l:parts = []
            for l:item in a:json.content
                if type(l:item) == v:t_dict && has_key(l:item, 'text')
                    call add(l:parts, l:item.text)
                endif
            endfor
            return join(l:parts, '')
        endif
    else
        if has_key(a:json, 'choices') && len(a:json.choices) > 0
            let l:choice = a:json.choices[0]
            let l:message = get(l:choice, 'message', {})
            let l:content = get(l:message, 'content', '')
            if type(l:content) == v:t_string
                return l:content
            endif
            if type(l:content) == v:t_list
                let l:parts = []
                for l:item in l:content
                    if type(l:item) == v:t_dict
                        if has_key(l:item, 'text')
                            call add(l:parts, l:item.text)
                        elseif get(l:item, 'type', '') ==# 'output_text' && has_key(l:item, 'text')
                            call add(l:parts, l:item.text)
                        endif
                    endif
                endfor
                return join(l:parts, '')
            endif
            if has_key(l:choice, 'text')
                return l:choice.text
            endif
        endif
    endif
    return ''
endfunction

" Clean suggest response content by removing think/thought tags and markdown code blocks
" Remove control characters before AI output is displayed or inserted. Keep
" newline and tab because they are meaningful in source code. AI output is
" untrusted input and must never be allowed to contain terminal/Vim controls.
function! s:sanitize_ai_text(content) abort
    let l:out = []
    for l:ch in split(a:content, '\zs')
        let l:n = char2nr(l:ch)
        if l:n == 9 || l:n == 10 || (l:n > 31 && l:n != 127)
            call add(l:out, l:ch)
        endif
    endfor
    return join(l:out, '')
endfunction

function! s:clean_suggest_content(content) abort
    let l:txt = s:sanitize_ai_text(a:content)
    " Remove completed <think>...</think> and <thought>...</thought> tags
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.\{-}</\%(think\|thought\)>', '', 'g')
    " Remove unclosed <think> or <thought> tags to the end
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.*$', '', 'g')
    " Remove markdown code blocks
    let l:txt = substitute(l:txt, '```.*\n', '', 'g')
    let l:txt = substitute(l:txt, '```', '', 'g')
    return trim(l:txt)
endfunction

" Return true for files or content that should not be sent automatically to an
" AI provider. This is deliberately fail-closed for common credential files
" and strong secret assignments, while avoiding broad matches such as the word
" token in normal prose.
function! s:is_sensitive_context(text) abort
    if !get(g:, 'wplus_ai_block_sensitive_context', 1)
        return 0
    endif
    if get(g:, 'wplus_ai_allow_sensitive_context', 0)
        return 0
    endif
    let l:name = expand('%:t')
    if !empty(l:name) && l:name !=# 'COMMIT_EDITMSG'
        for l:pattern in get(g:, 'wplus_ai_sensitive_files', [])
            if exists('*glob2regpat') && l:name =~# glob2regpat(l:pattern)
                return 1
            elseif l:name ==# l:pattern
                return 1
            endif
        endfor
    endif
    for l:line in split(a:text, "\n", 1)
        " Match private key envelopes
        if l:line =~? '-----BEGIN.*PRIVATE KEY-----' && a:text =~? '-----END.*PRIVATE KEY-----'
            return 1
        endif
        if l:line =~? '\cauthorization:\s*bearer\s\+\S\{16,}' || l:line =~? '\cbearer\s\+[A-Za-z0-9._~-]\{16,}'
            return 1
        endif
        " Check credential keyword assignments (api_key, secret_key, password, aws credentials)
        if l:line =~? '\v\c%(api[_-]?key|secret[_-]?key|password|aws_access_key_id|aws_secret_access_key)\s*[=:]'
            let l:value = s:extract_credential_rhs_value(l:line)
            if s:value_is_literal_secret(l:value)
                return 1
            endif
        endif
    endfor
    return 0
endfunction

" Extract only the right-hand side value after an assignment keyword, stripping
" surrounding quotes, inline comments, and delimiters.
function! s:extract_credential_rhs_value(line) abort
    let l:parts = matchlist(a:line, '\v\c%(api[_-]?key|secret[_-]?key|password|aws_access_key_id|aws_secret_access_key)\s*[=:]\s*(.*)')
    if empty(l:parts) || empty(l:parts[1])
        return ''
    endif
    let l:raw = trim(l:parts[1])

    " Single-quoted literal: 'secret_value' [optional comment]
    let l:sq = matchlist(l:raw, "^'\\([^']*\\)'")
    if !empty(l:sq)
        return l:sq[1]
    endif

    " Double-quoted literal: "secret_value" [optional comment]
    let l:dq = matchlist(l:raw, '^"\([^"]*\)"')
    if !empty(l:dq)
        return l:dq[1]
    endif

    " Unquoted identifier / expression / reference: strip trailing inline comments & punctuation
    let l:val = substitute(l:raw, '\s*#.*$', '', '')
    let l:val = substitute(l:val, '\s*//.*$', '', '')
    let l:val = substitute(l:val, '\s*".*$', '', '')
    let l:val = substitute(l:val, '[,;]\s*$', '', '')
    return trim(l:val)
endfunction

" Return true only when the right-hand side of a credential assignment is a
" literal secret value rather than a reference to a secret/config stored
" elsewhere. References (dotted member access, subscript/env lookups, function
" calls, shell variables, documented placeholders) are common in real code and
" must not be treated as leaked secrets.
function! s:value_is_literal_secret(value) abort
    if strlen(a:value) < 12
        return 0
    endif
    " Documented / example / placeholder values.
    if a:value =~? 'your-\|example\|placeholder\|secret-api-key\|not-a-real-key\|allowed-by-explicit-override\|sk-\.\.\.'
        return 0
    endif
    " Shell / environment variable references ($VAR).
    if a:value =~# '^\$'
        return 0
    endif
    " Variable/function references: dotted member access (cfg.password,
    " settings.API_KEY), subscript/env lookups (os.environ["X"]), and function
    " calls (get_password_from_vault(), secrets.token_hex(32)).
    if a:value =~# '\.' || a:value =~# '\[' || a:value =~# '\c^[a-z_][a-z0-9_]*(\s*'
        return 0
    endif
    " A bare identifier that looks like a variable/constant name (snake_case or
    " ALL_CAPS) is a reference, not a literal secret. Genuine literals almost
    " always contain mixed case/digits/symbols or a leading non-letter.
    if a:value =~# '^[A-Za-z_][A-Za-z0-9_]*$'
        if a:value =~# '_' || a:value =~# '^[A-Z][A-Z0-9]*$'
            return 0
        endif
    endif
    return 1
endfunction

function! s:reject_sensitive_context(text) abort
    if s:is_sensitive_context(a:text)
        call wplus#util#warn_msg('ai', 'request blocked: sensitive file or credential-like content detected')
        return 1
    endif
    return 0
endfunction

function! s:extract_error_message(json) abort
    if has_key(a:json, 'error')
        let l:error = a:json.error
        if type(l:error) == v:t_dict
            return get(l:error, 'message', '')
        endif
        if type(l:error) == v:t_string
            return l:error
        endif
    endif
    if has_key(a:json, 'message') && type(a:json.message) == v:t_string
        return a:json.message
    endif
    return ''
endfunction

" Merge user-defined sampling options (g:wplus_ai_ollama_options)
function! s:ollama_options(max_tokens, temperature) abort
    let l:opts = {}
    if type(g:wplus_ai_ollama_options) == v:t_dict
        call extend(l:opts, g:wplus_ai_ollama_options)
    endif
    let l:opts.temperature = a:temperature
    if a:max_tokens > 0
        let l:opts.num_predict = a:max_tokens
    endif
    return l:opts
endfunction

" Native Ollama /api/chat payload builder
function! s:build_ollama_payload(messages, max_tokens, temperature) abort
    return json_encode({
        \ 'model': g:wplus_ai_model,
        \ 'think': g:wplus_ai_ollama_think ? v:true : v:false,
        \ 'stream': v:false,
        \ 'keep_alive': g:wplus_ai_ollama_keep_alive,
        \ 'messages': a:messages,
        \ 'options': s:ollama_options(a:max_tokens, a:temperature),
        \ })
endfunction

" Native Ollama FIM (/api/generate) payload builder
function! s:build_ollama_fim_payload(prefix, suffix, max_tokens, temperature) abort
    return json_encode({
        \ 'model': g:wplus_ai_model,
        \ 'think': g:wplus_ai_ollama_think ? v:true : v:false,
        \ 'stream': v:false,
        \ 'keep_alive': g:wplus_ai_ollama_keep_alive,
        \ 'prompt': a:prefix,
        \ 'suffix': a:suffix,
        \ 'options': s:ollama_options(a:max_tokens, a:temperature),
        \ })
endfunction

" Check if FIM is enabled and supported for the current model
function! s:use_ollama_fim() abort
    return g:wplus_ai_provider ==# 'ollama' && g:wplus_ai_ollama_fim && !get(s:fim_unsupported_models, g:wplus_ai_model, 0)
endfunction

function! s:uses_max_completion_tokens() abort
    if g:wplus_ai_provider ==# 'claude'
        return v:false
    endif
    let l:model = tolower(g:wplus_ai_model)
    return l:model =~# '^gpt-5' || l:model =~# '^o[134]'
endfunction

function! s:suggest_debug(message) abort
    if g:wplus_ai_suggest_debug
        call wplus#util#info_msg('ai', '[suggest] ' . a:message)
    endif
endfunction

function! s:report_suggest_error(message) abort
    let l:now = localtime()
    if a:message ==# s:last_suggest_error && (l:now - s:last_suggest_error_at) < 3
        return
    endif
    let s:last_suggest_error = a:message
    let s:last_suggest_error_at = l:now
    call wplus#util#error_msg('ai', a:message)
endfunction

function! s:build_request_payload(prompt, ...) abort
    let l:prov = s:get_provider(g:wplus_ai_provider)
    if empty(l:prov) | return '' | endif
    let l:max_tokens = a:0 >= 1 && a:1 > 0 ? a:1 : get(g:, 'wplus_ai_max_tokens', 2048)
    let l:temperature = a:0 >= 2 ? a:2 : get(g:, 'wplus_ai_temperature', 0.7)
    let l:spec = {
        \ 'system': 'You are a helpful code assistant. Provide concise, accurate responses.',
        \ 'user': a:prompt,
        \ 'max_tokens': l:max_tokens,
        \ 'temperature': l:temperature,
        \ 'purpose': 'command',
        \ }
    return call(l:prov.payload, [l:spec])
endfunction

function! s:on_response(request_id, channel, msg) abort
    if !has_key(s:command_requests, a:request_id)
        return
    endif
    let l:req = s:command_requests[a:request_id]
    if strlen(l:req.response_buffer) + strlen(a:msg) > g:wplus_ai_response_max_bytes
        let l:req.error_buffer .= 'AI response exceeded g:wplus_ai_response_max_bytes'
        let s:command_requests[a:request_id] = l:req
        silent! call job_stop(l:req.job)
        return
    endif
    let l:req.response_buffer .= a:msg
    let s:command_requests[a:request_id] = l:req
endfunction

function! s:on_response_complete(request_id, channel) abort
    if !has_key(s:command_requests, a:request_id)
        return
    endif
    let l:request = remove(s:command_requests, a:request_id)
    call s:cleanup_curl_config(get(l:request, 'curl_config', ''))

    let l:response = trim(l:request.response_buffer)
    let l:err_buf = trim(get(l:request, 'error_buffer', ''))

    if empty(l:response)
        if !empty(l:err_buf)
            call wplus#util#error_msg('ai', 'request error: ' . l:err_buf)
        else
            call wplus#util#error_msg('ai', 'empty response from API')
        endif
        return
    endif

    try
        let l:json = json_decode(l:response)
    catch
        if !empty(l:err_buf)
            call wplus#util#error_msg('ai', 'request error: ' . l:err_buf)
        else
            call wplus#util#error_msg('ai', 'failed to parse response: ' . (len(l:response) > 100 ? l:response[:100] . '...' : l:response))
        endif
        return
    endtry

    " Extract content based on provider
    let l:content = s:sanitize_ai_text(s:extract_response_content(l:json))
    if empty(l:content)
        let l:error_msg = s:extract_error_message(l:json)
        if !empty(l:error_msg)
            call wplus#util#error_msg('ai', l:error_msg)
        else
            call wplus#util#error_msg('ai', 'no content in response')
        endif
        return
    endif

    call l:request.on_content(l:content)
endfunction

" ── Response preview popup (accept/discard before touching the buffer) ────

let s:ai_preview_apply = v:null

" Show a:lines in a centered popup highlighted as a:ft. On accept, call
" a:ApplyFn (a zero-arg partial with all context already bound); on
" discard, drop it. Used by every AI command below so a
" response is never written to a buffer/register without explicit accept.
function! s:open_ai_preview(ft, lines, ApplyFn) abort
    let s:ai_preview_apply = a:ApplyFn
    if !exists('*popup_create')
        if !empty(a:ApplyFn) | call a:ApplyFn() | endif
        return
    endif
    let l:header = '[wplus-ai] Enter/a = apply   Esc/q = discard'
    let l:width  = float2nr(&columns * 0.6)
    let l:height = min([len(a:lines) + 2, float2nr(&lines * 0.6)])
    let l:winid = popup_create([l:header, repeat('─', max([min([l:width - 4, 60]), 1]))] + a:lines, {
        \ 'title': ' AI Preview ',
        \ 'line': (&lines - l:height) / 2,
        \ 'col': (&columns - l:width) / 2,
        \ 'minwidth': l:width, 'maxwidth': l:width,
        \ 'minheight': l:height, 'maxheight': l:height,
        \ 'border': [1, 1, 1, 1],
        \ 'padding': [0, 1, 0, 1],
        \ 'filter': 'wplus#ai#preview_filter',
        \ 'mapping': 0,
        \ })
    call setbufvar(winbufnr(l:winid), '&filetype', a:ft)
endfunction

function! wplus#ai#preview_filter(winid, key) abort
    call popup_close(a:winid)
    let l:Apply = s:ai_preview_apply
    let s:ai_preview_apply = v:null
    if a:key ==# "\<CR>" || a:key ==? 'a'
        if !empty(l:Apply) | call l:Apply() | endif
    else
        call wplus#util#info_msg('ai', 'discarded')
    endif
    return 1
endfunction

" ── Apply callbacks (each is bound via function(name, [args]) partials) ───

function! s:apply_insert_after(bufnr, lnum, lines) abort
    if !bufloaded(a:bufnr) | return | endif
    call appendbufline(a:bufnr, a:lnum, a:lines)
    call wplus#util#info_msg('ai', 'response inserted')
endfunction

function! s:apply_replace_range(bufnr, start, end, lines) abort
    if !bufloaded(a:bufnr) | return | endif
    call deletebufline(a:bufnr, a:start, a:end)
    call appendbufline(a:bufnr, a:start - 1, a:lines)
    call wplus#util#info_msg('ai', 'replaced')
endfunction

function! s:apply_commit(msg) abort
    call setreg('"', a:msg)
    if has('clipboard') | silent! call setreg('+', a:msg) | endif
    if &filetype ==# 'gitcommit'
        call append(0, split(a:msg, "\n"))
        call wplus#util#info_msg('ai', 'commit message inserted')
    else
        call wplus#util#info_msg('ai', 'commit message copied to register "')
    endif
endfunction

" ── OnContent callbacks: parse response text into lines, show preview ─────

function! s:preview_insert_after(bufnr, lnum, content) abort
    let l:lines = split(a:content, "\n")
    if empty(l:lines) | call wplus#util#warn_msg('ai', 'empty response') | return | endif
    call s:open_ai_preview(getbufvar(a:bufnr, '&filetype'), l:lines,
        \ function('s:apply_insert_after', [a:bufnr, a:lnum, l:lines]))
endfunction

function! s:preview_replace_range(bufnr, start, end, content) abort
    let l:lines = split(a:content, "\n")
    if empty(l:lines) | call wplus#util#warn_msg('ai', 'empty response') | return | endif
    call s:open_ai_preview(getbufvar(a:bufnr, '&filetype'), l:lines,
        \ function('s:apply_replace_range', [a:bufnr, a:start, a:end, l:lines]))
endfunction

function! s:clean_commit_message(content) abort
    let l:txt = s:sanitize_ai_text(a:content)
    " Remove completed <think>...</think> and <thought>...</thought> tags
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.\{-}</\%(think\|thought\)>', '', 'g')
    " Remove unclosed <think> or <thought> tags to the end
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.*$', '', 'g')
    " Remove markdown code blocks (e.g. ```gitcommit ... ```)
    let l:txt = substitute(l:txt, '\v^```%(gitcommit|text|markdown)?\s*\n', '', 'g')
    let l:txt = substitute(l:txt, '\v\n```\s*$', '', 'g')
    let l:txt = substitute(l:txt, '```', '', 'g')
    return trim(l:txt)
endfunction

function! s:preview_commit(content) abort
    let l:msg = s:clean_commit_message(a:content)
    if empty(l:msg) | call wplus#util#warn_msg('ai', 'empty commit message') | return | endif
    call s:open_ai_preview('gitcommit', split(l:msg, "\n"), function('s:apply_commit', [l:msg]))
endfunction

function! wplus#ai#comment(range_type) abort
    " Generate comment for current selection/function
    let l:bufnr = bufnr('%')
    let l:lnum = line('.')

    if a:range_type ==# 'visual'
        let [l:line_start, l:col_start] = getpos("'<")[1:2]
        let [l:line_end, l:col_end] = getpos("'>")[1:2]
        let l:code = join(getline(l:line_start, l:line_end), "\n")
    else
        let l:code = getline(l:lnum)
    endif

    let l:prompt = "Write a concise comment for this code:\n\n" . l:code
    call s:send_request(l:prompt, function('s:preview_insert_after', [l:bufnr, l:lnum]))
endfunction

function! wplus#ai#complete(context_lines) abort
    " Generate code completion
    let l:bufnr = bufnr('%')
    let l:lnum = line('.')
    let l:col = col('.')

    let l:start = max([1, l:lnum - a:context_lines])
    let l:context = join(getline(l:start, l:lnum), "\n")

    let l:prompt = "Complete this code. Respond with only the completion, no explanation:\n\n" . l:context
    call s:send_request(l:prompt, function('s:preview_insert_after', [l:bufnr, l:lnum]))
endfunction

function! wplus#ai#refactor() abort
    " Suggest refactoring; replaces the visual selection on accept.
    let l:bufnr = bufnr('%')
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end, l:col_end] = getpos("'>")[1:2]
    let l:code = join(getline(l:line_start, l:line_end), "\n")

    let l:prompt = "Refactor this code to be more efficient and readable. "
        \ . "Return ONLY the replacement code for these lines, no explanation, no markdown code fences:\n\n"
        \ . l:code
    call s:send_request(l:prompt, function('s:preview_replace_range', [l:bufnr, l:line_start, l:line_end]))
endfunction

" Explain and fix the LSP diagnostic on the current line, replacing just
" that line on accept. Requires lsp.vim to be running for this filetype
" (b:wplus_lsp_diags is populated by wplus#lsp#setup()'s diagnostic handler).
function! wplus#ai#fix_diagnostic() abort
    let l:bufnr = bufnr('%')
    let l:lnum = line('.')
    let l:diags = getbufvar(l:bufnr, 'wplus_lsp_diags', {})
    if !has_key(l:diags, l:lnum)
        call wplus#util#warn_msg('ai', 'no diagnostic on this line')
        return
    endif
    let l:diag = l:diags[l:lnum]

    " get_prefix(lnum, 1, ...) excludes the current line; get_suffix must be
    " called with lnum+1 for the same reason, else it re-includes it (see
    " ai/context.vim get_suffix: col=1 keeps the whole line at line_nr).
    let l:prefix = wplus#ai#context#get_prefix(l:lnum, 1, 15)
    let l:suffix = wplus#ai#context#get_suffix(l:lnum + 1, 1, 15)
    let l:line   = getline(l:lnum)

    let l:prompt = "The following " . &filetype . " code has a diagnostic on the marked line.\n"
        \ . "Diagnostic: " . l:diag.msg . "\n\n"
        \ . "Code before:\n" . l:prefix . "\n\n"
        \ . ">>> " . l:line . "\n\n"
        \ . "Code after:\n" . l:suffix . "\n\n"
        \ . "Return ONLY the corrected replacement for the marked line (prefixed with >>>). "
        \ . "No explanation, no markdown fences, no line-number prefix."
    call s:send_request(l:prompt, function('s:preview_replace_range', [l:bufnr, l:lnum, l:lnum]))
endfunction

" Generate a commit message from the staged (git diff --cached) changes.
" On accept: copied to the unnamed (and system, if available) register, and
" auto-inserted at the top of the buffer when it's a gitcommit buffer.
function! wplus#ai#commit_message() abort
    let l:file = expand('%:p')
    let l:root = !empty(l:file) ? wplus#util#find_git_root(fnamemodify(l:file, ':h')) : ''
    if empty(l:root)
        let l:root = wplus#util#find_git_root(getcwd())
    endif
    if empty(l:root)
        call wplus#util#error_msg('ai', 'not a git repository')
        return
    endif
    if g:wplus_ai_provider !=# 'ollama' && empty(g:wplus_ai_api_key)
        call wplus#util#error_msg('ai', 'API key not configured (g:wplus_ai_api_key)')
        return
    endif
    if empty(g:wplus_ai_model)
        call wplus#util#error_msg('ai', 'model not configured (g:wplus_ai_model)')
        return
    endif

    let l:stat_lines = []
    call job_start(['git', '-C', l:root, 'diff', '--cached', '--stat'], {
        \ 'out_cb':   {_, l -> add(l:stat_lines, l)},
        \ 'close_cb': {_ -> s:on_commit_stat_done(l:root, l:stat_lines)},
        \ 'err_cb':   {_ch, _msg -> 0},
        \ })
    call wplus#util#info_msg('ai', 'reading staged changes...')
endfunction

function! s:on_commit_stat_done(root, stat_lines) abort
    let l:stat = trim(join(a:stat_lines, "\n"))
    if empty(l:stat)
        call wplus#util#warn_msg('ai', 'no staged changes (git add first)')
        return
    endif
    let l:diff_lines = []
    call job_start(['git', '-C', a:root, 'diff', '--cached'], {
        \ 'out_cb':   {_, l -> add(l:diff_lines, l)},
        \ 'close_cb': {_ -> s:on_commit_diff_collected(l:stat, l:diff_lines)},
        \ 'err_cb':   {_ch, _msg -> 0},
        \ })
endfunction

function! s:build_commit_prompt(stat, diff) abort
    if !empty(g:wplus_ai_commit_prompt)
        let l:p = g:wplus_ai_commit_prompt
        let l:p = substitute(l:p, '{stat}', escape(a:stat, '&~'), 'g')
        let l:p = substitute(l:p, '{diff}', escape(a:diff, '&~'), 'g')
        return l:p
    endif

    let l:prompt = "You are an expert software developer writing a Git commit message in Korean.\n"
        \ . "Based on the staged changes below, write a structured and detailed Git commit message following the Conventional Commits convention.\n\n"
        \ . "### Requirements:\n"
        \ . "1. First line: '<type>(<scope>): <summary>' (e.g. feat(ai): ..., fix(auth): ..., refactor(core): ...). Max 50 chars in Korean.\n"
        \ . "2. Second line: Leave a blank line.\n"
        \ . "3. Third line onwards (Body): Write a clear, bulleted list ('- ') explaining WHAT changed and WHY. Cover all significant modified modules/files with sufficient detail without cutting off.\n"
        \ . "4. Do NOT output markdown code fences (no ```), no <think> tags, and no meta-commentary. Output ONLY the raw commit message.\n\n"
        \ . "### Changed Files (Diff Stat):\n" . a:stat . "\n\n"
        \ . "### Diff:\n" . a:diff
    return l:prompt
endfunction

function! s:on_commit_diff_collected(stat, lines) abort
    let l:diff = join(a:lines, "\n")
    if empty(trim(l:diff))
        call wplus#util#warn_msg('ai', 'no staged changes (git add first)')
        return
    endif
    let l:max = g:wplus_ai_commit_diff_max_bytes
    if len(l:diff) > l:max
        call wplus#util#warn_msg('ai', 'diff too large (' . (len(l:diff)/1024) . 'KB), truncating to ' . (l:max/1024) . 'KB')
        let l:diff = l:diff[:l:max - 1]
        let l:last_nl = strridx(l:diff, "\n")
        if l:last_nl > 0
            let l:diff = l:diff[:l:last_nl]
        endif
    endif
    let l:prompt = s:build_commit_prompt(a:stat, l:diff)
    call s:send_request(l:prompt, function('s:preview_commit'), g:wplus_ai_commit_max_tokens, 0.3)
endfunction

function! s:send_request(prompt, OnContent, ...) abort
    if g:wplus_ai_provider !=# 'ollama' && empty(g:wplus_ai_api_key)
        call wplus#util#error_msg('ai', 'API key not configured (g:wplus_ai_api_key)')
        return
    endif

    if s:reject_sensitive_context(a:prompt)
        return
    endif

    if empty(g:wplus_ai_model)
        call wplus#util#error_msg('ai', 'model not configured (g:wplus_ai_model)')
        return
    endif

    let l:endpoint = s:get_api_endpoint()
    let l:headers = s:get_request_headers()
    if empty(l:headers) | return | endif

    let l:max_tokens = a:0 >= 1 && a:1 > 0 ? a:1 : get(g:, 'wplus_ai_max_tokens', 2048)
    let l:temperature = a:0 >= 2 ? a:2 : get(g:, 'wplus_ai_temperature', 0.7)
    let l:payload = s:build_request_payload(a:prompt, l:max_tokens, l:temperature)
    if strlen(l:payload) > g:wplus_ai_request_max_bytes
        call wplus#util#error_msg('ai', 'request exceeds g:wplus_ai_request_max_bytes')
        return
    endif
    let l:request_id = reltimestr(reltime())
    let l:transport = s:build_curl_command(l:endpoint, l:headers, g:wplus_ai_timeout)
    if empty(l:transport.cmd)
        call wplus#util#error_msg('ai', 'failed to create private curl config')
        return
    endif
    let l:cmd = l:transport.cmd

    let s:command_requests[l:request_id] = {
        \ 'job': v:null,
        \ 'on_content': a:OnContent,
        \ 'response_buffer': '',
        \ 'error_buffer': '',
        \ 'curl_config': l:transport.config,
        \ }

    let l:job = job_start(l:cmd, {
        \ 'in_mode': 'raw',
        \ 'out_cb': function('s:on_response', [l:request_id]),
        \ 'close_cb': function('s:on_response_complete', [l:request_id]),
        \ 'err_cb': function('s:on_error', [l:request_id])
        \ })
    if type(l:job) != v:t_job
        call remove(s:command_requests, l:request_id)
        call s:cleanup_curl_config(l:transport.config)
        call wplus#util#error_msg('ai', 'failed to start request')
        return
    endif

    let s:command_requests[l:request_id].job = l:job
    call s:write_payload_stdin(l:job, l:payload)
    call wplus#util#info_msg('ai', 'sending request...')
endfunction

function! s:on_error(request_id, channel, msg) abort
    if has_key(s:command_requests, a:request_id)
        let s:command_requests[a:request_id].error_buffer .= a:msg . "\n"
    endif
endfunction

" ── Review / Explain ──────────────────────────────────────────────────────

" Open a dedicated read-only split to display AI review/explain output.
function! s:open_result_split(ft, lines, title) abort
    " Reuse an existing wplus-ai-result window if one is visible.
    for l:win in range(1, winnr('$'))
        if getwinvar(l:win, 'wplus_ai_result', 0)
            execute l:win . 'wincmd w'
            setlocal modifiable
            silent %delete _
            call setline(1, a:lines)
            setlocal nomodifiable
            return
        endif
    endfor
    botright 15new
    let w:wplus_ai_result = 1
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    execute 'setlocal filetype=' . a:ft
    setlocal modifiable
    call setline(1, a:lines)
    setlocal nomodifiable
    execute 'setlocal statusline=\ 🤖\ ' . escape(a:title, ' \')
    nnoremap <buffer> <silent> q :close<CR>
endfunction

function! wplus#ai#review() range abort
    let l:bufnr = bufnr('%')
    let l:ft = &filetype
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end,   l:col_end]   = getpos("'>")[1:2]
    " Fall back to current line when called from Normal mode
    if l:line_start == 0
        let l:line_start = line('.')
        let l:line_end   = line('.')
    endif
    let l:code = join(getline(l:line_start, l:line_end), "\n")
    let l:prompt = "Review the following " . l:ft . " code. "
        \ . "List issues, potential bugs, security concerns, and improvement suggestions. "
        \ . "Be concise and use bullet points.\n\n```" . l:ft . "\n" . l:code . "\n```"
    call s:send_request(l:prompt, function('s:show_review_result', [l:ft]))
    call wplus#util#info_msg('ai', 'reviewing code...')
endfunction

function! s:show_review_result(ft, content) abort
    let l:lines = split(a:content, "\n")
    call s:open_result_split('markdown', l:lines, 'AI Code Review')
endfunction

function! wplus#ai#explain() range abort
    let l:ft = &filetype
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end,   l:col_end]   = getpos("'>")[1:2]
    if l:line_start == 0
        let l:line_start = line('.')
        let l:line_end   = line('.')
    endif
    let l:code = join(getline(l:line_start, l:line_end), "\n")
    let l:prompt = "Explain what the following " . l:ft . " code does step by step. "
        \ . "Keep the explanation concise and clear.\n\n```" . l:ft . "\n" . l:code . "\n```"
    call s:send_request(l:prompt, function('s:show_review_result', ['markdown']))
    call wplus#util#info_msg('ai', 'explaining code...')
endfunction

function! wplus#ai#setup() abort
    augroup WplusAI
        autocmd!
        autocmd VimLeavePre * for req in values(s:command_requests) | silent! call job_stop(req.job) | call s:cleanup_curl_config(get(req, 'curl_config', '')) | endfor
        autocmd VimLeavePre * if !empty(s:suggest_request) | silent! call job_stop(s:suggest_request.job) | call s:cleanup_curl_config(get(s:suggest_request, 'curl_config', '')) | endif
        " Invalidate context cache on buffer changes so symbols/scope stay fresh.
        autocmd BufEnter,FileType,BufWritePost * call wplus#ai#context#invalidate(bufnr('%'))
    augroup END
    
    " Warn if not configured, but still register commands
    if empty(g:wplus_ai_model)
        if g:wplus_ai_provider ==# 'ollama'
            call wplus#util#warn_msg('ai', 'Ollama: Set g:wplus_ai_model and optionally g:wplus_ai_ollama_host')
        elseif g:wplus_ai_provider ==# 'azure'
            call wplus#util#warn_msg('ai', 'Azure: Set g:wplus_ai_api_key, g:wplus_ai_azure_resource, g:wplus_ai_azure_deployment')
        elseif g:wplus_ai_provider ==# 'claude'
            call wplus#util#warn_msg('ai', 'Claude: Set g:wplus_ai_api_key, g:wplus_ai_model')
        else
            call wplus#util#warn_msg('ai', 'OpenAI: Set g:wplus_ai_api_key, g:wplus_ai_model')
        endif
    endif
    
    " Commands
    command! -range WaiComment   call wplus#ai#comment('visual')
    command! -nargs=? WaiComplete call wplus#ai#complete(<q-args> != '' ? <q-args> : 5)
    command! -range WaiRefactor  call wplus#ai#refactor()
    command! WaiFixDiag          call wplus#ai#fix_diagnostic()
    command! WaiCommitMsg        call wplus#ai#commit_message()
    command! WaiToggleSuggest    call wplus#ai#toggle_suggest()
    command! WaiAcceptSuggest    call wplus#ai#accept_suggestion_insert()
    command! WaiDismissSuggest   call wplus#ai#dismiss_suggestion()
    command! WaiAcceptWord       call wplus#ai#accept_suggestion_insert_word()
    command! -range WaiReview    <line1>,<line2>call wplus#ai#review()
    command! -range WaiExplain   <line1>,<line2>call wplus#ai#explain()
    command! WaiCancel           call wplus#ai#cancel()

    " Mappings
    nnoremap <silent> <Plug>WaiComment   :WaiComment<CR>
    nnoremap <silent> <Plug>WaiComplete  :WaiComplete<CR>
    xnoremap <silent> <Plug>WaiRefactor  :WaiRefactor<CR>
    nnoremap <silent> <Plug>WaiFixDiag   :WaiFixDiag<CR>
    nnoremap <silent> <Plug>WaiCommitMsg :WaiCommitMsg<CR>
    xnoremap <silent> <Plug>WaiReview    :WaiReview<CR>
    xnoremap <silent> <Plug>WaiExplain   :WaiExplain<CR>
    nnoremap <silent> <Plug>WaiToggleSuggest :WaiToggleSuggest<CR>
    inoremap <silent> <Plug>WaiDismissSuggest <C-r>=wplus#ai#dismiss_suggestion()<CR>
    inoremap <silent> <expr> <Plug>WaiAcceptSuggest wplus#ai#accept_suggestion()
    inoremap <silent> <expr> <Plug>WaiAcceptWord wplus#ai#accept_word_suggestion()
    inoremap <silent> <expr> <Plug>WaiSmartTab wplus#ai#smart_tab()
    nnoremap <silent> <leader>ac :WaiCancel<CR>

    if g:wplus_ai_tab_complete && empty(maparg('<Tab>', 'i'))
        imap <expr> <Tab> wplus#ai#smart_tab()
    endif

    if g:wplus_ai_suggest_enabled
        augroup WplusAISuggest
            autocmd!
            autocmd InsertEnter * call s:on_insert_enter()
            autocmd InsertLeave * call s:dismiss_suggestion()
            autocmd TextChangedI * call s:on_text_changed()
        augroup END
    endif
endfunction

" ── Ghost Text Suggestion Functions ────────────────────────────────────────────

" Show Ghost Text suggestion with textprop
function! s:show_suggestion() abort
    let l:bufnr = s:suggest_bufnr

    " Ensure the text property type exists. It is normally registered in
    " plugin/wplus.vim and re-registered in setup(), but some load orders
    " (e.g. plugin sourced before highlight groups, or :source of autoload
    " alone in tests) can leave it missing. prop_add/prop_remove would then
    " throw E971 and silently swallow the suggestion.
    if empty(prop_type_get('WplusAISuggest'))
        if !hlexists('WplusAISuggest')
            if hlexists('Comment')
                highlight default link WplusAISuggest Comment
            else
                highlight default WplusAISuggest ctermfg=244 guifg=#7c6f64
            endif
        endif
        call prop_type_add('WplusAISuggest', {'highlight': 'WplusAISuggest'})
    endif

    if bufloaded(l:bufnr)
        silent! call prop_remove({'type': 'WplusAISuggest', 'all': 1, 'bufnr': l:bufnr})
    endif

    if empty(s:suggest_content) | return | endif
    if !bufloaded(l:bufnr) | return | endif

    let l:lines = split(s:suggest_content, "\n", 1)
    let l:line = s:suggest_line
    let l:col  = s:suggest_col

    try
        " First line appended to current line
        if !empty(l:lines[0])
            call prop_add(l:line, l:col, {
                \ 'type': 'WplusAISuggest',
                \ 'bufnr': l:bufnr,
                \ 'text': l:lines[0],
                \ 'id': 1,
                \ })
        endif

        " Remaining lines as virtual lines below
        let l:i = 1
        while l:i < len(l:lines)
            let l:text = l:lines[l:i]
            if empty(l:text) | let l:text = ' ' | endif
            call prop_add(l:line, 0, {
                \ 'type': 'WplusAISuggest',
                \ 'bufnr': l:bufnr,
                \ 'text': l:text,
                \ 'text_align': 'below',
                \ 'id': 1 + l:i,
                \ })
            let l:i += 1
        endwhile

        redraw
    catch
        call s:suggest_debug('failed to render ghost text: ' . v:exception)
    endtry
endfunction

" Dismiss current suggestion
function! s:dismiss_suggestion() abort
    let l:bufnr = s:suggest_bufnr
    let s:suggest_content = ''
    let s:suggest_line = 0
    let s:suggest_col = 0
    let s:suggest_bufnr = 0

    if s:suggest_timer != v:null
        call timer_stop(s:suggest_timer)
        let s:suggest_timer = v:null
    endif

    if !empty(s:suggest_request) && has_key(s:suggest_request, 'job')
        silent! call job_stop(s:suggest_request.job)
        call s:cleanup_curl_config(get(s:suggest_request, 'curl_config', ''))
        let s:suggest_request = {}
    endif

    if l:bufnr > 0 && bufloaded(l:bufnr)
        call prop_remove({'type': 'WplusAISuggest', 'all': 1, 'bufnr': l:bufnr})
    endif
endfunction

" Insert trusted, sanitized text at the current cursor without feeding it back
" through Vim's key parser. Command variants use this helper; expression
" mappings return plain text directly to Vim.
function! s:insert_text_at_cursor(content) abort
    let l:lines = split(s:sanitize_ai_text(a:content), "\n", 1)
    if empty(l:lines) | return | endif
    let l:lnum = line('.')
    let l:byte = col('.') - 1
    let l:current = getline(l:lnum)
    let l:prefix = strpart(l:current, 0, l:byte)
    let l:suffix = strpart(l:current, l:byte)
    let l:replacement = copy(l:lines)
    let l:replacement[0] = l:prefix . l:replacement[0]
    let l:replacement[-1] .= l:suffix
    call setline(l:lnum, l:replacement[0])
    if len(l:replacement) > 1
        call appendbufline(bufnr('%'), l:lnum, l:replacement[1:])
    endif
    call cursor(l:lnum + len(l:replacement) - 1, strlen(l:replacement[-1]) + 1)
endfunction

" Accept current suggestion. Returns plain text suitable for <expr> mappings.
function! wplus#ai#accept_suggestion() abort
    if empty(s:suggest_content)
        " No suggestion, insert normal tab
        return "\<Tab>"
    endif

    let l:content = s:sanitize_ai_text(s:suggest_content)
    call s:dismiss_suggestion()
    call s:suggest_debug('suggestion accepted')
    return substitute(l:content, '\n', "\<CR>", 'g')
endfunction

" Command variant: insert the suggestion at cursor without returning a string.
function! wplus#ai#accept_suggestion_insert() abort
    if empty(s:suggest_content)
        return
    endif
    let l:content = s:sanitize_ai_text(s:suggest_content)
    call s:dismiss_suggestion()
    if mode() =~# 'i'
        call s:insert_text_at_cursor(l:content)
    else
        " Best-effort in normal mode: append after cursor line
        call append(line('.'), split(l:content, "\n", 1))
    endif
    call s:suggest_debug('suggestion accepted (insert)')
endfunction

" Smart Tab handler:
" 1. If Ghost Text is active -> accept suggestion
" 2. If completion popup is visible -> select next item (<C-n>)
" 3. Otherwise -> normal <Tab>
function! wplus#ai#smart_tab() abort
    if wplus#ai#has_suggestion()
        return wplus#ai#accept_suggestion()
    endif
    if pumvisible()
        return "\<C-n>"
    endif
    return "\<Tab>"
endfunction

function! wplus#ai#has_suggestion() abort
    return !empty(s:suggest_content)
endfunction

" Public dismiss for <Plug>WaiDismissSuggest mapping.
function! wplus#ai#dismiss_suggestion() abort
    call s:dismiss_suggestion()
endfunction

" Accept only the next word of the suggestion and keep the rest visible.
" Returns a string suitable for <expr> mappings. If no suggestion, falls back
" to a literal space so the cursor still advances when bound to a key.
function! wplus#ai#accept_word_suggestion() abort
    if empty(s:suggest_content)
        return "\<Space>"
    endif
    let l:content = s:suggest_content
    " First whitespace-separated token + the trailing whitespace (if any).
    let l:match = matchlist(l:content, '^\(\s*\S\+\)\(\s\?\)\(.*\)$')
    if empty(l:match)
        call s:dismiss_suggestion()
        return ''
    endif
    let l:word = s:sanitize_ai_text(l:match[1])
    let l:rest = s:sanitize_ai_text(l:match[3])
    if empty(l:rest)
        call s:dismiss_suggestion()
    else
        " Update ghost text to the remaining suggestion.
        let s:suggest_content = l:rest
        call s:show_suggestion()
    endif
    call s:suggest_debug('accepted word: ' . l:word)
    return substitute(l:word, '\n', "\<CR>", 'g')
endfunction

" Command variant of accept-word: inserts via the buffer API.
function! wplus#ai#accept_suggestion_insert_word() abort
    if empty(s:suggest_content)
        return
    endif
    let l:word = wplus#ai#accept_word_suggestion()
    if !empty(l:word) && mode() =~# 'i'
        call s:insert_text_at_cursor(l:word)
    endif
endfunction

" Toggle suggestions on/off
function! wplus#ai#toggle_suggest() abort
    let g:wplus_ai_suggest_enabled = !g:wplus_ai_suggest_enabled
    if g:wplus_ai_suggest_enabled
        call wplus#util#info_msg('ai', 'Ghost Text suggestions enabled')
        augroup WplusAISuggest
            autocmd!
            autocmd InsertEnter * call s:on_insert_enter()
            autocmd InsertLeave * call s:dismiss_suggestion()
            autocmd TextChangedI * call s:on_text_changed()
        augroup END
    else
        call wplus#util#info_msg('ai', 'Ghost Text suggestions disabled')
        call s:dismiss_suggestion()
        augroup WplusAISuggest
            autocmd!
        augroup END
    endif
endfunction

" Timer callback for delayed suggestion trigger
function! s:on_suggest_timer(timer) abort
    " Check if cursor is still in same position
    if line('.') != s:suggest_line || col('.') != s:suggest_col
        return
    endif
    
    " Skip if in comment
    if wplus#ai#context#is_in_comment()
        return
    endif
    
    let l:prefix = wplus#ai#context#get_prefix(s:suggest_line, s:suggest_col, g:wplus_ai_suggest_context_lines)
    let l:suffix = wplus#ai#context#get_suffix(s:suggest_line, s:suggest_col, g:wplus_ai_suggest_suffix_lines)

    if s:reject_sensitive_context(l:prefix . "\n" . l:suffix)
        return
    endif

    " Don't suggest if prefix is empty or only whitespace
    if empty(trim(l:prefix)) && empty(trim(l:suffix))
        call s:suggest_debug('skipped empty context')
        return
    endif
    
    " Build suggestion request
    let l:max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
    let l:prompt = "Complete the following code. Return only the completion without explanation or markdown. Keep your suggestion short (maximum " . l:max_lines . " lines):\n\n"
          \ . "Prefix:\n" . l:prefix . "\n\n"
          \ . "Suffix:\n" . l:suffix . "\n\n"
          \ . "Completion:"
    
    call s:send_suggest_request(l:prefix, l:suffix, l:prompt)
endfunction

" TextChangedI handler for Ghost Text
function! s:on_text_changed() abort
    if !g:wplus_ai_suggest_enabled
        return
    endif

    let s:suggest_keystroke_count += 1
    call s:dismiss_suggestion()
    let s:suggest_line = line('.')
    let s:suggest_col = col('.')
    let s:suggest_bufnr = bufnr('%')
    
    let l:delay = g:wplus_ai_suggest_delay
    if s:suggest_keystroke_count > 5
        let l:delay = l:delay * 2
    endif
    
    let s:suggest_timer = timer_start(l:delay, function('s:on_suggest_timer'))
endfunction

" InsertEnter handler
function! s:on_insert_enter() abort
    let s:suggest_keystroke_count = 0
endfunction

" Prepend language, scope, and symbols to improve suggestion accuracy
function! s:suggest_context_hint() abort
    let l:parts = []
    if !empty(&filetype)
        call add(l:parts, 'Language: ' . &filetype)
    endif
    let l:scope = wplus#ai#context#get_scope()
    if !empty(l:scope)
        call add(l:parts, 'Enclosing scope: ' . l:scope)
    endif
    let l:syms = wplus#ai#context#extract_symbols()
    if !empty(l:syms)
        call add(l:parts, 'Known symbols: ' . join(l:syms[0:19], ', '))
    endif
    if empty(l:parts) | return '' | endif
    return join(l:parts, "\n") . "\n\n"
endfunction

" Build suggestion prompt for all providers
function! s:build_suggest_payload(prefix, suffix) abort
    let l:prov = s:get_provider(g:wplus_ai_provider)
    if empty(l:prov) | return '' | endif

    let l:max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
    let l:system_msg = 'You are a code completion assistant. Complete the code based on context. Return only the completion without explanation or code blocks. Keep your suggestion short (maximum ' . l:max_lines . ' lines).'
    let l:prompt = s:suggest_context_hint() . "Complete this code:\n\nPrefix:\n" . a:prefix . "\n\nSuffix:\n" . a:suffix

    let l:spec = {
        \ 'system': l:system_msg,
        \ 'user': l:prompt,
        \ 'prefix': a:prefix,
        \ 'suffix': a:suffix,
        \ 'max_tokens': get(g:, 'wplus_ai_suggest_max_tokens', 128),
        \ 'temperature': get(g:, 'wplus_ai_suggest_temperature', 0.2),
        \ 'purpose': 'suggest',
        \ }
    return call(l:prov.payload, [l:spec])
endfunction

function! s:on_suggest_response(request_id, channel, msg) abort
    if empty(s:suggest_request) || get(s:suggest_request, 'request_id', -1) != a:request_id
        return
    endif
    if strlen(s:suggest_request.response_buffer) + strlen(a:msg) > g:wplus_ai_response_max_bytes
        call s:report_suggest_error('AI response exceeded g:wplus_ai_response_max_bytes')
        silent! call job_stop(s:suggest_request.job)
        let s:suggest_request = {}
        return
    endif
    let s:suggest_request.response_buffer .= a:msg
endfunction

" Complete response handler for suggestions. request_id is bound via partial.
function! s:on_suggest_response_complete(request_id, channel) abort
    if empty(s:suggest_request) || get(s:suggest_request, 'request_id', -1) != a:request_id
        return
    endif
    let l:request = s:suggest_request
    let s:suggest_request = {}
    call s:cleanup_curl_config(get(l:request, 'curl_config', ''))

    let l:response = l:request.response_buffer

    if empty(l:response)
        call s:suggest_debug('empty suggestion response')
        return
    endif

    try
        let l:json = json_decode(l:response)
    catch
        call s:suggest_debug('failed to parse suggestion response')
        return
    endtry

    " FIM(/api/generate)은 응답이 {"response": ...} 형식
    if get(l:request, 'fim', 0)
        let l:content = get(l:json, 'response', '')
    else
        let l:content = s:extract_response_content(l:json)
    endif
    if empty(l:content)
        let l:error_msg = s:extract_error_message(l:json)
        " FIM 미지원 모델이면 chat 방식으로 자동 폴백 후 재시도
        if l:error_msg =~? 'does not support insert'
            let g:wplus_ai_ollama_fim = 0
            call s:report_suggest_error('FIM 미지원 모델 → chat 방식으로 전환 (g:wplus_ai_ollama_fim=0)')
            " 커서가 여전히 제안 위치에 있을 때만 즉시 재시도
            if line('.') == l:request.line && col('.') == l:request.col && bufnr('%') == l:request.bufnr
                let l:prefix = wplus#ai#context#get_prefix(l:request.line, l:request.col, g:wplus_ai_suggest_context_lines)
                let l:suffix = wplus#ai#context#get_suffix(l:request.line, l:request.col, g:wplus_ai_suggest_suffix_lines)
                call s:send_suggest_request(l:prefix, l:suffix, '')
            endif
        elseif !empty(l:error_msg)
            call s:suggest_debug('api error: ' . l:error_msg)
            call s:report_suggest_error(l:error_msg)
        else
            call s:suggest_debug('no suggestion content in response')
        endif
        return
    endif

    let l:content = s:clean_suggest_content(l:content)

    let l:max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
    let l:lines = split(l:content, "\n", 1)
    if len(l:lines) > l:max_lines
        let l:content = join(l:lines[:l:max_lines - 1], "\n")
    endif

    " Only update if cursor is still at request position
    if line('.') == l:request.line && col('.') == l:request.col && bufnr('%') == l:request.bufnr
        let s:suggest_content = l:content
        let s:suggest_line = l:request.line
        let s:suggest_col = l:request.col
        let s:suggest_bufnr = l:request.bufnr
        call s:show_suggestion()
    else
        call s:suggest_debug('dropped stale suggestion response')
    endif
endfunction

" Send suggestion request to AI. a:prompt is ignored when provider uses FIM
" or builds its own prompt from prefix/suffix (ollama chat path falls back to
" build_suggest_payload internally when fim is off).
function! s:send_suggest_request(prefix, suffix, prompt) abort
    if (g:wplus_ai_provider !=# 'ollama' && empty(g:wplus_ai_api_key)) || empty(g:wplus_ai_model)
        call s:suggest_debug('missing API key or model')
        return
    endif

    let l:is_fim = s:use_ollama_fim()
    if l:is_fim
        let l:endpoint = g:wplus_ai_ollama_host . '/api/generate'
        let l:payload = s:build_ollama_fim_payload(a:prefix, a:suffix,
            \ g:wplus_ai_suggest_max_tokens, g:wplus_ai_suggest_temperature)
    else
        let l:endpoint = s:get_api_endpoint()
        if empty(l:endpoint)
            call s:suggest_debug('empty API endpoint')
            return
        endif
        let l:payload = s:build_suggest_payload(a:prefix, a:suffix)
    endif
    let l:headers = s:get_request_headers()
    if empty(l:headers) | return | endif

    if strlen(l:payload) > g:wplus_ai_request_max_bytes
        call s:report_suggest_error('suggestion context exceeds g:wplus_ai_request_max_bytes')
        return
    endif

    let l:transport = s:build_curl_command(l:endpoint, l:headers, g:wplus_ai_suggest_timeout)
    if empty(l:transport.cmd)
        call s:report_suggest_error('failed to create private curl config')
        return
    endif
    let l:cmd = l:transport.cmd

    if !empty(s:suggest_request)
        silent! call job_stop(s:suggest_request.job)
        let s:suggest_request = {}
    endif

    let s:suggest_request_id += 1
    let l:rid = s:suggest_request_id
    let l:job = job_start(l:cmd, {
        \ 'in_mode': 'raw',
        \ 'out_mode': 'raw',
        \ 'out_cb': function('s:on_suggest_response', [l:rid]),
        \ 'close_cb': function('s:on_suggest_response_complete', [l:rid]),
        \ })
    if type(l:job) != v:t_job
        call wplus#util#error_msg('ai', 'failed to start suggestion request')
        let s:suggest_request = {}
        return
    endif

    call s:write_payload_stdin(l:job, l:payload)
    let s:suggest_request = {
        \ 'request_id': l:rid,
        \ 'job': l:job,
        \ 'channel_key': s:channel_key(job_getchannel(l:job)),
        \ 'bufnr': bufnr('%'),
        \ 'lnum': line('.'),
        \ 'line': s:suggest_line,
        \ 'col': s:suggest_col,
        \ 'fim': l:is_fim,
        \ 'response_buffer': '',
        \ 'curl_config': l:transport.config
        \ }
    call s:suggest_debug('sent suggestion request' . (l:is_fim ? ' (FIM)' : ''))
endfunction

function! wplus#ai#cancel() abort
    for [l:req_id, l:req] in items(s:command_requests)
        if has_key(l:req, 'job') && type(l:req.job) == v:t_job
            try | call job_stop(l:req.job) | catch | endtry
        endif
        call s:cleanup_curl_config(get(l:req, 'curl_config', ''))
    endfor
    let s:command_requests = {}

    if !empty(s:suggest_request) && has_key(s:suggest_request, 'job') && type(s:suggest_request.job) == v:t_job
        try | call job_stop(s:suggest_request.job) | catch | endtry
        let s:suggest_request = {}
    endif
    call s:dismiss_suggestion()
    call wplus#util#info_msg('ai', 'All active AI requests cancelled.')
endfunction

function! wplus#ai#_test_build_suggest_payload(prefix, suffix) abort
    return s:build_suggest_payload(a:prefix, a:suffix)
endfunction

function! wplus#ai#_test_get_api_endpoint(...) abort
    return call('s:get_api_endpoint', a:000)
endfunction

function! wplus#ai#_test_write_payload_stdin(job, payload) abort
    call s:write_payload_stdin(a:job, a:payload)
endfunction

function! wplus#ai#_test_sanitize_text(text) abort
    return s:sanitize_ai_text(a:text)
endfunction

function! wplus#ai#_test_is_sensitive(text) abort
    return s:is_sensitive_context(a:text)
endfunction

function! wplus#ai#_test_set_suggestion(content) abort
    let s:suggest_content = a:content
endfunction

function! wplus#ai#_test_clean_commit(content) abort
    return s:clean_commit_message(a:content)
endfunction

function! wplus#ai#_test_build_commit_prompt(stat, diff) abort
    return s:build_commit_prompt(a:stat, a:diff)
endfunction
