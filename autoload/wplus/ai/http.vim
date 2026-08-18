" wplus/ai/http.vim — Async curl execution and transport management

if exists('g:autoloaded_wplus_ai_http') | finish | endif
let g:autoloaded_wplus_ai_http = 1

let s:command_requests = {}
let s:suggest_job = v:null
let s:suggest_request = {}
let s:suggest_curl_config = ''

function! s:channel_key(channel) abort
    return wplus#util#channel_key(a:channel)
endfunction

" Store headers in a private curl config file instead of argv. This prevents
" API keys from appearing in /proc/<pid>/cmdline and process listings.
function! wplus#ai#http#write_curl_config(headers) abort
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

function! wplus#ai#http#build_curl_command(endpoint, headers, ...) abort
    let l:timeout = a:0 >= 1 ? a:1 : g:wplus_ai_timeout
    let l:config = wplus#ai#http#write_curl_config(a:headers)
    if empty(l:config)
        return {'cmd': [], 'config': ''}
    endif
    return {'cmd': ['curl', '-s', '-S', '--max-time', string(l:timeout),
                \ '--config', l:config, '-X', 'POST', '-d', '@-', a:endpoint],
                \ 'config': l:config}
endfunction

function! wplus#ai#http#cleanup_curl_config(file) abort
    if !empty(a:file)
        silent! call delete(a:file)
    endif
endfunction

" Send payload over stdin in chunks safely and close channel (prevents E631 pipe buffer overflow)
function! wplus#ai#http#write_payload_stdin(job, payload) abort
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

function! wplus#ai#http#send_request(prompt, OnContent, ...) abort
    if g:wplus_ai_provider !=# 'ollama' && empty(g:wplus_ai_api_key)
        call wplus#util#error_msg('ai', 'API key not configured (g:wplus_ai_api_key)')
        return
    endif

    if wplus#ai#security#reject_sensitive(a:prompt)
        return
    endif

    if empty(g:wplus_ai_model)
        call wplus#util#error_msg('ai', 'model not configured (g:wplus_ai_model)')
        return
    endif

    let l:endpoint = wplus#ai#provider#get_endpoint()
    let l:headers = wplus#ai#provider#get_headers()
    if empty(l:headers) | return | endif

    let l:max_tokens = a:0 >= 1 && a:1 > 0 ? a:1 : get(g:, 'wplus_ai_max_tokens', 2048)
    let l:temperature = a:0 >= 2 ? a:2 : get(g:, 'wplus_ai_temperature', 0.7)
    let l:payload = wplus#ai#provider#build_request_payload(a:prompt, l:max_tokens, l:temperature)
    if strlen(l:payload) > g:wplus_ai_request_max_bytes
        call wplus#util#error_msg('ai', 'request exceeds g:wplus_ai_request_max_bytes')
        return
    endif
    let l:request_id = reltimestr(reltime())
    let l:transport = wplus#ai#http#build_curl_command(l:endpoint, l:headers, g:wplus_ai_timeout)
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
        call wplus#ai#http#cleanup_curl_config(l:transport.config)
        call wplus#util#error_msg('ai', 'failed to start request')
        return
    endif

    let s:command_requests[l:request_id].job = l:job
    call wplus#ai#http#write_payload_stdin(l:job, l:payload)
    call wplus#util#info_msg('ai', 'sending request...')
endfunction

function! s:on_response(request_id, channel, msg) abort
    if !has_key(s:command_requests, a:request_id)
        return
    endif
    let l:req = s:command_requests[a:request_id]
    let l:req.response_buffer .= a:msg . "\n"
    if strlen(l:req.response_buffer) > g:wplus_ai_response_max_bytes
        call wplus#util#error_msg('ai', 'response exceeded g:wplus_ai_response_max_bytes')
        if type(l:req.job) == v:t_job
            silent! call job_stop(l:req.job)
        endif
        call wplus#ai#http#cleanup_curl_config(l:req.curl_config)
        call remove(s:command_requests, a:request_id)
    endif
endfunction

function! s:on_error(request_id, channel, msg) abort
    if has_key(s:command_requests, a:request_id)
        let s:command_requests[a:request_id].error_buffer .= a:msg . "\n"
    endif
endfunction

function! s:on_response_complete(request_id, channel) abort
    if !has_key(s:command_requests, a:request_id)
        return
    endif
    let l:req = remove(s:command_requests, a:request_id)
    call wplus#ai#http#cleanup_curl_config(l:req.curl_config)

    if !empty(l:req.error_buffer) && empty(l:req.response_buffer)
        call wplus#util#error_msg('ai', 'request error: ' . trim(l:req.error_buffer))
        return
    endif

    try
        let l:json = json_decode(l:req.response_buffer)
    catch
        call wplus#util#error_msg('ai', 'failed to parse JSON response: ' . v:exception)
        return
    endtry

    let l:content = wplus#ai#provider#extract_content(l:json)
    if empty(l:content)
        let l:err = wplus#ai#provider#extract_error(l:json)
        if !empty(l:err)
            call wplus#util#error_msg('ai', 'API Error: ' . l:err)
        else
            call wplus#util#warn_msg('ai', 'No content returned from AI')
        endif
        return
    endif

    let l:cleaned = wplus#ai#security#sanitize_text(l:content)
    if type(l:req.on_content) == v:t_func
        call call(l:req.on_content, [l:cleaned])
    endif
endfunction

function! wplus#ai#http#send_suggest_request(prefix, suffix, prompt, OnComplete) abort
    if g:wplus_ai_provider !=# 'ollama' && empty(g:wplus_ai_api_key)
        return
    endif
    if empty(g:wplus_ai_model)
        return
    endif

    let l:fim = wplus#ai#provider#use_ollama_fim()
    if l:fim
        if wplus#ai#security#is_sensitive(a:prefix . "\n" . a:suffix)
            return
        endif
        let l:endpoint = g:wplus_ai_ollama_host . '/api/generate'
        let l:headers = ['Content-Type: application/json', 'Authorization: Bearer ollama']
        let l:payload = wplus#ai#provider#build_ollama_fim_payload(a:prefix, a:suffix, g:wplus_ai_suggest_max_tokens, g:wplus_ai_suggest_temperature)
    else
        if wplus#ai#security#is_sensitive(a:prompt)
            return
        endif
        let l:endpoint = wplus#ai#provider#get_endpoint({'purpose': 'suggest'})
        let l:headers = wplus#ai#provider#get_headers()
        if empty(l:headers) | return | endif
        let l:payload = wplus#ai#provider#build_suggest_payload(a:prefix, a:suffix)
    endif

    if empty(l:payload) || strlen(l:payload) > g:wplus_ai_request_max_bytes
        return
    endif

    if type(s:suggest_job) == v:t_job
        silent! call job_stop(s:suggest_job)
        let s:suggest_job = v:null
    endif
    call wplus#ai#http#cleanup_curl_config(s:suggest_curl_config)

    let l:request_id = reltimestr(reltime())
    let l:transport = wplus#ai#http#build_curl_command(l:endpoint, l:headers, g:wplus_ai_suggest_timeout)
    if empty(l:transport.cmd)
        return
    endif
    let s:suggest_curl_config = l:transport.config

    let s:suggest_request = {
        \ 'id': l:request_id,
        \ 'line': line('.'),
        \ 'col': col('.'),
        \ 'bufnr': bufnr('%'),
        \ 'response_buffer': '',
        \ 'error_buffer': '',
        \ 'fim': l:fim,
        \ 'on_complete': a:OnComplete,
        \ }

    let l:job = job_start(l:transport.cmd, {
        \ 'in_mode': 'raw',
        \ 'out_cb': function('s:on_suggest_response', [l:request_id]),
        \ 'close_cb': function('s:on_suggest_response_complete', [l:request_id]),
        \ 'err_cb': function('s:on_suggest_error', [l:request_id])
        \ })
    if type(l:job) == v:t_job
        let s:suggest_job = l:job
        call wplus#ai#http#write_payload_stdin(l:job, l:payload)
    else
        let s:suggest_request = {}
        call wplus#ai#http#cleanup_curl_config(s:suggest_curl_config)
    endif
endfunction

function! s:on_suggest_response(request_id, channel, msg) abort
    if empty(s:suggest_request) || s:suggest_request.id !=# a:request_id
        return
    endif
    let s:suggest_request.response_buffer .= a:msg . "\n"
    if strlen(s:suggest_request.response_buffer) > g:wplus_ai_response_max_bytes
        if type(s:suggest_job) == v:t_job
            silent! call job_stop(s:suggest_job)
            let s:suggest_job = v:null
        endif
        let s:suggest_request = {}
        call wplus#ai#http#cleanup_curl_config(s:suggest_curl_config)
    endif
endfunction

function! s:on_suggest_error(request_id, channel, msg) abort
    if !empty(s:suggest_request) && s:suggest_request.id ==# a:request_id
        let s:suggest_request.error_buffer .= a:msg . "\n"
    endif
endfunction

function! s:on_suggest_response_complete(request_id, channel) abort
    if empty(s:suggest_request) || s:suggest_request.id !=# a:request_id
        return
    endif
    let l:request = copy(s:suggest_request)
    let s:suggest_request = {}
    let s:suggest_job = v:null
    call wplus#ai#http#cleanup_curl_config(s:suggest_curl_config)

    if !empty(l:request.error_buffer) && empty(l:request.response_buffer)
        return
    endif

    try
        let l:json = json_decode(l:request.response_buffer)
    catch
        return
    endtry

    if type(l:request.on_complete) == v:t_func
        call call(l:request.on_complete, [l:request, l:json])
    endif
endfunction

function! wplus#ai#http#cancel_all() abort
    for [l:req_id, l:req] in items(s:command_requests)
        if type(l:req.job) == v:t_job
            silent! call job_stop(l:req.job)
        endif
        call wplus#ai#http#cleanup_curl_config(l:req.curl_config)
    endfor
    let s:command_requests = {}

    if type(s:suggest_job) == v:t_job
        silent! call job_stop(s:suggest_job)
        let s:suggest_job = v:null
    endif
    let s:suggest_request = {}
    call wplus#ai#http#cleanup_curl_config(s:suggest_curl_config)
endfunction
