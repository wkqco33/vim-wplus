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

" Ghost Text auto-suggestion settings
let g:wplus_ai_suggest_enabled = get(g:, 'wplus_ai_suggest_enabled', 1)
let g:wplus_ai_suggest_delay = get(g:, 'wplus_ai_suggest_delay', 500)
let g:wplus_ai_suggest_context_lines = get(g:, 'wplus_ai_suggest_context_lines', 50)
let g:wplus_ai_suggest_suffix_lines = get(g:, 'wplus_ai_suggest_suffix_lines', 20)
let g:wplus_ai_suggest_max_tokens = get(g:, 'wplus_ai_suggest_max_tokens', 500)
let g:wplus_ai_suggest_debug = get(g:, 'wplus_ai_suggest_debug', 0)

let s:command_requests = {} " request_id -> {job, bufnr, lnum, response_buffer}
let s:command_channels = {} " channel_key -> request_id
let s:suggest_request = {} " {job, channel_key, bufnr, lnum, line, col, response_buffer}

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

function! s:build_curl_command(payload, endpoint, headers) abort
    let l:cmd = ['curl', '-s', '-X', 'POST', '-d', a:payload, a:endpoint]
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

" native /api/chat 페이로드. stream:false 로 단일 JSON 응답을 받고,
" think 로 추론을 토글, keep_alive 로 모델을 메모리에 유지해 재로딩 지연을 막는다.
function! s:build_ollama_payload(messages, max_tokens, temperature) abort
    return json_encode({
        \ 'model': g:wplus_ai_model,
        \ 'think': g:wplus_ai_ollama_think ? v:true : v:false,
        \ 'stream': v:false,
        \ 'keep_alive': g:wplus_ai_ollama_keep_alive,
        \ 'messages': a:messages,
        \ 'options': {
        \   'temperature': a:temperature,
        \   'num_predict': a:max_tokens,
        \ }
        \ })
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
    let l:cmd = s:build_curl_command(l:payload, l:endpoint, l:headers)
    
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
    call wplus#util#error_msg('ai', 'request error: ' . a:msg)
endfunction

function! wplus#ai#setup() abort
    augroup WplusAI
        autocmd!
        autocmd VimLeavePre * for req in values(s:command_requests) | silent! call job_stop(req.job) | endfor
        autocmd VimLeavePre * if !empty(s:suggest_request) | silent! call job_stop(s:suggest_request.job) | endif
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
    command! WaiAcceptSuggest    call wplus#ai#accept_suggestion()
    
    " Mappings
    nnoremap <silent> <Plug>WaiComment   :WaiComment<CR>
    nnoremap <silent> <Plug>WaiComplete  :WaiComplete<CR>
    xnoremap <silent> <Plug>WaiRefactor  :WaiRefactor<CR>
    nnoremap <silent> <Plug>WaiToggleSuggest :WaiToggleSuggest<CR>
    
    " Ghost Text auto-suggest
    if has('textprop')
        silent! call prop_type_add('WplusAISuggest', {'highlight': 'Comment'})
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
    call prop_remove({'type': 'WplusAISuggest', 'all': 1, 'bufnr': l:bufnr})

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

    if l:bufnr > 0 && bufloaded(l:bufnr)
        call prop_remove({'type': 'WplusAISuggest', 'all': 1, 'bufnr': l:bufnr})
    endif
endfunction

" Accept current suggestion
function! wplus#ai#accept_suggestion() abort
    if empty(s:suggest_content)
        " No suggestion, insert normal tab
        return "\<Tab>"
    endif

    let l:content = s:suggest_content
    call s:dismiss_suggestion()
    call wplus#util#info_msg('ai', 'suggestion accepted')
    return l:content
endfunction

function! wplus#ai#has_suggestion() abort
    return !empty(s:suggest_content)
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
    let l:prompt = "Complete the following code. Return only the completion without explanation or markdown:\n\n"
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

" Build suggestion prompt for all providers
function! s:build_suggest_payload(prefix, suffix) abort
    let l:system_msg = 'You are a code completion assistant. Complete the code based on context. Return only the completion without explanation or code blocks.'
    let l:prompt = "Complete this code:\n\nPrefix:\n" . a:prefix . "\n\nSuffix:\n" . a:suffix

    if g:wplus_ai_provider ==# 'ollama'
        return s:build_ollama_payload([
            \   {'role': 'system', 'content': l:system_msg},
            \   {'role': 'user', 'content': l:prompt}
            \ ], g:wplus_ai_suggest_max_tokens, 0.5)
    endif

    if g:wplus_ai_provider ==# 'claude'
        return json_encode({
            \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'claude-3-sonnet-20240229',
            \ 'max_tokens': 500,
            \ 'system': l:system_msg,
            \ 'messages': [{'role': 'user', 'content': l:prompt}],
            \ 'temperature': 0.5
            \ })
    endif

    let l:payload = {
        \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'gpt-3.5-turbo',
        \ 'temperature': 0.5,
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

" Response handler for suggestions
function! s:on_suggest_response(channel, msg) abort
    let l:key = s:channel_key(a:channel)
    if !empty(s:suggest_request) && get(s:suggest_request, 'channel_key', '') ==# l:key
        let s:suggest_request.response_buffer .= a:msg
    endif
endfunction

" Complete response handler for suggestions
function! s:on_suggest_response_complete(channel) abort
    let l:key = s:channel_key(a:channel)
    if empty(s:suggest_request) || get(s:suggest_request, 'channel_key', '') !=# l:key
        return
    endif
    let l:request = s:suggest_request
    let s:suggest_request = {}
    
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
    
    let l:content = s:extract_response_content(l:json)
    if empty(l:content)
        let l:error_msg = s:extract_error_message(l:json)
        if !empty(l:error_msg)
            call s:suggest_debug('api error: ' . l:error_msg)
            call s:report_suggest_error(l:error_msg)
        else
            call s:suggest_debug('no suggestion content in response')
        endif
        return
    endif
    
    " Clean up response (remove markdown code blocks if present)
    let l:content = substitute(l:content, '```.*\n', '', 'g')
    let l:content = substitute(l:content, '```', '', 'g')
    let l:content = trim(l:content)
    
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

" Send suggestion request to AI
function! s:send_suggest_request(prefix, suffix, prompt) abort
    if (g:wplus_ai_provider !=# 'ollama' && empty(g:wplus_ai_api_key)) || empty(g:wplus_ai_model)
        call s:suggest_debug('missing API key or model')
        return
    endif
    
    let l:endpoint = s:get_api_endpoint()
    if empty(l:endpoint)
        call s:suggest_debug('empty API endpoint')
        return
    endif
    let l:headers = s:get_request_headers()
    if empty(l:headers) | return | endif
    
    let l:payload = s:build_suggest_payload(a:prefix, a:suffix)
    let l:cmd = s:build_curl_command(l:payload, l:endpoint, l:headers)

    if !empty(s:suggest_request)
        silent! call job_stop(s:suggest_request.job)
        let s:suggest_request = {}
    endif
    
    let l:job = job_start(l:cmd, {
        \ 'out_cb': function('s:on_suggest_response'),
        \ 'close_cb': function('s:on_suggest_response_complete'),
        \ })
    if type(l:job) != v:t_job
        call wplus#util#error_msg('ai', 'failed to start suggestion request')
        return
    endif

    let s:suggest_request = {
        \ 'job': l:job,
        \ 'channel_key': s:channel_key(job_getchannel(l:job)),
        \ 'bufnr': bufnr('%'),
        \ 'lnum': line('.'),
        \ 'line': s:suggest_line,
        \ 'col': s:suggest_col,
        \ 'response_buffer': ''
        \ }
    call s:suggest_debug('sent suggestion request')
endfunction
