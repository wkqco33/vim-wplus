" wplus/ai.vim — AI assistant with OpenAI/Claude integration

if exists('g:autoloaded_wplus_ai') | finish | endif
let g:autoloaded_wplus_ai = 1

let g:wplus_ai_provider = get(g:, 'wplus_ai_provider', 'openai') " 'openai' or 'claude'
let g:wplus_ai_model = get(g:, 'wplus_ai_model', '')
let g:wplus_ai_api_key = get(g:, 'wplus_ai_api_key', '')
let g:wplus_ai_temperature = get(g:, 'wplus_ai_temperature', 0.7)
let g:wplus_ai_max_tokens = get(g:, 'wplus_ai_max_tokens', 2000)

let s:requests = {} " request_id -> {job, bufnr, start_lnum, status}
let s:response_buffer = ''

function! s:get_api_endpoint() abort
    if g:wplus_ai_provider ==# 'claude'
        return 'https://api.anthropic.com/v1/messages'
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

function! s:on_response(job, bufnr, start_lnum, data) abort
    let s:response_buffer .= join(a:data, '')
endfunction

function! s:on_response_complete(job, bufnr, start_lnum) abort
    " Parse response based on provider
    let l:response = s:response_buffer
    let s:response_buffer = ''
    
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
    let l:request_id = reltimestr(reltime()) | " use timestamp as unique ID
    
    let l:job = job_start(['curl', '-s', '-X', 'POST',
        \ '-H', 'Content-Type: application/json',
        \ '-d', l:payload,
        \ l:endpoint], {
        \ 'out_cb': function('s:on_response', [a:bufnr, a:lnum]),
        \ 'close_cb': function('s:on_response_complete', [a:bufnr, a:lnum]),
        \ 'err_cb': function('s:on_error')
        \ })
    
    let s:requests[l:request_id] = {'job': l:job, 'bufnr': a:bufnr}
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
        call wplus#util#warn_msg('ai', 'API not fully configured. Set g:wplus_ai_provider, g:wplus_ai_model, g:wplus_ai_api_key')
    endif
    
    " Commands
    command! -range WaiComment   call wplus#ai#comment('visual')
    command! -nargs=? WaiComplete call wplus#ai#complete(<q-args> != '' ? <q-args> : 5)
    command! -range WaiRefactor  call wplus#ai#refactor()
    
    " Mappings
    nnoremap <silent> <Plug>WaiComment   :WaiComment<CR>
    nnoremap <silent> <Plug>WaiComplete  :WaiComplete<CR>
    xnoremap <silent> <Plug>WaiRefactor  :WaiRefactor<CR>
endfunction
