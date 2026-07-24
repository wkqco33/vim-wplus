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
let g:wplus_ai_ollama_host = get(g:, 'wplus_ai_ollama_host', 'http://localhost:11434')
" Thinking 모델(reasoning)을 사용할지 여부. 기본 0(끔): 추론 모델이 content를
" 비우고 reasoning으로 응답을 보내거나 max_tokens를 추론에 소진하는 문제를 방지한다.
let g:wplus_ai_ollama_think = get(g:, 'wplus_ai_ollama_think', 0)
" 모델을 메모리에 유지하는 시간. native /api/chat 에서만 적용된다.
" 기본 '30m': 코드를 읽느라 잠깐 멈춰도 모델이 내려가지 않아 첫 응답 지연을
" 막는다. 무한 유지는 '-1', 즉시 해제는 '0'.
let g:wplus_ai_ollama_keep_alive = get(g:, 'wplus_ai_ollama_keep_alive', '30m')
" FIM(Fill-In-the-Middle): 코드 전용 모델(qwen2.5-coder 등)에서 prefix/suffix
" 사이를 정확히 채운다. 자동완성 품질이 크게 오르고 prefix 에코가 사라진다.
" 모델이 insert 를 지원해야 한다(미지원 시 chat 방식으로 자동 폴백).
let g:wplus_ai_ollama_fim = get(g:, 'wplus_ai_ollama_fim', 0)
" 샘플링 옵션 오버라이드. 사용자가 지정한 키가 기본값 위에 병합된다.
" 예: {'repeat_penalty': 1.1, 'top_p': 0.9, 'stop': ['\n\n']}
let g:wplus_ai_ollama_options = get(g:, 'wplus_ai_ollama_options', {})
" 자동완성 샘플링 온도. 코드 완성은 낮을수록 정확/일관적이다.
let g:wplus_ai_suggest_temperature = get(g:, 'wplus_ai_suggest_temperature', 0.2)

" Ghost Text auto-suggestion settings
let g:wplus_ai_suggest_enabled = get(g:, 'wplus_ai_suggest_enabled', 1)
let g:wplus_ai_suggest_delay = get(g:, 'wplus_ai_suggest_delay', 500)
let g:wplus_ai_suggest_context_lines = get(g:, 'wplus_ai_suggest_context_lines', 50)
let g:wplus_ai_suggest_suffix_lines = get(g:, 'wplus_ai_suggest_suffix_lines', 20)
let g:wplus_ai_suggest_max_tokens = get(g:, 'wplus_ai_suggest_max_tokens', 500)
let g:wplus_ai_suggest_max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
let g:wplus_ai_suggest_debug = get(g:, 'wplus_ai_suggest_debug', 0)

" Network timeouts (seconds). Commands wait longer; suggestions abort faster.
let g:wplus_ai_timeout = get(g:, 'wplus_ai_timeout', 30)
let g:wplus_ai_suggest_timeout = get(g:, 'wplus_ai_suggest_timeout', 10)

" Streaming responses: render suggestions incrementally as tokens arrive.
" Disable for providers/proxies that buffer SSE.
let g:wplus_ai_stream = get(g:, 'wplus_ai_stream', 1)
" Minimum accumulated chars before first incremental ghost-text render.
let g:wplus_ai_stream_min_chars = get(g:, 'wplus_ai_stream_min_chars', 20)

let s:command_requests = {} " request_id -> {job, bufnr, lnum, response_buffer}
let s:command_channels = {} " channel_key -> request_id
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


function! s:get_api_endpoint() abort
    if g:wplus_ai_provider ==# 'claude'
        return 'https://api.anthropic.com/v1/messages'
    elseif g:wplus_ai_provider ==# 'azure'
        if empty(g:wplus_ai_azure_resource) || empty(g:wplus_ai_azure_deployment)
            call wplus#util#error_msg('ai', 'Azure: resource and deployment must be configured')
            return ''
        endif
        return 'https://' . g:wplus_ai_azure_resource . '.openai.azure.com/openai/deployments/'
                    \ . g:wplus_ai_azure_deployment . '/chat/completions'
                    \ . '?api-version=' . g:wplus_ai_azure_api_version
    elseif g:wplus_ai_provider ==# 'ollama'
        " native API: think/keep_alive/options 를 제어할 수 있다.
        " (v1 호환 엔드포인트는 keep_alive 를 무시해 매번 모델을 재로딩한다)
        return g:wplus_ai_ollama_host . '/api/chat'
    else
        return 'https://api.openai.com/v1/chat/completions'
    endif
endfunction

function! s:get_request_headers() abort
    let l:headers = ['Content-Type: application/json']
    if g:wplus_ai_provider ==# 'ollama'
        " Ollama does not require an API key
        call add(l:headers, 'Authorization: Bearer ollama')
        return l:headers
    endif
    if empty(g:wplus_ai_api_key)
        call wplus#util#error_msg('ai', 'API key not configured')
        return []
    endif
    if g:wplus_ai_provider ==# 'claude'
        call add(l:headers, 'x-api-key: ' . g:wplus_ai_api_key)
        call add(l:headers, 'anthropic-version: 2023-06-01')
    elseif g:wplus_ai_provider ==# 'azure'
        call add(l:headers, 'api-key: ' . g:wplus_ai_api_key)
    else
        call add(l:headers, 'Authorization: Bearer ' . g:wplus_ai_api_key)
    endif
    return l:headers
endfunction

function! s:channel_key(channel) abort
    try
        let l:info = ch_info(a:channel)
        return string(get(l:info, 'id', a:channel))
    catch
        return string(a:channel)
    endtry
endfunction

function! s:build_curl_command(payload, endpoint, headers, ...) abort
    let l:timeout = a:0 >= 1 ? a:1 : g:wplus_ai_timeout
    let l:stream = a:0 >= 2 ? a:2 : 0
    " -N: disable output buffering so streaming chunks reach out_cb promptly.
    "     Without it curl block-buffers piped output and out_cb sees nothing
    "     until close_cb, breaking incremental ghost-text rendering.
    let l:cmd = ['curl', '-s', '-S', '--max-time', string(l:timeout),
                \ '-X', 'POST', '-d', a:payload]
    if l:stream
        call insert(l:cmd, '-N', 1)
    endif
    call add(l:cmd, a:endpoint)
    for l:header in a:headers
        call insert(l:cmd, l:header, 2)
        call insert(l:cmd, '-H', 2)
    endfor
    return l:cmd
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
function! s:clean_suggest_content(content) abort
    let l:txt = a:content
    " Remove completed <think>...</think> and <thought>...</thought> tags
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.\{-}</\%(think\|thought\)>', '', 'g')
    " Remove unclosed <think> or <thought> tags to the end
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.*$', '', 'g')
    " Remove markdown code blocks
    let l:txt = substitute(l:txt, '```.*\n', '', 'g')
    let l:txt = substitute(l:txt, '```', '', 'g')
    return trim(l:txt)
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

" 기본 옵션에 사용자 오버라이드(g:wplus_ai_ollama_options)를 병합한다.
function! s:ollama_options(max_tokens, temperature) abort
    let l:opts = {'temperature': a:temperature, 'num_predict': a:max_tokens}
    if type(g:wplus_ai_ollama_options) == v:t_dict
        call extend(l:opts, g:wplus_ai_ollama_options)
    endif
    return l:opts
endfunction

" native /api/chat 페이로드. stream:false 로 단일 JSON 응답을 받고,
" think 로 추론을 토글, keep_alive 로 모델을 메모리에 유지해 재로딩 지연을 막는다.
function! s:build_ollama_payload(messages, max_tokens, temperature, ...) abort
    let l:stream = a:0 >= 1 ? a:1 : 0
    return json_encode({
        \ 'model': g:wplus_ai_model,
        \ 'think': g:wplus_ai_ollama_think ? v:true : v:false,
        \ 'stream': l:stream ? v:true : v:false,
        \ 'keep_alive': g:wplus_ai_ollama_keep_alive,
        \ 'messages': a:messages,
        \ 'options': s:ollama_options(a:max_tokens, a:temperature),
        \ })
endfunction

" FIM(/api/generate) 페이로드. prefix=prompt, suffix=suffix 로 중간을 채운다.
function! s:build_ollama_fim_payload(prefix, suffix, max_tokens, temperature, ...) abort
    let l:stream = a:0 >= 1 ? a:1 : 0
    return json_encode({
        \ 'model': g:wplus_ai_model,
        \ 'think': g:wplus_ai_ollama_think ? v:true : v:false,
        \ 'stream': l:stream ? v:true : v:false,
        \ 'keep_alive': g:wplus_ai_ollama_keep_alive,
        \ 'prompt': a:prefix,
        \ 'suffix': a:suffix,
        \ 'options': s:ollama_options(a:max_tokens, a:temperature),
        \ })
endfunction

" FIM 사용 여부. provider 가 ollama 이고 사용자가 켰을 때만.
function! s:use_ollama_fim() abort
    return g:wplus_ai_provider ==# 'ollama' && g:wplus_ai_ollama_fim
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

function! s:build_request_payload(prompt) abort
    let l:system_msg = 'You are a helpful code assistant. Provide concise, accurate responses.'

    if g:wplus_ai_provider ==# 'ollama'
        return s:build_ollama_payload([
            \   {'role': 'system', 'content': l:system_msg},
            \   {'role': 'user', 'content': a:prompt}
            \ ], g:wplus_ai_max_tokens, g:wplus_ai_temperature)
    endif

    if g:wplus_ai_provider ==# 'claude'
        return json_encode({
            \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'claude-3-sonnet-20240229',
            \ 'max_tokens': g:wplus_ai_max_tokens,
            \ 'system': l:system_msg,
            \ 'messages': [{'role': 'user', 'content': a:prompt}],
            \ 'temperature': g:wplus_ai_temperature
            \ })
    endif

    let l:payload = {
        \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'gpt-3.5-turbo',
        \ 'temperature': g:wplus_ai_temperature,
        \ 'messages': [
        \   {'role': 'system', 'content': l:system_msg},
        \   {'role': 'user', 'content': a:prompt}
        \ ]
        \ }
    if s:uses_max_completion_tokens()
        let l:payload.max_completion_tokens = g:wplus_ai_max_tokens
    else
        let l:payload.max_tokens = g:wplus_ai_max_tokens
    endif
    return json_encode(l:payload)
endfunction

function! s:on_response(channel, msg) abort
    let l:key = s:channel_key(a:channel)
    if has_key(s:command_channels, l:key)
        let l:request_id = s:command_channels[l:key]
        if has_key(s:command_requests, l:request_id)
            let s:command_requests[l:request_id].response_buffer .= a:msg
        endif
    endif
endfunction

function! s:on_response_complete(channel) abort
    let l:key = s:channel_key(a:channel)
    if !has_key(s:command_channels, l:key)
        return
    endif
    let l:request_id = remove(s:command_channels, l:key)
    if !has_key(s:command_requests, l:request_id)
        return
    endif
    let l:request = remove(s:command_requests, l:request_id)
    
    let l:response = l:request.response_buffer
    let l:bufnr = l:request.bufnr
    let l:lnum = l:request.lnum
    
    if empty(l:response)
        call wplus#util#error_msg('ai', 'empty response from API')
        return
    endif
    
    try
        let l:json = json_decode(l:response)
    catch
        call wplus#util#error_msg('ai', 'failed to parse response')
        return
    endtry
    
    " Extract content based on provider
    let l:content = s:extract_response_content(l:json)
    if empty(l:content)
        let l:error_msg = s:extract_error_message(l:json)
        if !empty(l:error_msg)
            call wplus#util#error_msg('ai', l:error_msg)
        else
            call wplus#util#error_msg('ai', 'no content in response')
        endif
        return
    endif
    
    " Insert response at current position
    if bufloaded(l:bufnr)
        let l:lines = split(l:content, "\n")
        call append(l:lnum, l:lines)
        call wplus#util#info_msg('ai', 'response inserted')
    endif
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
    call s:send_request(l:bufnr, l:lnum, l:prompt)
endfunction

function! wplus#ai#complete(context_lines) abort
    " Generate code completion
    let l:bufnr = bufnr('%')
    let l:lnum = line('.')
    let l:col = col('.')
    
    let l:start = max([1, l:lnum - a:context_lines])
    let l:context = join(getline(l:start, l:lnum), "\n")
    
    let l:prompt = "Complete this code. Respond with only the completion, no explanation:\n\n" . l:context
    call s:send_request(l:bufnr, l:lnum, l:prompt)
endfunction

function! wplus#ai#refactor() abort
    " Suggest refactoring
    let l:bufnr = bufnr('%')
    let l:lnum = line('.')
    
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end, l:col_end] = getpos("'>")[1:2]
    let l:code = join(getline(l:line_start, l:line_end), "\n")
    
    let l:prompt = "Refactor this code to be more efficient and readable:\n\n" . l:code
    call s:send_request(l:bufnr, l:lnum, l:prompt)
endfunction

function! s:send_request(bufnr, lnum, prompt) abort
    if g:wplus_ai_provider !=# 'ollama' && empty(g:wplus_ai_api_key)
        call wplus#util#error_msg('ai', 'API key not configured (g:wplus_ai_api_key)')
        return
    endif

    if empty(g:wplus_ai_model)
        call wplus#util#error_msg('ai', 'model not configured (g:wplus_ai_model)')
        return
    endif
    
    let l:endpoint = s:get_api_endpoint()
    let l:headers = s:get_request_headers()
    if empty(l:headers) | return | endif
    
    let l:payload = s:build_request_payload(a:prompt)
    let l:request_id = reltimestr(reltime())
    let l:cmd = s:build_curl_command(l:payload, l:endpoint, l:headers, g:wplus_ai_timeout)
    
    let l:job = job_start(l:cmd, {
        \ 'out_cb': function('s:on_response'),
        \ 'close_cb': function('s:on_response_complete'),
        \ 'err_cb': function('s:on_error')
        \ })
    if type(l:job) != v:t_job
        call wplus#util#error_msg('ai', 'failed to start request')
        return
    endif
    
    let s:command_requests[l:request_id] = {
        \ 'job': l:job,
        \ 'bufnr': a:bufnr,
        \ 'lnum': a:lnum,
        \ 'response_buffer': ''
        \ }
    let s:command_channels[s:channel_key(job_getchannel(l:job))] = l:request_id
    call wplus#util#info_msg('ai', 'sending request...')
endfunction

function! s:on_error(channel, msg) abort
    let l:key = s:channel_key(a:channel)
    if has_key(s:command_channels, l:key)
        let l:request_id = remove(s:command_channels, l:key)
        if has_key(s:command_requests, l:request_id)
            call remove(s:command_requests, l:request_id)
        endif
    endif
    call wplus#util#error_msg('ai', 'request error: ' . a:msg)
endfunction

function! wplus#ai#setup() abort
    augroup WplusAI
        autocmd!
        autocmd VimLeavePre * for req in values(s:command_requests) | silent! call job_stop(req.job) | endfor
        autocmd VimLeavePre * if !empty(s:suggest_request) | silent! call job_stop(s:suggest_request.job) | endif
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
    command! WaiToggleSuggest    call wplus#ai#toggle_suggest()
    command! WaiAcceptSuggest    call wplus#ai#accept_suggestion_insert()
    command! WaiDismissSuggest   call wplus#ai#dismiss_suggestion()
    command! WaiAcceptWord       call wplus#ai#accept_suggestion_insert_word()

    " Mappings
    nnoremap <silent> <Plug>WaiComment   :WaiComment<CR>
    nnoremap <silent> <Plug>WaiComplete  :WaiComplete<CR>
    xnoremap <silent> <Plug>WaiRefactor  :WaiRefactor<CR>
    nnoremap <silent> <Plug>WaiToggleSuggest :WaiToggleSuggest<CR>
    inoremap <silent> <Plug>WaiDismissSuggest <C-r>=wplus#ai#dismiss_suggestion()<CR>
    inoremap <silent> <expr> <Plug>WaiAcceptWord wplus#ai#accept_word_suggestion()
    
    " Ghost Text auto-suggest: register property type if missing.
    " show_suggestion() also self-heals this, but registering here avoids the
    " first-render E971 entirely.
    if has('textprop') && empty(prop_type_get('WplusAISuggest'))
        if !hlexists('WplusAISuggest')
            if hlexists('Comment')
                highlight default link WplusAISuggest Comment
            else
                highlight default WplusAISuggest ctermfg=244 guifg=#7c6f64
            endif
        endif
        call prop_type_add('WplusAISuggest', {'highlight': 'WplusAISuggest'})
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
        let s:suggest_request = {}
    endif

    if l:bufnr > 0 && bufloaded(l:bufnr)
        call prop_remove({'type': 'WplusAISuggest', 'all': 1, 'bufnr': l:bufnr})
    endif
endfunction

" Accept current suggestion. Returns a string suitable for <expr> mappings.
" Multi-line suggestions are joined with \<CR>" so Vim inserts every line.
function! wplus#ai#accept_suggestion() abort
    if empty(s:suggest_content)
        " No suggestion, insert normal tab
        return "\<Tab>"
    endif

    let l:content = s:suggest_content
    call s:dismiss_suggestion()
    call s:suggest_debug('suggestion accepted')
    if mode() =~# 'i'
        call feedkeys(l:content, 'n')
        return ''
    endif
    return substitute(l:content, '\n', "\<CR>", 'g')
endfunction

" Command variant: insert the suggestion at cursor without returning a string.
function! wplus#ai#accept_suggestion_insert() abort
    if empty(s:suggest_content)
        return
    endif
    let l:content = s:suggest_content
    call s:dismiss_suggestion()
    let l:lines = split(l:content, "\n", 1)
    if mode() =~# 'i'
        call feedkeys(join(l:lines, "\<CR>"), 'n')
    else
        " Best-effort in normal mode: append after cursor line
        call append(line('.'), l:lines)
    endif
    call s:suggest_debug('suggestion accepted (insert)')
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
    let l:word = l:match[1]
    let l:rest = l:match[3]
    if empty(l:rest)
        call s:dismiss_suggestion()
    else
        " Update ghost text to the remaining suggestion.
        let s:suggest_content = l:rest
        call s:show_suggestion()
    endif
    call s:suggest_debug('accepted word: ' . l:word)
    if mode() =~# 'i'
        call feedkeys(l:word, 'n')
        return ''
    endif
    return substitute(l:word, '\n', "\<CR>", 'g')
endfunction

" Command variant of accept-word: inserts at cursor via feedkeys.
function! wplus#ai#accept_suggestion_insert_word() abort
    if empty(s:suggest_content)
        return
    endif
    let l:word = wplus#ai#accept_word_suggestion()
    if !empty(l:word) && mode() =~# 'i'
        call feedkeys(l:word, 'n')
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

" 작은 모델 정확도를 위해 언어/스코프/주변 심볼을 프롬프트 머리에 붙인다.
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
function! s:build_suggest_payload(prefix, suffix, ...) abort
    let l:stream = a:0 >= 1 ? a:1 : 0
    let l:max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
    let l:system_msg = 'You are a code completion assistant. Complete the code based on context. Return only the completion without explanation or code blocks. Keep your suggestion short (maximum ' . l:max_lines . ' lines).'
    let l:prompt = s:suggest_context_hint() . "Complete this code:\n\nPrefix:\n" . a:prefix . "\n\nSuffix:\n" . a:suffix

    if g:wplus_ai_provider ==# 'ollama'
        return s:build_ollama_payload([
            \   {'role': 'system', 'content': l:system_msg},
            \   {'role': 'user', 'content': l:prompt}
            \ ], g:wplus_ai_suggest_max_tokens, g:wplus_ai_suggest_temperature, l:stream)
    endif

    if g:wplus_ai_provider ==# 'claude'
        return json_encode({
            \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'claude-3-sonnet-20240229',
            \ 'max_tokens': 500,
            \ 'system': l:system_msg,
            \ 'messages': [{'role': 'user', 'content': l:prompt}],
            \ 'temperature': 0.5,
            \ 'stream': l:stream ? v:true : v:false,
            \ })
    endif

    let l:payload = {
        \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'gpt-3.5-turbo',
        \ 'temperature': 0.5,
        \ 'stream': l:stream ? v:true : v:false,
        \ 'messages': [
        \   {'role': 'system', 'content': l:system_msg},
        \   {'role': 'user', 'content': l:prompt}
        \ ]
        \ }
    if s:uses_max_completion_tokens()
        let l:payload.max_completion_tokens = g:wplus_ai_suggest_max_tokens
    else
        let l:payload.max_tokens = g:wplus_ai_suggest_max_tokens
    endif
    return json_encode(l:payload)
endfunction

" ── Streaming delta parsers ───────────────────────────────────────────────────
" Extract text delta from one streamed chunk. Returns '' when no delta.
"   - Ollama ndstream: {"message":{"content":"..."},...} or {"response":"..."} (FIM)
"   - OpenAI/Azure SSE: data: {"choices":[{"delta":{"content":"..."}}]}
"   - Claude SSE: data: {"type":"content_block_delta","delta":{"text":"..."}}
function! s:parse_stream_delta(line, fim) abort
    let l:raw = a:line
    " SSE: strip leading "data:" + optional spaces; stop on [DONE].
    " Lines without data: (event:, id:, comments, blanks) → empty.
    if g:wplus_ai_provider !=# 'ollama'
        if l:raw =~# '^data:'
            let l:raw = substitute(l:raw, '^data:\s*', '', '')
            if l:raw =~# '\[DONE\]'
                return ''
            endif
        else
            return ''
        endif
    endif
    let l:raw = trim(l:raw)
    if empty(l:raw) | return '' | endif
    try
        let l:json = json_decode(l:raw)
    catch
        return ''
    endtry
    if g:wplus_ai_provider ==# 'ollama'
        if a:fim
            return get(l:json, 'response', '')
        endif
        if has_key(l:json, 'message') && type(l:json.message) == v:t_dict
            return get(l:json.message, 'content', '')
        endif
        return ''
    endif
    if g:wplus_ai_provider ==# 'claude'
        if get(l:json, 'type', '') ==# 'content_block_delta'
                    \ && has_key(l:json, 'delta')
                    \ && get(l:json.delta, 'type', '') ==# 'text_delta'
            return get(l:json.delta, 'text', '')
        endif
        return ''
    endif
    " OpenAI/Azure
    if has_key(l:json, 'choices') && len(l:json.choices) > 0
        let l:delta = get(l:json.choices[0], 'delta', {})
        return get(l:delta, 'content', '')
    endif
    return ''
endfunction

" Render incremental ghost text from accumulated content.
function! s:render_stream_increment(request) abort
    let l:content = get(a:request, 'stream_content', '')
    if empty(l:content) | return | endif
    let l:clean = s:clean_suggest_content(l:content)
    if len(l:clean) < g:wplus_ai_stream_min_chars | return | endif
    if line('.') != a:request.line || col('.') != a:request.col || bufnr('%') != a:request.bufnr
        return
    endif

    let l:lines = split(l:clean, "\n", 1)
    let l:max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
    let l:should_stop = 0

    if len(l:lines) > l:max_lines
        let l:clean = join(l:lines[:l:max_lines - 1], "\n")
        let l:should_stop = 1
    endif

    let s:suggest_content = l:clean
    let s:suggest_line = a:request.line
    let s:suggest_col = a:request.col
    let s:suggest_bufnr = a:request.bufnr
    call s:show_suggestion()

    if l:should_stop
        call s:suggest_debug('reached max lines, stopping job')
        if has_key(a:request, 'job') && type(a:request.job) == v:t_job
            silent! call job_stop(a:request.job)
        endif
        let s:suggest_request = {}
    endif
endfunction

" Response handler for suggestions. request_id is bound via partial and thus
" comes first in the argument list. Streaming: parse each chunk for deltas and
" render incrementally. Non-streaming: buffer raw response for final decode.
function! s:on_suggest_response(request_id, channel, msg) abort
    if empty(s:suggest_request) || get(s:suggest_request, 'request_id', -1) != a:request_id
        return
    endif
    if get(s:suggest_request, 'stream', 0)
        let s:suggest_request.stream_buffer .= substitute(a:msg, "\r\n\=", "\n", 'g')
        if s:suggest_request.stream_buffer =~# "\n"
            let l:parts = split(s:suggest_request.stream_buffer, "\n", 1)
            if s:suggest_request.stream_buffer =~# "\n$"
                let s:suggest_request.stream_buffer = ''
            else
                let s:suggest_request.stream_buffer = remove(l:parts, -1)
            endif
            for l:line in l:parts
                if empty(l:line) | continue | endif
                let l:delta = s:parse_stream_delta(l:line, get(s:suggest_request, 'fim', 0))
                if !empty(l:delta)
                    let s:suggest_request.stream_content .= l:delta
                    call s:render_stream_increment(s:suggest_request)
                endif
            endfor
        endif
    else
        let s:suggest_request.response_buffer .= a:msg
    endif
endfunction

" Complete response handler for suggestions. request_id is bound via partial.
function! s:on_suggest_response_complete(request_id, channel) abort
    if empty(s:suggest_request) || get(s:suggest_request, 'request_id', -1) != a:request_id
        return
    endif
    let l:request = s:suggest_request
    let s:suggest_request = {}

    " ── Streaming path: finalize accumulated content ──
    if get(l:request, 'stream', 0)
        " Flush any remaining buffered partial line
        if !empty(l:request.stream_buffer)
            let l:delta = s:parse_stream_delta(l:request.stream_buffer, get(l:request, 'fim', 0))
            if !empty(l:delta)
                let l:request.stream_content .= l:delta
            endif
            let l:request.stream_buffer = ''
        endif
        let l:content = l:request.stream_content
        if empty(l:content)
            call s:suggest_debug('empty streaming suggestion response')
            return
        endif
        let l:content = s:clean_suggest_content(l:content)

        let l:max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
        let l:lines = split(l:content, "\n", 1)
        if len(l:lines) > l:max_lines
            let l:content = join(l:lines[:l:max_lines - 1], "\n")
        endif
        if line('.') == l:request.line && col('.') == l:request.col && bufnr('%') == l:request.bufnr
            let s:suggest_content = l:content
            let s:suggest_line = l:request.line
            let s:suggest_col = l:request.col
            let s:suggest_bufnr = l:request.bufnr
            call s:show_suggestion()
        else
            call s:suggest_debug('dropped stale streaming suggestion')
        endif
        return
    endif

    " ── Non-streaming path ──
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
    let l:stream = g:wplus_ai_stream ? 1 : 0
    if l:is_fim
        let l:endpoint = g:wplus_ai_ollama_host . '/api/generate'
        let l:payload = s:build_ollama_fim_payload(a:prefix, a:suffix,
            \ g:wplus_ai_suggest_max_tokens, g:wplus_ai_suggest_temperature, l:stream)
    else
        let l:endpoint = s:get_api_endpoint()
        if empty(l:endpoint)
            call s:suggest_debug('empty API endpoint')
            return
        endif
        let l:payload = s:build_suggest_payload(a:prefix, a:suffix, l:stream)
    endif
    let l:headers = s:get_request_headers()
    if empty(l:headers) | return | endif

    let l:cmd = s:build_curl_command(l:payload, l:endpoint, l:headers, g:wplus_ai_suggest_timeout, l:stream)

    if !empty(s:suggest_request)
        silent! call job_stop(s:suggest_request.job)
        let s:suggest_request = {}
    endif

    let s:suggest_request_id += 1
    let l:rid = s:suggest_request_id
    let l:job = job_start(l:cmd, {
        \ 'out_mode': 'raw',
        \ 'out_cb': function('s:on_suggest_response', [l:rid]),
        \ 'close_cb': function('s:on_suggest_response_complete', [l:rid]),
        \ })
    if type(l:job) != v:t_job
        call wplus#util#error_msg('ai', 'failed to start suggestion request')
        let s:suggest_request = {}
        return
    endif

    let s:suggest_request = {
        \ 'request_id': l:rid,
        \ 'job': l:job,
        \ 'channel_key': s:channel_key(job_getchannel(l:job)),
        \ 'bufnr': bufnr('%'),
        \ 'lnum': line('.'),
        \ 'line': s:suggest_line,
        \ 'col': s:suggest_col,
        \ 'fim': l:is_fim,
        \ 'stream': l:stream,
        \ 'stream_content': '',
        \ 'stream_buffer': '',
        \ 'response_buffer': ''
        \ }
    call s:suggest_debug('sent suggestion request' . (l:is_fim ? ' (FIM)' : '') . (l:stream ? ' (stream)' : ''))
endfunction
