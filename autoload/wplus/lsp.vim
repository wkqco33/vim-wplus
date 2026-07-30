" wplus/lsp.vim — Minimal LSP client using Vim 9 jobs/channels

if exists('g:autoloaded_wplus_lsp') | finish | endif
let g:autoloaded_wplus_lsp = 1

let s:servers = {} " ft -> {job, channel, last_id, requests, buffer}
let s:diag_timers = {} " uri -> timer_id
let s:pending_actions = []
let s:sig_winid = -1
let s:def_cache = {} " uri:line:col -> {result, timestamp} (with TTL)
let s:ref_cache = {} " uri:line:col -> {result, timestamp} (with TTL)
let s:symbol_cache = {} " uri -> {line_count, timestamp, symbols} (symbol info cache)
let g:wplus_lsp_log_enabled  = get(g:, 'wplus_lsp_log_enabled',  0)
let g:wplus_lsp_signcolumn   = get(g:, 'wplus_lsp_signcolumn',   'yes')
let g:wplus_lsp_cache_ttl    = get(g:, 'wplus_lsp_cache_ttl',    300)
let g:wplus_lsp_sig_delay    = get(g:, 'wplus_lsp_sig_delay',    100)
let g:wplus_lsp_change_delay = get(g:, 'wplus_lsp_change_delay', 800)
let g:wplus_lsp_diag_delay   = get(g:, 'wplus_lsp_diag_delay',   300)
let s:CONTENT_LENGTH_PREFIX  = 'Content-Length: '

function! s:log(ft, type, msg) abort
    if !g:wplus_lsp_log_enabled | return | endif
    let l:log_file = getcwd() . '/lsp.log'
    let l:line = printf('[%s][%s][%s] %s', strftime('%H:%M:%S'), a:ft, a:type, a:msg)
    call writefile([l:line], l:log_file, 'a')
endfunction

function! wplus#lsp#setup() abort
    if !has('job') || !has('channel') | return | endif
    call s:ensure_signcolumn()
    call s:define_diag_signs()
    augroup WplusLSP
        autocmd!
        autocmd FileType go,c,cpp,python,dart,rust call s:on_filetype_changed()
        autocmd BufDelete * call s:on_buf_delete()
        autocmd VimLeavePre * call s:cleanup_all()
    augroup END
    nnoremap <silent> <Plug>WplusLspDefinition  :call wplus#lsp#request('textDocument/definition')<CR>
    nnoremap <silent> <Plug>WplusLspHover       :call wplus#lsp#request('textDocument/hover')<CR>
    nnoremap <silent> <Plug>WplusLspReferences  :call wplus#lsp#request('textDocument/references')<CR>
    nnoremap <silent> <Plug>WplusLspRename      :call wplus#lsp#rename()<CR>
    nnoremap <silent> <Plug>WplusLspCodeAction  :call wplus#lsp#code_action()<CR>
    nnoremap <silent> ]e :call wplus#lsp#next_diag()<CR>
    nnoremap <silent> [e :call wplus#lsp#prev_diag()<CR>
    nnoremap <silent> <leader>E :call wplus#lsp#diag_popup()<CR>
endfunction

function! s:on_filetype_changed() abort
    let l:ft = &filetype
    call s:ensure_signcolumn()
    call s:start_server(l:ft)
    augroup WplusLSPBuffer
        autocmd! * <buffer>
        autocmd BufWritePost <buffer> call s:did_save(&filetype)
        autocmd TextChanged,TextChangedI <buffer> call s:on_change(&filetype)
        autocmd InsertCharPre <buffer>
            \ if v:char ==# '(' || v:char ==# ','
            \   | call s:throttle_signature_help()
            \ | endif
        autocmd InsertLeave <buffer> call s:close_signature_help()
    augroup END
    nmap <buffer><silent> gd         <Plug>WplusLspDefinition
    nmap <buffer><silent> K          <Plug>WplusLspHover
    nmap <buffer><silent> gr         <Plug>WplusLspReferences
    nmap <buffer><silent> <leader>rn <Plug>WplusLspRename
    nmap <buffer><silent> <leader>ca <Plug>WplusLspCodeAction
    inoremap <buffer><silent><expr> <Tab>
        \ (get(g:, 'wplus_ai_enabled', 1) && get(g:, 'wplus_ai_suggest_enabled', 1) && wplus#ai#has_suggestion()) ? wplus#ai#accept_suggestion() :
        \ pumvisible() ? "\<C-n>" :
        \ <SID>check_backspace() ? "\<Tab>" :
        \ "\<C-r>=wplus#lsp#request('textDocument/completion')\<CR>\<Ignore>"
endfunction

function! s:throttle_signature_help() abort
    let l:buf = bufnr('%')
    let l:sig_timer = getbufvar(l:buf, 'wplus_lsp_sig_timer', -1)
    if l:sig_timer != -1
        return
    endif
    let l:timer = timer_start(g:wplus_lsp_sig_delay, {-> s:do_signature_help(l:buf)})
    call setbufvar(l:buf, 'wplus_lsp_sig_timer', l:timer)
endfunction

function! s:do_signature_help(buf) abort
    if bufnr('%') == a:buf
        call wplus#lsp#request('textDocument/signatureHelp')
    endif
    call setbufvar(a:buf, 'wplus_lsp_sig_timer', -1)
endfunction

function! s:ensure_signcolumn() abort
    if empty(g:wplus_lsp_signcolumn) | return | endif
    if &signcolumn ==# 'auto' || empty(&signcolumn)
        try
            execute 'set signcolumn=' . g:wplus_lsp_signcolumn
        catch /^Vim(set):E474/
            silent! set signcolumn=yes
        endtry
    endif
endfunction

function! s:check_backspace() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1] =~# '\s'
endfunction

function! s:url_encode(str) abort
    let l:res = ''
    let l:len = strlen(a:str)
    let l:i = 0
    while l:i < l:len
        let l:ch = strpart(a:str, l:i, 1, 1)
        if l:ch =~# '[A-Za-z0-9._~/-]'
            let l:res .= l:ch
        else
            let l:res .= printf('%%%02X', char2nr(l:ch))
        endif
        let l:i += 1
    endwhile
    return l:res
endfunction

function! s:get_uri(path) abort
    let l:p = fnamemodify(a:path, ':p')
    if has('win32')
        let l:p = substitute(l:p, '\\', '/', 'g')
        return 'file:///' . s:url_encode(l:p)
    endif
    return 'file://' . (l:p[0] ==# '/' ? '' : '/') . s:url_encode(l:p)
endfunction

function! s:get_buf_uri(buf) abort
    let l:name = bufname(a:buf)
    return empty(l:name) ? '' : s:get_uri(l:name)
endfunction

function! s:decode_uri_path(uri) abort
    let l:path = substitute(a:uri, '\v^file:/*(localhost)?', '', '')
    let l:len = strlen(l:path)
    let l:i = 0
    let l:res = ''
    while l:i < l:len
        if strpart(l:path, l:i, 1, 1) ==# '%' && l:i + 2 < l:len && strpart(l:path, l:i+1, 2, 1) =~# '^\x\x$'
            let l:hex = strpart(l:path, l:i+1, 2, 1)
            let l:res .= nr2char(str2nr(l:hex, 16), 1)
            let l:i += 3
        else
            let l:res .= strpart(l:path, l:i, 1, 1)
            let l:i += 1
        endif
    endwhile
    if l:res =~# '^[A-Za-z]:[\\/]'
        return l:res
    endif
    return l:res[0] ==# '/' ? l:res : '/' . l:res
endfunction

function! s:get_request_params(method) abort
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri)
        return {}
    endif

    let l:params = {
        \ 'textDocument': {'uri': l:uri},
        \ 'position': {'line': line('.') - 1, 'character': col('.') - 1},
        \ }
    if a:method ==# 'textDocument/references'
        let l:params.context = {'includeDeclaration': v:true}
    endif
    return l:params
endfunction

function! s:uri_to_bufnr(uri) abort
    let l:abs = fnamemodify(s:decode_uri_path(a:uri), ':p')
    let l:nr = bufnr(l:abs)
    if l:nr != -1 | return l:nr | endif
    for l:buf in getbufinfo({'buflisted': 1})
        if !empty(l:buf.name) && fnamemodify(l:buf.name, ':p') ==# l:abs | return l:buf.bufnr | endif
    endfor
    return -1
endfunction

function! s:did_open(ft) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let b:wplus_lsp_version = get(b:, 'wplus_lsp_version', 0) + 1
    let l:params = {'textDocument': {'uri': l:uri, 'languageId': a:ft, 'version': b:wplus_lsp_version, 'text': join(getline(1, '$'), "\n") . "\n"}}
    call s:send(a:ft, 'textDocument/didOpen', l:params, 1)
    call wplus#lsp#request_inlay_hints()
endfunction

function! s:on_change(ft) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:buf = bufnr('%')
    " Cancel previous timer to prevent duplicate timers
    let l:timer_id = getbufvar(l:buf, 'wplus_lsp_timer', -1)
    if l:timer_id != -1
        silent! call timer_stop(l:timer_id)
    endif
    let l:timer = timer_start(g:wplus_lsp_change_delay, {-> s:send_change(l:buf, a:ft)})
    call setbufvar(l:buf, 'wplus_lsp_timer', l:timer)
endfunction

function! s:send_change(buf, ft) abort
    if !bufexists(a:buf) | return | endif
    let l:uri = s:get_buf_uri(a:buf)
    if empty(l:uri) | return | endif
    let l:ver = getbufvar(a:buf, 'wplus_lsp_version', 0) + 1
    call setbufvar(a:buf, 'wplus_lsp_version', l:ver)
    let l:params = {'textDocument': {'uri': l:uri, 'version': l:ver}, 'contentChanges': [{'text': join(getbufline(a:buf, 1, '$'), "\n") . "\n"}]}
    call s:send(a:ft, 'textDocument/didChange', l:params, 1)
endfunction

function! s:did_save(ft) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    call s:send(a:ft, 'textDocument/didSave', {'textDocument': {'uri': l:uri}}, 1)
    call wplus#lsp#request_inlay_hints()
endfunction

function! s:start_server(ft) abort
    if has_key(s:servers, a:ft) && job_status(s:servers[a:ft].job) ==# 'run' | call s:did_open(a:ft) | return | endif
    let l:cmds = {'go': ['gopls'], 'c': ['clangd'], 'cpp': ['clangd'], 'python': ['pyright-langserver', '--stdio'], 'dart': ['dart', 'language-server', '--protocol=lsp'], 'rust': ['rust-analyzer']}
    if !has_key(l:cmds, a:ft) || !executable(l:cmds[a:ft][0]) | return | endif
    let l:job = job_start(l:cmds[a:ft], {'in_mode': 'raw', 'out_mode': 'raw', 'out_cb': {c, m -> s:on_stdout(a:ft, c, m)}, 'err_cb': {c, m -> s:log(a:ft, 'STDERR', m)}})
    let s:servers[a:ft] = {'job': l:job, 'channel': job_getchannel(l:job), 'last_id': 0, 'requests': {}, 'buffer': ''}
    call s:send(a:ft, 'initialize', {
        \ 'processId': getpid(),
        \ 'rootUri': s:get_uri(getcwd()),
        \ 'capabilities': {'textDocument': {
        \   'synchronization': {'didChange': 1, 'willSave': v:true, 'didSave': v:true},
        \   'hover': {'contentFormat': ['plaintext', 'markdown']},
        \   'definition': {'dynamicRegistration': v:true},
        \   'references': {'dynamicRegistration': v:true},
        \   'completion': {'completionItem': {'snippetSupport': v:false}},
        \   'rename': {'dynamicRegistration': v:true, 'prepareSupport': v:false},
        \   'codeAction': {'dynamicRegistration': v:true, 'codeActionLiteralSupport': {'codeActionKind': {'valueSet': []}}},
        \   'signatureHelp': {'signatureInformation': {'documentationFormat': ['plaintext', 'markdown']}},
        \   'inlayHint': {'dynamicRegistration': v:true},
        \ }}})
endfunction

function! s:send(ft, method, params, ...) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:s = s:servers[a:ft]
    if job_status(l:s.job) !=# 'run' | return | endif
    let l:is_notify = a:0 > 0 ? a:1 : 0
    let l:req = {'jsonrpc': '2.0', 'method': a:method, 'params': a:params}
    if !l:is_notify
        let l:s.last_id += 1
        let l:req.id = l:s.last_id
        let l:s.requests[l:s.last_id] = a:method
    endif
    let l:body = json_encode(l:req)
    call s:log(a:ft, 'SEND', l:body)
    call ch_sendraw(l:s.channel, 'Content-Length: ' . strlen(l:body) . "\r\n\r\n" . l:body)
endfunction

function! s:read_location_text(uri, lnum) abort
    let l:path = s:decode_uri_path(a:uri)
    if !filereadable(l:path)
        return ''
    endif
    let l:lines = readfile(l:path, '', a:lnum)
    return len(l:lines) >= a:lnum ? l:lines[a:lnum - 1] : ''
endfunction

function! s:on_stdout(ft, channel, msg) abort
    let l:s = s:servers[a:ft]
    let l:s.buffer .= a:msg
    while 1
        let l:idx = stridx(l:s.buffer, "Content-Length: ")
        if l:idx == -1 | break | endif
        if l:idx > 0
            let l:s.buffer = strpart(l:s.buffer, l:idx, strlen(l:s.buffer) - l:idx, 1)
            let l:idx = 0
        endif
        let l:end = stridx(l:s.buffer, "\r\n\r\n")
        if l:end == -1 | break | endif
        let l:len_str = strpart(l:s.buffer, len(s:CONTENT_LENGTH_PREFIX), l:end - len(s:CONTENT_LENGTH_PREFIX), 1)
        let l:len = str2nr(l:len_str)
        if strlen(l:s.buffer) < l:end + 4 + l:len | break | endif
        let l:body = strpart(l:s.buffer, l:end + 4, l:len, 1)
        let l:s.buffer = strpart(l:s.buffer, l:end + 4 + l:len, strlen(l:s.buffer) - (l:end + 4 + l:len), 1)
        call s:handle_message(a:ft, l:body)
    endwhile
endfunction

function! s:handle_message(ft, body) abort
    call s:log(a:ft, 'RECV', a:body)
    try
        let l:resp = json_decode(a:body)
    catch
        call s:log(a:ft, 'JSON_ERR', a:body)
        return
    endtry
    if type(l:resp) != v:t_dict | return | endif
    call s:handle_response(a:ft, l:resp)
endfunction

function! s:handle_notification(ft, resp) abort
    if get(a:resp, 'method', '') ==# 'textDocument/publishDiagnostics'
        call s:update_diagnostics(a:ft, a:resp.params)
    endif
endfunction

function! s:handle_request_result(ft, method, result) abort
    if a:method ==# 'initialize'
        call s:send(a:ft, 'initialized', {}, 1)
        call s:did_open(a:ft)
    elseif a:method ==# 'textDocument/definition'
        call s:goto_location(a:result)
    elseif a:method ==# 'textDocument/hover'
        call s:show_hover(a:result)
    elseif a:method ==# 'textDocument/references'
        call s:show_references(a:result)
    elseif a:method ==# 'textDocument/completion'
        call s:show_completion(a:result)
    elseif a:method ==# 'textDocument/rename'
        call s:apply_workspace_edit(a:result)
    elseif a:method ==# 'textDocument/codeAction'
        call s:show_code_actions(a:result)
    elseif a:method ==# 'textDocument/signatureHelp'
        call s:show_signature_help(a:result)
    elseif a:method ==# 'textDocument/inlayHint'
        call s:show_inlay_hints(a:result)
    endif
endfunction

function! s:handle_response(ft, resp) abort
    if !has_key(a:resp, 'id')
        call s:handle_notification(a:ft, a:resp)
        return
    endif
    let l:id = a:resp.id
    let l:method = get(s:servers[a:ft].requests, l:id, '')
    if empty(l:method) | return | endif
    unlet s:servers[a:ft].requests[l:id]
    if has_key(a:resp, 'error') | return | endif
    
    let l:result = get(a:resp, 'result', {})
    
    " Cache definition and references results
    if (l:method ==# 'textDocument/definition' || l:method ==# 'textDocument/references') && !empty(l:result)
        let l:uri = s:get_buf_uri(bufnr('%'))
        if !empty(l:uri)
            let l:cache = l:method ==# 'textDocument/definition' ? s:def_cache : s:ref_cache
            call s:store_cache(l:cache, l:uri, line('.') - 1, col('.') - 1, l:result)
        endif
    endif
    
    call s:handle_request_result(a:ft, l:method, l:result)
endfunction

function! s:diag_style(sev) abort
    if a:sev == 1
        return {'sign': 'WplusLspError', 'type': 'WplusLspDiagErr', 'key': 'error', 'hl': 'ErrorMsg'}
    elseif a:sev == 2
        return {'sign': 'WplusLspWarn', 'type': 'WplusLspDiagWarn', 'key': 'warning', 'hl': 'WarningMsg'}
    elseif a:sev == 3
        return {'sign': 'WplusLspInfo', 'type': 'WplusLspDiagInfo', 'key': 'info', 'hl': 'Directory'}
    endif
    return {'sign': 'WplusLspHint', 'type': 'WplusLspDiagHint', 'key': 'hint', 'hl': 'Comment'}
endfunction

function! s:define_diag_signs() abort
    highlight default WplusDiagError guifg=#fb4934 ctermfg=167
    highlight default WplusDiagWarn  guifg=#fabd2f ctermfg=214
    highlight default WplusDiagInfo  guifg=#83a598 ctermfg=109
    highlight default WplusDiagHint  guifg=#928374 ctermfg=243
    silent! call sign_define('WplusLspError', {'text': 'E', 'texthl': 'WplusDiagError'})
    silent! call sign_define('WplusLspWarn',  {'text': 'W', 'texthl': 'WplusDiagWarn'})
    silent! call sign_define('WplusLspInfo',  {'text': 'I', 'texthl': 'WplusDiagInfo'})
    silent! call sign_define('WplusLspHint',  {'text': 'H', 'texthl': 'WplusDiagHint'})
    if has('textprop')
        silent! call prop_type_add('WplusLspDiagErr', {'highlight': 'WplusDiagError'})
        silent! call prop_type_add('WplusLspDiagWarn', {'highlight': 'WplusDiagWarn'})
        silent! call prop_type_add('WplusLspDiagInfo', {'highlight': 'WplusDiagInfo'})
        silent! call prop_type_add('WplusLspDiagHint', {'highlight': 'WplusDiagHint'})
        if empty(prop_type_get('WplusLspInlay'))
            silent! call prop_type_add('WplusLspInlay', {'highlight': 'WplusDiagHint'})
        endif
    endif
endfunction

function! wplus#lsp#request_inlay_hints() abort
    if !get(g:, 'wplus_lsp_inlay_hints', 1) | return | endif
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:params = {
        \ 'textDocument': {'uri': l:uri},
        \ 'range': {
        \   'start': {'line': 0, 'character': 0},
        \   'end': {'line': line('$'), 'character': 0},
        \ },
        \ }
    call s:send(l:ft, 'textDocument/inlayHint', l:params, 0)
endfunction

function! s:show_inlay_hints(result) abort
    if !has('textprop') || empty(a:result) | return | endif
    let l:bufnr = bufnr('%')
    silent! call prop_remove({'type': 'WplusLspInlay', 'bufnr': l:bufnr, 'all': v:true})
    let l:items = type(a:result) == v:t_list ? a:result : get(a:result, 'items', [])
    for l:hint in l:items
        let l:pos = get(l:hint, 'position', {})
        if empty(l:pos) | continue | endif
        let l:lnum = get(l:pos, 'line', 0) + 1
        let l:col = get(l:pos, 'character', 0) + 1
        let l:raw_label = get(l:hint, 'label', '')
        let l:text = ''
        if type(l:raw_label) == v:t_string
            let l:text = l:raw_label
        elseif type(l:raw_label) == v:t_list
            let l:parts = []
            for l:part in l:raw_label
                if type(l:part) == v:t_dict
                    call add(l:parts, get(l:part, 'value', ''))
                elseif type(l:part) == v:t_string
                    call add(l:parts, l:part)
                endif
            endfor
            let l:text = join(l:parts, '')
        endif
        if empty(l:text) | continue | endif
        if get(l:hint, 'paddingLeft', v:false) | let l:text = ' ' . l:text | endif
        if get(l:hint, 'paddingRight', v:false) | let l:text = l:text . ' ' | endif

        silent! call prop_add(l:lnum, l:col, {
            \ 'bufnr': l:bufnr,
            \ 'type': 'WplusLspInlay',
            \ 'text': l:text,
            \ 'text_align': 'inline',
            \ })
    endfor
endfunction

function! s:update_diagnostics(ft, params) abort
    let l:uri = get(a:params, 'uri', '')
    silent! call timer_stop(get(s:diag_timers, l:uri, -1))
    let s:diag_timers[l:uri] = timer_start(g:wplus_lsp_diag_delay, {-> s:diag_timer_fire(l:uri, a:ft, a:params)})
endfunction

function! s:diag_timer_fire(uri, ft, params) abort
    unlet! s:diag_timers[a:uri]
    call s:do_update_diagnostics(a:ft, a:params)
endfunction

function! s:clear_diagnostics(bufnr, last_line) abort
    call sign_unplace('WplusLspGroup', {'buffer': a:bufnr})
    if has('textprop')
        silent! call prop_remove({'type': 'WplusLspDiagErr', 'bufnr': a:bufnr, 'all': v:true}, 1, a:last_line)
        silent! call prop_remove({'type': 'WplusLspDiagWarn', 'bufnr': a:bufnr, 'all': v:true}, 1, a:last_line)
        silent! call prop_remove({'type': 'WplusLspDiagInfo', 'bufnr': a:bufnr, 'all': v:true}, 1, a:last_line)
        silent! call prop_remove({'type': 'WplusLspDiagHint', 'bufnr': a:bufnr, 'all': v:true}, 1, a:last_line)
    endif
endfunction

function! s:do_update_diagnostics(ft, params) abort
    let l:bufnr = s:uri_to_bufnr(a:params.uri)
    if l:bufnr == -1 | return | endif

    let l:bufinfo = getbufinfo(l:bufnr)
    if empty(l:bufinfo) | return | endif
    let l:last_line = l:bufinfo[0].linecount
    call s:clear_diagnostics(l:bufnr, l:last_line)

    let l:diags = {}
    let l:counts = {'error': 0, 'warning': 0, 'info': 0, 'hint': 0}
    let l:signs = []
    let l:has_textprop = has('textprop')
    for l:diag in a:params.diagnostics
        let l:lnum = l:diag.range.start.line + 1
        if l:lnum <= 0 || l:lnum > l:last_line | continue | endif

        let l:sev = get(l:diag, 'severity', 1)
        let l:style = s:diag_style(l:sev)
        let l:counts[l:style.key] += 1

        call add(l:signs, {'id': 0, 'group': 'WplusLspGroup', 'name': l:style.sign, 'buffer': l:bufnr, 'lnum': l:lnum, 'priority': 20})
        if l:has_textprop && get(g:, 'wplus_lsp_inline_diags', 0)
            let l:msg = '  // ' . split(l:diag.message, "\n")[0]
            silent! call prop_add(l:lnum, 0, {'bufnr': l:bufnr, 'type': l:style.type, 'text': l:msg, 'text_align': 'after'})
        endif
        if !has_key(l:diags, l:lnum) || l:sev < l:diags[l:lnum].sev
            let l:diags[l:lnum] = {'msg': l:diag.message, 'sev': l:sev}
        endif
    endfor

    if !empty(l:signs) | call sign_placelist(l:signs) | endif
    call setbufvar(l:bufnr, 'wplus_lsp_diags', l:diags)
    call setbufvar(l:bufnr, 'wplus_lsp_diag_counts', l:counts)
    redrawstatus
endfunction

function! s:echo_diag() abort
    let l:diags = getbufvar(bufnr('%'), 'wplus_lsp_diags', {})
    let l:lnum = line('.')
    if has_key(l:diags, l:lnum)
        let l:info = l:diags[l:lnum]
        let l:style = s:diag_style(l:info.sev)
        execute 'echohl ' . l:style.hl
        echo l:info.msg
        echohl None
    endif
endfunction

function! wplus#lsp#next_diag() abort
    let l:diags = get(b:, 'wplus_lsp_diags', {})
    if empty(l:diags) | call wplus#util#info_msg('lsp', 'No diagnostics') | return | endif
    let l:lines = sort(map(keys(l:diags), 'str2nr(v:val)'), 'n')
    let l:cur = line('.')
    for l:ln in l:lines
        if l:ln > l:cur
            call cursor(l:ln, 1)
            call s:echo_diag()
            return
        endif
    endfor
    call cursor(l:lines[0], 1)
    call s:echo_diag()
endfunction

function! wplus#lsp#prev_diag() abort
    let l:diags = get(b:, 'wplus_lsp_diags', {})
    if empty(l:diags) | call wplus#util#info_msg('lsp', 'No diagnostics') | return | endif
    let l:lines = sort(map(keys(l:diags), 'str2nr(v:val)'), 'n')
    let l:cur = line('.')
    let l:prev = l:lines[-1]
    for l:ln in l:lines
        if l:ln >= l:cur | break | endif
        let l:prev = l:ln
    endfor
    call cursor(l:prev, 1)
    call s:echo_diag()
endfunction

function! wplus#lsp#diag_popup() abort
    let l:diags = get(b:, 'wplus_lsp_diags', {})
    let l:lnum = line('.')
    if !has_key(l:diags, l:lnum)
        call wplus#util#info_msg('lsp', 'No diagnostic on this line')
        return
    endif
    let l:info = l:diags[l:lnum]
    let l:style = s:diag_style(l:info.sev)
    let l:lines = split(l:info.msg, "\n")
    call popup_create(l:lines, {
        \ 'line':     'cursor+1',
        \ 'col':      'cursor',
        \ 'moved':    'any',
        \ 'border':   [1, 1, 1, 1],
        \ 'borderhighlight': [l:style.hl],
        \ 'padding':  [0, 1, 0, 1],
        \ 'wrap':     1,
        \ 'maxwidth': 80,
        \ })
endfunction

function! s:make_cache_key(uri, lnum, col) abort
    return a:uri . ':' . a:lnum . ':' . a:col
endfunction

function! s:lookup_cache(cache, uri, lnum, col) abort
    let l:key = s:make_cache_key(a:uri, a:lnum, a:col)
    if !has_key(a:cache, l:key) | return v:null | endif
    
    let l:entry = a:cache[l:key]
    let l:now = reltime()[0] " Current timestamp in seconds
    let l:age = l:now - l:entry.timestamp
    
    " Check if cache expired
    if l:age > g:wplus_lsp_cache_ttl
        call remove(a:cache, l:key)
        return v:null
    endif
    
    return l:entry.result
endfunction

function! s:store_cache(cache, uri, lnum, col, result) abort
    let l:key = s:make_cache_key(a:uri, a:lnum, a:col)
    let a:cache[l:key] = {'result': a:result, 'timestamp': reltime()[0]}
endfunction

function! wplus#lsp#request(method) abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:params = s:get_request_params(a:method)
    if empty(l:params) | return | endif
    
    " Check cache for definition/references before requesting
    if a:method ==# 'textDocument/definition'
        let l:cached = s:lookup_cache(s:def_cache, l:params.textDocument.uri, l:params.position.line, l:params.position.character)
        if l:cached isnot v:null
            call s:handle_request_result(l:ft, a:method, l:cached)
            return
        endif
    elseif a:method ==# 'textDocument/references'
        let l:cached = s:lookup_cache(s:ref_cache, l:params.textDocument.uri, l:params.position.line, l:params.position.character)
        if l:cached isnot v:null
            call s:handle_request_result(l:ft, a:method, l:cached)
            return
        endif
    endif
    
    call s:send(l:ft, a:method, l:params, 0)
endfunction

function! wplus#lsp#rename() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:word = expand('<cword>')
    if empty(l:word) | return | endif
    let l:new_name = input('Rename ' . l:word . ' → ')
    if empty(l:new_name) || l:new_name ==# l:word | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:params = {
        \ 'textDocument': {'uri': l:uri},
        \ 'position': {'line': line('.') - 1, 'character': col('.') - 1},
        \ 'newName': l:new_name,
        \ }
    call s:send(l:ft, 'textDocument/rename', l:params, 0)
endfunction

function! wplus#lsp#code_action() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:lnum = line('.')
    let l:diags = getbufvar(bufnr('%'), 'wplus_lsp_diags', {})
    let l:diag_items = []
    if has_key(l:diags, l:lnum)
        let l:d = l:diags[l:lnum]
        call add(l:diag_items, {
            \ 'message': l:d.msg,
            \ 'severity': l:d.sev,
            \ 'range': {'start': {'line': l:lnum - 1, 'character': 0}, 'end': {'line': l:lnum - 1, 'character': 0}},
            \ })
    endif
    let l:params = {
        \ 'textDocument': {'uri': l:uri},
        \ 'range': {
        \   'start': {'line': l:lnum - 1, 'character': col('.') - 1},
        \   'end': {'line': l:lnum - 1, 'character': col('.') - 1},
        \ },
        \ 'context': {'diagnostics': l:diag_items},
        \ }
    call s:send(l:ft, 'textDocument/codeAction', l:params, 0)
endfunction

function! s:goto_location(result) abort
    let l:loc = type(a:result) == v:t_list ? get(a:result, 0) : a:result
    if empty(l:loc) | return | endif
    let l:uri = get(l:loc, 'uri', get(l:loc, 'targetUri', ''))
    let l:range = get(l:loc, 'range', get(l:loc, 'targetSelectionRange', {}))
    execute 'edit +' . (l:range.start.line + 1) . ' ' . fnameescape(s:decode_uri_path(l:uri))
endfunction

function! s:show_hover(result) abort
    if empty(a:result) || empty(a:result.contents) | return | endif
    let l:contents = a:result.contents
    let l:text = type(l:contents) == v:t_dict ? l:contents.value : (type(l:contents) == v:t_list ? join(map(copy(l:contents), 'type(v:val) == v:t_dict ? v:val.value : v:val'), "\n") : l:contents)
    let l:lines = split(l:text, "\n")
    if empty(l:lines) | return | endif
    let l:winid = popup_atcursor(l:lines, {'title': ' ' . expand('<cword>') . ' ', 'padding': [1,2,1,2], 'border': [1,1,1,1], 'moved': 'any', 'maxwidth': float2nr(&columns * 0.6), 'maxheight': float2nr(&lines * 0.5), 'borderchars': ['─', '│', '─', '│', '┌', '┐', '┘', '└'], 'highlight': 'Normal', 'borderhighlight': ['Special']})
    call setbufvar(winbufnr(l:winid), '&filetype', 'markdown')
endfunction

function! s:show_references(result) abort
    if empty(a:result) | return | endif
    let l:qflist = []
    for l:ref in a:result
        let l:filename = s:decode_uri_path(l:ref.uri)
        let l:lnum = l:ref.range.start.line + 1
        call add(l:qflist, {
            \ 'filename': l:filename,
            \ 'lnum': l:lnum,
            \ 'col': l:ref.range.start.character + 1,
            \ 'text': s:read_location_text(l:ref.uri, l:lnum),
            \ })
    endfor
    call setqflist(l:qflist)
    botright copen
endfunction

function! s:show_completion(result) abort
    if empty(a:result) | return | endif
    let l:items = type(a:result) == v:t_list ? a:result : a:result.items
    let l:matches = []
    let l:kind_map = {1: 'v', 2: 'f', 3: 'm', 4: 'f', 5: 'f', 6: 'c', 7: 'i', 8: 's', 9: 'm', 10: 'p', 11: 'u', 12: 'e', 13: 'k', 14: 's', 15: 's'}
    for l:item in l:items | call add(l:matches, {'word': get(l:item, 'insertText', l:item.label), 'abbr': l:item.label, 'kind': get(l:kind_map, get(l:item, 'kind', 0), 't'), 'menu': get(l:item, 'detail', '')}) | endfor
    let l:start = col('.') - 1
    while l:start > 0 && getline('.')[l:start - 1] =~# '\k' | let l:start -= 1 | endwhile
    call complete(l:start + 1, l:matches)
endfunction

" ── rename ────────────────────────────────────────────────────────────────

function! s:apply_workspace_edit(edit) abort
    if empty(a:edit) | return | endif
    if has_key(a:edit, 'documentChanges')
        for l:change in a:edit.documentChanges
            if has_key(l:change, 'textDocument')
                call s:apply_text_edits(s:decode_uri_path(l:change.textDocument.uri), l:change.edits)
            endif
        endfor
    elseif has_key(a:edit, 'changes')
        for [l:uri, l:edits] in items(a:edit.changes)
            call s:apply_text_edits(s:decode_uri_path(l:uri), l:edits)
        endfor
    endif
endfunction

function! s:apply_text_edits(path, edits) abort
    let l:abs = fnamemodify(a:path, ':p')
    if bufnr(l:abs) == -1
        silent execute 'badd ' . fnameescape(l:abs)
    endif
    let l:bufnr = bufnr(l:abs)
    if !bufloaded(l:bufnr)
        call bufload(l:bufnr)
    endif

    " Reverse sort: bottom-to-top to preserve line numbers during edits
    let l:sorted = sort(copy(a:edits), {a, b ->
        \ a.range.start.line != b.range.start.line
        \   ? b.range.start.line - a.range.start.line
        \   : b.range.start.character - a.range.start.character})

    for l:e in l:sorted
        let l:sl = l:e.range.start.line + 1
        let l:sc = l:e.range.start.character
        let l:el = l:e.range.end.line + 1
        let l:ec = l:e.range.end.character

        let l:start_line = get(getbufline(l:bufnr, l:sl), 0, '')
        let l:end_line   = l:el == l:sl ? l:start_line : get(getbufline(l:bufnr, l:el), 0, '')
        let l:prefix = l:sc > 0 ? l:start_line[: l:sc - 1] : ''
        let l:suffix = l:end_line[l:ec : ]

        let l:replacement = split(l:prefix . l:e.newText . l:suffix, "\n", 1)
        " appendbufline, not append: every other call here is explicitly scoped to
        " l:bufnr, but bare append() writes into the *current* buffer. During a
        " cross-file rename that meant the edits for every other file landed in
        " whatever buffer the user happened to be looking at, while the correct
        " lines were deleted from the real target.
        call appendbufline(l:bufnr, l:el, l:replacement)
        call deletebufline(l:bufnr, l:sl, l:el)
    endfor

    call setbufvar(l:bufnr, '&modified', 1)
endfunction

" ── code action ───────────────────────────────────────────────────────────

function! s:show_code_actions(result) abort
    if empty(a:result)
        call wplus#util#warn_msg('lsp', 'No code actions available')
        return
    endif
    let s:pending_actions = a:result
    let l:titles = map(copy(a:result), 'get(v:val, "title", "?")')
    call wplus#finder#open(l:titles, function('s:execute_code_action'), 'Code Actions')
endfunction

function! s:execute_code_action(title) abort
    for l:action in s:pending_actions
        if get(l:action, 'title', '') ==# a:title
            if has_key(l:action, 'edit')
                call s:apply_workspace_edit(l:action.edit)
            endif
            if has_key(l:action, 'command')
                let l:cmd = type(l:action.command) == v:t_dict
                    \ ? l:action.command
                    \ : {'command': l:action.command, 'arguments': get(l:action, 'arguments', [])}
                let l:ft = &filetype
                if has_key(s:servers, l:ft)
                    call s:send(l:ft, 'workspace/executeCommand', l:cmd, 0)
                endif
            endif
            return
        endif
    endfor
endfunction

" ── signature help ────────────────────────────────────────────────────────

function! s:show_signature_help(result) abort
    call s:close_signature_help()
    if empty(a:result) | return | endif
    let l:sigs = get(a:result, 'signatures', [])
    if empty(l:sigs) | return | endif
    let l:idx = get(a:result, 'activeSignature', 0)
    let l:sig = l:sigs[min([l:idx, len(l:sigs) - 1])]
    let l:lines = [get(l:sig, 'label', '')]
    let l:doc = get(l:sig, 'documentation', '')
    if type(l:doc) == v:t_dict | let l:doc = get(l:doc, 'value', '') | endif
    if !empty(l:doc)
        let l:first = split(l:doc, "\n")[0]
        if !empty(l:first) | call add(l:lines, l:first) | endif
    endif
    let s:sig_winid = popup_atcursor(l:lines, {
        \ 'padding': [0,1,0,1],
        \ 'border': [1,1,1,1],
        \ 'moved': 'any',
        \ 'highlight': 'Normal',
        \ 'borderhighlight': ['Special'],
        \ 'maxwidth': float2nr(&columns * 0.6),
        \ })
endfunction

function! s:close_signature_help() abort
    if s:sig_winid != -1
        silent! call popup_close(s:sig_winid)
        let s:sig_winid = -1
    endif
endfunction

function! s:on_buf_delete() abort
    " Clean up any timers for this buffer
    let l:buf = bufnr('%')
    let l:timer_id = getbufvar(l:buf, 'wplus_lsp_timer', -1)
    if l:timer_id != -1
        silent! call timer_stop(l:timer_id)
    endif
endfunction

function! s:cleanup_all() abort
    " Stop all pending timers
    for l:uri in keys(s:diag_timers)
        silent! call timer_stop(s:diag_timers[l:uri])
    endfor
    let s:diag_timers = {}
    let s:pending_actions = []
    
    " Clear caches to free memory
    let s:def_cache = {}
    let s:ref_cache = {}
    let s:symbol_cache = {}
    
    " Close all LSP servers gracefully
    for l:ft in keys(s:servers)
        let l:server = s:servers[l:ft]
        if job_status(l:server.job) ==# 'run'
            call s:send(l:ft, 'shutdown', {}, 0)
            silent! call job_stop(l:server.job)
        endif
    endfor
    let s:servers = {}
endfunction

function! wplus#lsp#is_ready(ft) abort
    return has_key(s:servers, a:ft) && job_status(s:servers[a:ft].job) ==# 'run'
endfunction
