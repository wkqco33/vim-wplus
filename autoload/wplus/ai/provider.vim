" wplus/ai/provider.vim — AI provider registry and payload builder

if exists('g:autoloaded_wplus_ai_provider') | finish | endif
let g:autoloaded_wplus_ai_provider = 1

let s:providers = {}
let s:fim_unsupported_models = {}

function! wplus#ai#provider#register(name, dict) abort
    let s:providers[a:name] = a:dict
endfunction

function! wplus#ai#provider#get(name) abort
    if !has_key(s:providers, a:name)
        call wplus#util#error_msg('ai', 'Unknown AI provider: "' . a:name . '". Registered providers: ' . join(keys(s:providers), ', '))
        return {}
    endif
    return s:providers[a:name]
endfunction

function! wplus#ai#provider#get_endpoint(...) abort
    let l:spec = a:0 > 0 ? a:1 : {}
    let l:prov = wplus#ai#provider#get(g:wplus_ai_provider)
    if empty(l:prov) | return '' | endif
    if type(l:prov.endpoint) == v:t_func
        return call(l:prov.endpoint, [l:spec])
    endif
    return l:prov.endpoint
endfunction

function! wplus#ai#provider#get_headers() abort
    let l:prov = wplus#ai#provider#get(g:wplus_ai_provider)
    if empty(l:prov) | return [] | endif
    let l:key = get(g:, 'wplus_ai_api_key', '')
    return call(l:prov.headers, [l:key])
endfunction

function! wplus#ai#provider#extract_content(json) abort
    if g:wplus_ai_provider ==# 'ollama'
        if has_key(a:json, 'message') && type(a:json.message) == v:t_dict
            return get(a:json.message, 'content', '')
        endif
        return ''
    endif
    let l:prov = wplus#ai#provider#get(g:wplus_ai_provider)
    if empty(l:prov) | return '' | endif
    return call(l:prov.extract, [a:json])
endfunction

function! wplus#ai#provider#extract_error(json) abort
    if has_key(a:json, 'error')
        if type(a:json.error) == v:t_dict
            return get(a:json.error, 'message', string(a:json.error))
        elseif type(a:json.error) == v:t_string
            return a:json.error
        endif
    endif
    let l:prov = wplus#ai#provider#get(g:wplus_ai_provider)
    if !empty(l:prov) && has_key(l:prov, 'error')
        return call(l:prov.error, [a:json])
    endif
    return ''
endfunction

function! wplus#ai#provider#get_completion_model() abort
    return !empty(g:wplus_ai_completion_model) ? g:wplus_ai_completion_model : g:wplus_ai_model
endfunction

function! wplus#ai#provider#use_ollama_fim() abort
    return g:wplus_ai_provider ==# 'ollama' && g:wplus_ai_ollama_fim && !get(s:fim_unsupported_models, wplus#ai#provider#get_completion_model(), 0)
endfunction

" Ollama accepts the suffix field only when the model's template implements
" FIM.  There is no reliable local model-name convention, so capability is
" learned from the first response rather than guessed from the model name.
function! wplus#ai#provider#is_fim_unsupported_error(message) abort
    let l:first = a:message =~? '\c\%(does\s\+not\s\+support\|not\s\+support\|unsupported\)\_.\{0,40}\%\(insert\|suffix\|fim\)'
    let l:second = a:message =~? '\c\%\(insert\|suffix\|fim\)\_.\{0,40}\%(not\s\+support\|unsupported\|unavailable\)'
    return l:first || l:second
endfunction

function! wplus#ai#provider#mark_fim_unsupported(model) abort
    let s:fim_unsupported_models[a:model] = 1
endfunction

function! wplus#ai#provider#ollama_options(max_tokens, temperature) abort
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

function! wplus#ai#provider#build_ollama_fim_payload(prefix, suffix, max_tokens, temperature) abort
    return json_encode({
        \ 'model': wplus#ai#provider#get_completion_model(),
        \ 'think': g:wplus_ai_ollama_think ? v:true : v:false,
        \ 'stream': v:false,
        \ 'keep_alive': g:wplus_ai_ollama_keep_alive,
        \ 'prompt': a:prefix,
        \ 'suffix': a:suffix,
        \ 'options': wplus#ai#provider#ollama_options(a:max_tokens, a:temperature),
        \ })
endfunction

function! wplus#ai#provider#build_suggest_payload(prefix, suffix) abort
    if wplus#ai#provider#use_ollama_fim()
        return wplus#ai#provider#build_ollama_fim_payload(a:prefix, a:suffix, g:wplus_ai_suggest_max_tokens, g:wplus_ai_suggest_temperature)
    endif
    let l:prov = wplus#ai#provider#get(g:wplus_ai_provider)
    if empty(l:prov) | return '' | endif

    " extract_symbols() must run first: it fills the cache with symbols, and
    " get_scope() then reuses that cached entry. The reverse order would cache
    " an empty symbol list and starve the suggestion prompt.
    let l:symbols = wplus#ai#context#extract_symbols()
    let l:scope = wplus#ai#context#get_scope()
    let l:max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)

    let l:language = empty(&filetype) ? 'plain text' : &filetype
    let l:prompt = "Complete the code at the cursor.\n"
        \ . "Language: " . l:language . "\n"
        \ . "Keep the insertion short (at most " . l:max_lines . " lines).\n\n"
    if !empty(l:scope)
        let l:prompt .= "You are currently inside: " . l:scope . "\n\n"
    endif
    if !empty(l:symbols)
        let l:prompt .= "Relevant symbols available in the workspace: " . join(l:symbols, ', ') . "\n\n"
    endif
    let l:prompt .= "Insert between these exact markers; do not output either marker:\n"
        \ . "<PREFIX>\n" . a:prefix . "\n<CURSOR>\n"
        \ . a:suffix . "\n</PREFIX>\n\n"
        \ . "Return ONLY the text to insert at <CURSOR>. Do not repeat the prefix, suffix, markers, explanations, or markdown.\n"

    let l:spec = {
        \ 'system': 'You are a precise code completion engine for ' . l:language . '. Return only a short insertion at the cursor. Never explain your answer.',
        \ 'user': l:prompt,
        \ 'max_tokens': g:wplus_ai_suggest_max_tokens,
        \ 'temperature': g:wplus_ai_suggest_temperature,
        \ 'purpose': 'suggest',
        \ }
    return call(l:prov.payload, [l:spec])
endfunction

function! wplus#ai#provider#build_commit_prompt(stat, diff) abort
    if !empty(get(g:, 'wplus_ai_commit_prompt', ''))
        let l:p = g:wplus_ai_commit_prompt
        let l:p = substitute(l:p, '{stat}', escape(a:stat, '&~'), 'g')
        let l:p = substitute(l:p, '{diff}', escape(a:diff, '&~'), 'g')
        return l:p
    endif

    let l:scale = s:commit_scale(a:stat)
    let l:prompt = "You are an expert software developer writing a Git commit message in Korean.\n"
        \ . "Based on the staged changes below, write a commit message following the Conventional Commits convention.\n\n"
        \ . "### Requirements:\n"
        \ . "1. First line: '<type>(<scope>): <summary>' (e.g. feat(ai): ..., fix(auth): ..., refactor(core): ...). Max 50 chars in Korean.\n"
        \ . "2. Do NOT output markdown code fences (no ```), no <thinking> tags, and no meta-commentary. Output ONLY the raw commit message.\n"

    if l:scale ==# 'large'
        let l:prompt .= "3. The changes are extensive. After the summary line, leave one blank line and write a body with short bullets that cover the main changes grouped by area or module. You may reference the main files or modules involved. Make sure the body reflects the full scope of the changes, not just the first file.\n"
    elseif l:scale ==# 'medium'
        let l:prompt .= "3. If the changes span multiple areas, leave one blank line and add a short body (2-4 bullets) covering the main changes.\n"
    else
        let l:prompt .= "3. Keep it concise: prefer a single-line summary; add a brief body only when context is needed.\n"
    endif

    let l:prompt .= "\n### Changed Files (Diff Stat):\n" . a:stat . "\n\n### Diff:\n" . a:diff
    return l:prompt
endfunction

" Estimate the scale of a change set from its `git diff --cached --stat` output
" so the prompt can ask for a single-line summary for small changes but a
" detailed body that reflects the full scope for large ones.
function! s:commit_scale(stat) abort
    let l:files = 0
    for l:line in split(a:stat, "\n")
        " File stat lines look like ' path | 10 +++++-----'; the summary line
        " ('N files changed, ...') has no '|' and is not counted.
        if l:line =~# '\v^\s*\S.*\|'
            let l:files += 1
        endif
    endfor
    let l:total = 0
    let l:m = matchlist(a:stat, '\v(\d+) insertions\?(\+)')
    if !empty(l:m) | let l:total += str2nr(l:m[1]) | endif
    let l:m = matchlist(a:stat, '\v(\d+) deletions\?(\-)')
    if !empty(l:m) | let l:total += str2nr(l:m[1]) | endif
    if l:files >= 5 || l:total >= 200
        return 'large'
    elseif l:files >= 2 || l:total >= 30
        return 'medium'
    endif
    return 'small'
endfunction

function! wplus#ai#provider#build_request_payload(prompt, ...) abort
    let l:prov = wplus#ai#provider#get(g:wplus_ai_provider)
    if empty(l:prov) | return '' | endif
    let l:max_tokens = a:0 >= 1 && a:1 > 0 ? a:1 : get(g:, 'wplus_ai_max_tokens', 2048)
    let l:temperature = a:0 >= 2 ? a:2 : get(g:, 'wplus_ai_temperature', 0.7)
    let l:purpose = a:0 >= 3 ? a:3 : 'command'
    let l:spec = {
        \ 'system': l:purpose ==# 'suggest' ? 'You are a precise code completion engine. Return only the requested insertion.' : 'You are a helpful code assistant. Provide concise, accurate responses.',
        \ 'user': a:prompt,
        \ 'max_tokens': l:max_tokens,
        \ 'temperature': l:temperature,
        \ 'purpose': l:purpose,
        \ }
    return call(l:prov.payload, [l:spec])
endfunction

function! s:resolve_model(spec) abort
    let l:model = get(a:spec, 'purpose', '') ==# 'suggest'
        \ ? wplus#ai#provider#get_completion_model()
        \ : g:wplus_ai_model
    if !empty(l:model)
        return l:model
    endif
    if g:wplus_ai_provider ==# 'claude'
        return 'claude-3-sonnet-20240229'
    elseif g:wplus_ai_provider ==# 'ollama'
        return 'codellama'
    endif
    return 'gpt-3.5-turbo'
endfunction

function! s:uses_max_completion_tokens(spec) abort
    if g:wplus_ai_provider ==# 'claude'
        return v:false
    endif
    let l:model = get(a:spec, 'purpose', '') ==# 'suggest'
        \ ? wplus#ai#provider#get_completion_model()
        \ : g:wplus_ai_model
    let l:model = tolower(l:model)
    return l:model =~# '^gpt-5' || l:model =~# '^o[134]'
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
    let l:model = s:resolve_model(a:spec)
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
    if s:uses_max_completion_tokens(a:spec)
        let l:body.max_completion_tokens = a:spec.max_tokens
    else
        let l:body.max_tokens = a:spec.max_tokens
    endif
    return json_encode(l:body)
endfunction

function! s:build_claude_payload(spec) abort
    let l:model = s:resolve_model(a:spec)
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
    let l:body = {
        \ 'model': s:resolve_model(a:spec),
        \ 'think': g:wplus_ai_ollama_think ? v:true : v:false,
        \ 'stream': v:false,
        \ 'keep_alive': g:wplus_ai_ollama_keep_alive,
        \ 'messages': l:msgs,
        \ 'options': wplus#ai#provider#ollama_options(a:spec.max_tokens, a:spec.temperature),
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

" Register default providers
call wplus#ai#provider#register('openai', {
    \ 'needs_key': 1,
    \ 'endpoint': {spec -> get(g:, 'wplus_ai_openai_endpoint', 'https://api.openai.com/v1/chat/completions')},
    \ 'headers': {key -> ['Content-Type: application/json', 'Authorization: Bearer ' . key]},
    \ 'payload': function('s:build_openai_payload'),
    \ 'extract': function('s:extract_openai'),
    \ 'error': function('s:error_openai'),
    \ })

call wplus#ai#provider#register('claude', {
    \ 'needs_key': 1,
    \ 'endpoint': {spec -> 'https://api.anthropic.com/v1/messages'},
    \ 'headers': {key -> ['Content-Type: application/json', 'x-api-key: ' . key, 'anthropic-version: 2023-06-01']},
    \ 'payload': function('s:build_claude_payload'),
    \ 'extract': function('s:extract_claude'),
    \ 'error': function('s:error_claude'),
    \ })

call wplus#ai#provider#register('azure', {
    \ 'needs_key': 1,
    \ 'endpoint': function('s:azure_endpoint'),
    \ 'headers': {key -> ['Content-Type: application/json', 'api-key: ' . key]},
    \ 'payload': function('s:build_openai_payload'),
    \ 'extract': function('s:extract_openai'),
    \ 'error': function('s:error_openai'),
    \ })

call wplus#ai#provider#register('ollama', {
    \ 'needs_key': 0,
    \ 'endpoint': function('s:ollama_endpoint'),
    \ 'headers': {key -> ['Content-Type: application/json', 'Authorization: Bearer ollama']},
    \ 'payload': function('s:build_ollama_payload_spec'),
    \ 'extract': function('s:extract_ollama'),
    \ 'error': function('s:error_ollama'),
    \ })
