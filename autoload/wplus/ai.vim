" wplus/ai.vim — AI assistant with OpenAI/Claude/Azure OpenAI integration

if exists('g:autoloaded_wplus_ai') | finish | endif
let g:autoloaded_wplus_ai = 1

let g:wplus_ai_provider = get(g:, 'wplus_ai_provider', 'openai') " 'openai', 'claude', or 'azure'
let g:wplus_ai_model = get(g:, 'wplus_ai_model', '')
let g:wplus_ai_api_key = get(g:, 'wplus_ai_api_key', '')
let g:wplus_ai_temperature = get(g:, 'wplus_ai_temperature', 0.7)
let g:wplus_ai_max_tokens = get(g:, 'wplus_ai_max_tokens', 2000)

" Azure-specific settings
let g:wplus_ai_azure_resource = get(g:, 'wplus_ai_azure_resource', '')  " e.g., 'my-resource'
let g:wplus_ai_azure_deployment = get(g:, 'wplus_ai_azure_deployment', '')  " e.g., 'gpt-4'
let g:wplus_ai_azure_api_version = get(g:, 'wplus_ai_azure_api_version', '2024-02-15-preview')

" Ghost Text auto-suggestion settings
let g:wplus_ai_suggest_enabled = get(g:, 'wplus_ai_suggest_enabled', 1)
let g:wplus_ai_suggest_delay = get(g:, 'wplus_ai_suggest_delay', 500)
let g:wplus_ai_suggest_context_lines = get(g:, 'wplus_ai_suggest_context_lines', 50)
let g:wplus_ai_suggest_suffix_lines = get(g:, 'wplus_ai_suggest_suffix_lines', 20)

let s:requests = {} " request_id -> {job, bufnr, lnum, response_buffer}
let s:request_id = '' " current request_id

" Ghost Text state
let s:suggest_content = '' " current suggestion content
let s:suggest_line = 0 " line where suggestion was requested
let s:suggest_col = 0 " column where suggestion was requested
let s:suggest_timer = v:null
let s:suggest_keystroke_count = 0 " keystroke counter for adaptive delay


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
    else
        return 'https://api.openai.com/v1/chat/completions'
    endif
endfunction

function! s:get_request_headers() abort
    let l:headers = ['Content-Type: application/json']
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

function! s:build_request_payload(prompt) abort
    let l:system_msg = 'You are a helpful code assistant. Provide concise, accurate responses.'
    
    if g:wplus_ai_provider ==# 'claude'
        return json_encode({
            \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'claude-3-sonnet-20240229',
            \ 'max_tokens': g:wplus_ai_max_tokens,
            \ 'system': l:system_msg,
            \ 'messages': [{'role': 'user', 'content': a:prompt}],
            \ 'temperature': g:wplus_ai_temperature
            \ })
    else
        " Both OpenAI and Azure OpenAI use same request format (chat completions)
        return json_encode({
            \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'gpt-3.5-turbo',
            \ 'max_tokens': g:wplus_ai_max_tokens,
            \ 'temperature': g:wplus_ai_temperature,
            \ 'messages': [
            \   {'role': 'system', 'content': l:system_msg},
            \   {'role': 'user', 'content': a:prompt}
            \ ]
            \ })
    endif
endfunction

function! s:on_response(channel, msg) abort
    if !empty(s:request_id) && has_key(s:requests, s:request_id)
        let s:requests[s:request_id].response_buffer .= a:msg
    endif
endfunction

function! s:on_response_complete(channel) abort
    if empty(s:request_id) || !has_key(s:requests, s:request_id)
        return
    endif
    
    " Parse response based on provider
    let l:response = s:requests[s:request_id].response_buffer
    let l:bufnr = s:requests[s:request_id].bufnr
    let l:lnum = s:requests[s:request_id].lnum
    
    call remove(s:requests, s:request_id)
    let s:request_id = ''
    
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
    let l:content = ''
    if g:wplus_ai_provider ==# 'claude'
        if has_key(l:json, 'content') && len(l:json.content) > 0
            let l:content = l:json.content[0].text
        endif
    else
        if has_key(l:json, 'choices') && len(l:json.choices) > 0
            let l:content = l:json.choices[0].message.content
        endif
    endif
    
    if empty(l:content)
        call wplus#util#error_msg('ai', 'no content in response')
        return
    endif
    
    " Insert response at current position
    if bufloaded(a:bufnr)
        let l:lines = split(l:content, "\n")
        call append(a:start_lnum, l:lines)
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
    if empty(g:wplus_ai_api_key)
        call wplus#util#error_msg('ai', 'API key not configured (g:wplus_ai_api_key)')
        return
    endif
    
    if empty(g:wplus_ai_model)
        call wplus#util#error_msg('ai', 'model not configured (g:wplus_ai_ai_model)')
        return
    endif
    
    let l:endpoint = s:get_api_endpoint()
    let l:headers = s:get_request_headers()
    if empty(l:headers) | return | endif
    
    let l:payload = s:build_request_payload(a:prompt)
    let l:request_id = reltimestr(reltime()) " use timestamp as unique ID
    
    " Build curl command with all headers
    let l:cmd = ['curl', '-s', '-X', 'POST', '-d', l:payload, l:endpoint]
    
    " Add each header at the beginning (after base options)
    for l:header in l:headers
        call insert(l:cmd, l:header, 2)
        call insert(l:cmd, '-H', 2)
    endfor
    
    let l:job = job_start(l:cmd, {
        \ 'out_cb': function('s:on_response'),
        \ 'close_cb': function('s:on_response_complete'),
        \ 'err_cb': function('s:on_error')
        \ })
    
    let s:request_id = l:request_id
    let s:requests[l:request_id] = {
        \ 'job': l:job,
        \ 'bufnr': a:bufnr,
        \ 'lnum': a:lnum,
        \ 'response_buffer': ''
        \ }
    call wplus#util#info_msg('ai', 'sending request...')
endfunction

function! s:on_error(channel, msg) abort
    call wplus#util#error_msg('ai', 'request error: ' . a:msg)
endfunction

function! wplus#ai#setup() abort
    augroup WplusAI
        autocmd!
        autocmd VimLeavePre * for req in values(s:requests) | silent! call job_stop(req.job) | endfor
    augroup END
    
    " Warn if not configured, but still register commands
    if empty(g:wplus_ai_api_key) || empty(g:wplus_ai_model)
        if g:wplus_ai_provider ==# 'azure'
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
    if g:wplus_ai_suggest_enabled
        augroup WplusAISuggest
            autocmd!
            autocmd InsertEnter * call s:on_insert_enter()
            autocmd InsertLeave * call s:dismiss_suggestion()
            autocmd InsertTextChangedI * call s:on_text_changed()
        augroup END
    endif
endfunction

" ── Ghost Text Suggestion Functions ────────────────────────────────────────────

" Show Ghost Text suggestion with textprop
function! s:show_suggestion() abort
    call prop_remove({'type': 'WplusAISuggest', 'all': 1})
    
    if empty(s:suggest_content) | return | endif
    
    let l:lines = split(s:suggest_content, "\n", 1)
    let l:line = line('.')
    let l:col = col('.')
    
    try
        " First line appended to current line
        if !empty(l:lines[0])
            call prop_add(l:line, l:col, {
                \ 'type': 'WplusAISuggest',
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
                \ 'text': l:text,
                \ 'text_align': 'below',
                \ 'id': 1 + l:i,
                \ })
            let l:i += 1
        endwhile
        
        redraw
    catch
        return
    endtry
endfunction

" Dismiss current suggestion
function! s:dismiss_suggestion() abort
    let s:suggest_content = ''
    let s:suggest_line = 0
    let s:suggest_col = 0
    let s:suggest_keystroke_count = 0
    
    if s:suggest_timer != v:null
        call timer_stop(s:suggest_timer)
        let s:suggest_timer = v:null
    endif
    
    call prop_remove({'type': 'WplusAISuggest', 'all': 1})
endfunction

" Accept current suggestion
function! wplus#ai#accept_suggestion() abort
    if empty(s:suggest_content)
        " No suggestion, insert normal tab
        return "\<Tab>"
    endif
    
    let l:content = s:suggest_content
    call s:dismiss_suggestion()
    
    " Insert suggestion text at cursor position
    call wplus#util#info_msg('ai', 'suggestion accepted')
    
    " Simply append the suggestion to current line
    let l:line = getline('.')
    let l:col = col('.')
    let l:new_line = l:line[:l:col - 2] . l:content . l:line[l:col - 1:]
    
    let l:lines = split(l:new_line, "\n")
    if len(l:lines) > 1
        " Multi-line suggestion
        call setline('.', l:lines[0])
        for l:i in range(1, len(l:lines) - 1)
            call append(line('.'), l:lines[l:i])
        endfor
        call cursor(line('.') + len(l:lines) - 1, len(l:lines[-1]) + 1)
    else
        " Single-line suggestion
        call setline('.', l:new_line)
        call cursor(line('.'), l:col + len(l:content))
    endif
    
    return ''
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
            autocmd InsertTextChangedI * call s:on_text_changed()
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
    
    let l:prefix = wplus#ai#context#get_prefix(s:suggest_line, s:suggest_col)
    let l:suffix = wplus#ai#context#get_suffix(s:suggest_line, s:suggest_col)
    
    " Don't suggest if prefix is empty or only whitespace
    if empty(trim(l:prefix)) && empty(trim(l:suffix))
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
    
    if g:wplus_ai_provider ==# 'claude'
        return json_encode({
            \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'claude-3-sonnet-20240229',
            \ 'max_tokens': 500,
            \ 'system': l:system_msg,
            \ 'messages': [{'role': 'user', 'content': l:prompt}],
            \ 'temperature': 0.5
            \ })
    else
        return json_encode({
            \ 'model': !empty(g:wplus_ai_model) ? g:wplus_ai_model : 'gpt-3.5-turbo',
            \ 'max_tokens': 500,
            \ 'temperature': 0.5,
            \ 'messages': [
            \   {'role': 'system', 'content': l:system_msg},
            \   {'role': 'user', 'content': l:prompt}
            \ ]
            \ })
    endif
endfunction

" Response handler for suggestions
function! s:on_suggest_response(channel, msg) abort
    if !empty(s:request_id) && has_key(s:requests, s:request_id)
        let s:requests[s:request_id].response_buffer .= a:msg
    endif
endfunction

" Complete response handler for suggestions
function! s:on_suggest_response_complete(channel) abort
    if empty(s:request_id) || !has_key(s:requests, s:request_id)
        return
    endif
    
    let l:response = s:requests[s:request_id].response_buffer
    call remove(s:requests, s:request_id)
    let s:request_id = ''
    
    if empty(l:response)
        return
    endif
    
    try
        let l:json = json_decode(l:response)
    catch
        return
    endtry
    
    let l:content = ''
    if g:wplus_ai_provider ==# 'claude'
        if has_key(l:json, 'content') && len(l:json.content) > 0
            let l:content = l:json.content[0].text
        endif
    else
        if has_key(l:json, 'choices') && len(l:json.choices) > 0
            let l:content = l:json.choices[0].message.content
        endif
    endif
    
    if empty(l:content)
        return
    endif
    
    " Clean up response (remove markdown code blocks if present)
    let l:content = substitute(l:content, '```.*\n', '', 'g')
    let l:content = substitute(l:content, '```', '', 'g')
    let l:content = trim(l:content)
    
    " Only update if cursor is still at request position
    if line('.') == s:suggest_line && col('.') == s:suggest_col
        let s:suggest_content = l:content
        call s:show_suggestion()
    endif
endfunction

" Send suggestion request to AI
function! s:send_suggest_request(prefix, suffix, prompt) abort
    if empty(g:wplus_ai_api_key) || empty(g:wplus_ai_model)
        return
    endif
    
    let l:endpoint = s:get_api_endpoint()
    let l:headers = s:get_request_headers()
    if empty(l:headers) | return | endif
    
    let l:payload = s:build_suggest_payload(a:prefix, a:suffix)
    let l:request_id = reltimestr(reltime())
    
    let l:cmd = ['curl', '-s', '-X', 'POST', '-d', l:payload, l:endpoint]
    
    " Add headers
    for l:header in l:headers
        call insert(l:cmd, l:header, 2)
        call insert(l:cmd, '-H', 2)
    endfor
    
    let l:job = job_start(l:cmd, {
        \ 'out_cb': function('s:on_suggest_response'),
        \ 'close_cb': function('s:on_suggest_response_complete'),
        \ })
    
    let s:request_id = l:request_id
    let s:suggest_line = line('.')
    let s:suggest_col = col('.')
    let s:requests[l:request_id] = {
        \ 'job': l:job,
        \ 'bufnr': bufnr('%'),
        \ 'lnum': line('.'),
        \ 'response_buffer': ''
        \ }
endfunction
