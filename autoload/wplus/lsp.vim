" wplus/lsp.vim — built-in Language Server Protocol client
" Requires: Vim 9.1+ with +job +channel +json +popupwin +signs

if exists('g:autoloaded_wplus_lsp') | finish | endif
let g:autoloaded_wplus_lsp = 1

let s:servers   = {} " ft -> {job, channel, last_id, requests, buffer, caps, initialized}
let s:diag_timers = {} " uri -> timer_id
let s:hover_winid = -1
let s:sig_winid   = -1
let s:def_cache   = {} " uri:line:col -> {result, timestamp} (with TTL)
let s:ref_cache   = {} " uri:line:col -> {result, timestamp} (with TTL)
let s:symbol_cache = {} " uri -> symbols
let s:warned_caps = {} " ft:method -> 1

let g:wplus_lsp_log_enabled     = get(g:, 'wplus_lsp_log_enabled',     0)
let g:wplus_lsp_signcolumn      = get(g:, 'wplus_lsp_signcolumn',      'yes')
let g:wplus_lsp_cache_ttl       = get(g:, 'wplus_lsp_cache_ttl',       300)
let g:wplus_lsp_sig_delay       = get(g:, 'wplus_lsp_sig_delay',       100)
let g:wplus_lsp_change_delay    = get(g:, 'wplus_lsp_change_delay',    800)
let g:wplus_lsp_diag_delay      = get(g:, 'wplus_lsp_diag_delay',      300)
let g:wplus_lsp_request_timeout = get(g:, 'wplus_lsp_request_timeout', 10)
let g:wplus_lsp_definition_split = get(g:, 'wplus_lsp_definition_split', 0)
let g:wplus_lsp_servers = get(g:, 'wplus_lsp_servers', {
    \ 'go': ['gopls'],
    \ 'c': ['clangd'],
    \ 'cpp': ['clangd'],
    \ 'python': ['pyright-langserver', '--stdio'],
    \ 'dart': ['dart', 'language-server', '--protocol=lsp'],
    \ 'rust': ['rust-analyzer'],
    \ })
let s:CONTENT_LENGTH_PREFIX     = 'Content-Length: '
let s:timeout_timer             = -1

function! s:log(ft, type, msg) abort
    if !g:wplus_lsp_log_enabled | return | endif
    let l:log_file = getcwd() . '/lsp.log'
    let l:line = printf('[%s][%s][%s] %s', strftime('%H:%M:%S'), a:ft, a:type, a:msg)
    call writefile([l:line], l:log_file, 'a')
endfunction

function! s:get_uri(path) abort
    let l:p = fnamemodify(a:path, ':p')
    if has('win32')
        let l:p = substitute(l:p, '\\', '/', 'g')
        if l:p !~# '^/' | let l:p = '/' . l:p | endif
    endif
    return 'file://' . l:p
endfunction

function! s:get_buf_uri(buf) abort
    let l:path = bufname(a:buf)
    return empty(l:path) ? '' : s:get_uri(l:path)
endfunction

function! s:decode_uri_path(uri) abort
    let l:path = substitute(a:uri, '^file://', '', '')
    " Hex-decode percent-encoded characters (%20 -> space, etc.)
    let l:path = substitute(l:path, '%\(\x\x\)', '\=nr2char("0x" . submatch(1))', 'g')
    if has('win32')
        if l:path =~# '^/[a-zA-Z]:'
            let l:path = l:path[1:]
        endif
        let l:path = substitute(l:path, '/', '\\', 'g')
    endif
    return l:path
endfunction

function! s:supports(ft, method) abort
    if !has_key(s:servers, a:ft) | return 0 | endif
    let l:s = s:servers[a:ft]
    if !get(l:s, 'initialized', 0) | return 1 | endif
    let l:caps = get(l:s, 'caps', {})
    if empty(l:caps) | return 1 | endif

    let l:cap_map = {
        \ 'textDocument/hover': 'hoverProvider',
        \ 'textDocument/definition': 'definitionProvider',
        \ 'textDocument/references': 'referencesProvider',
        \ 'textDocument/completion': 'completionProvider',
        \ 'textDocument/formatting': 'documentFormattingProvider',
        \ 'textDocument/rangeFormatting': 'documentRangeFormattingProvider',
        \ 'textDocument/documentSymbol': 'documentSymbolProvider',
        \ 'textDocument/documentHighlight': 'documentHighlightProvider',
        \ 'textDocument/foldingRange': 'foldingRangeProvider',
        \ 'textDocument/signatureHelp': 'signatureHelpProvider',
        \ 'textDocument/inlayHint': 'inlayHintProvider',
        \ 'textDocument/codeAction': 'codeActionProvider',
        \ 'textDocument/rename': 'renameProvider',
        \ }

    if has_key(l:cap_map, a:method)
        let l:cap_key = l:cap_map[a:method]
        let l:val = get(l:caps, l:cap_key, v:true)
        let l:ok = 1
        if type(l:val) == v:t_bool
            let l:ok = l:val
        elseif type(l:val) == v:t_dict
            let l:ok = !empty(l:val)
        endif
        if !l:ok
            let l:wkey = a:ft . ':' . a:method
            if !has_key(s:warned_caps, l:wkey)
                let s:warned_caps[l:wkey] = 1
                call wplus#util#warn_msg('lsp', 'LSP server for ' . a:ft . ' does not support ' . a:method)
            endif
            return 0
        endif
    endif

    return 1
endfunction

function! s:did_open(ft) abort
    let l:buf = bufnr('%')
    let l:uri = s:get_buf_uri(l:buf)
    if empty(l:uri) | return | endif
    call setbufvar(l:buf, 'wplus_lsp_uri', l:uri)
    call setbufvar(l:buf, 'wplus_lsp_version', 1)
    let l:params = {'textDocument': {'uri': l:uri, 'languageId': a:ft, 'version': 1, 'text': join(getline(1, '$'), "\n") . "\n"}}
    call s:send(a:ft, 'textDocument/didOpen', l:params, 1)
    call wplus#lsp#request_inlay_hints()
endfunction

function! s:did_close(bufnr) abort
    let l:uri = getbufvar(a:bufnr, 'wplus_lsp_uri', '')
    let l:ft  = getbufvar(a:bufnr, '&filetype', '')
    if !empty(l:uri) && !empty(l:ft) && has_key(s:servers, l:ft)
        call s:send(l:ft, 'textDocument/didClose', {'textDocument': {'uri': l:uri}}, 1)
    endif
endfunction

function! s:did_change(ft, buf) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:timer = getbufvar(a:buf, 'wplus_lsp_change_timer', -1)
    if l:timer != -1 | silent! call timer_stop(l:timer) | endif
    let l:new_timer = timer_start(g:wplus_lsp_change_delay, {-> s:do_did_change(a:ft, a:buf)})
    call setbufvar(a:buf, 'wplus_lsp_change_timer', l:new_timer)
endfunction

function! s:do_did_change(ft, buf) abort
    call setbufvar(a:buf, 'wplus_lsp_change_timer', -1)
    let l:uri = s:get_buf_uri(a:buf)
    if empty(l:uri) | return | endif
    let l:ver = getbufvar(a:buf, 'wplus_lsp_version', 1) + 1
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

function! s:job_running(job) abort
    return type(a:job) == v:t_job && job_status(a:job) ==# 'run'
endfunction

function! s:project_root() abort
    let l:root = exists('*wplus#root#find_root') ? wplus#root#find_root() : ''
    return empty(l:root) ? getcwd() : resolve(fnamemodify(l:root, ':p'))
endfunction

function! s:start_server(ft) abort
    let l:root = s:project_root()
    if has_key(s:servers, a:ft) && s:job_running(s:servers[a:ft].job)
        if get(s:servers[a:ft], 'root', '') ==# l:root
            call s:did_open(a:ft)
            return
        endif
        " Never reuse a language server from another project root.
        call wplus#lsp#stop(a:ft)
    endif
    let l:configured = get(g:wplus_lsp_servers, a:ft, [])
    let l:cmd = type(l:configured) == v:t_dict ? get(l:configured, 'cmd', []) : l:configured
    if type(l:cmd) != v:t_list || empty(l:cmd) || !executable(l:cmd[0]) | return | endif
    let l:job = job_start(l:cmd, {'in_mode': 'raw', 'out_mode': 'raw', 'out_cb': {c, m -> s:on_stdout(a:ft, c, m)}, 'err_cb': {c, m -> s:log(a:ft, 'STDERR', m)}})
    let s:servers[a:ft] = {
        \ 'job': l:job,
        \ 'root': l:root,
        \ 'channel': job_getchannel(l:job),
        \ 'last_id': 0,
        \ 'requests': {},
        \ 'buffer': '',
        \ 'caps': {},
        \ 'initialized': 0,
        \ }
    call s:send(a:ft, 'initialize', {
        \ 'processId': getpid(),
        \ 'rootUri': s:get_uri(l:root),
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
        \   'documentSymbol': {'hierarchicalDocumentSymbolSupport': v:true},
        \   'formatting': {'dynamicRegistration': v:true},
        \   'rangeFormatting': {'dynamicRegistration': v:true},
        \   'documentHighlight': {'dynamicRegistration': v:true},
        \   'foldingRange': {'dynamicRegistration': v:true},
        \   'publishDiagnostics': {'relatedInformation': v:true},
        \ }}})
endfunction

function! s:send(ft, method, params, ...) abort
    if !has_key(s:servers, a:ft) | return 0 | endif
    let l:is_notify = a:0 > 0 ? a:1 : 0
    let l:is_user   = a:0 > 1 ? a:2 : 0

    if !l:is_notify && !s:supports(a:ft, a:method)
        return 0
    endif

    let l:s = s:servers[a:ft]
    if !s:job_running(l:s.job) | return 0 | endif

    let l:req = {'jsonrpc': '2.0', 'method': a:method, 'params': a:params}
    if !l:is_notify
        let l:s.last_id += 1
        let l:req.id = l:s.last_id
        let l:req_uri = get(get(a:params, 'textDocument', {}), 'uri', '')
        let l:s.requests[l:req.id] = {
            \ 'method': a:method,
            \ 'at': localtime(),
            \ 'is_user': l:is_user,
            \ 'uri': l:req_uri,
            \ 'bufnr': bufnr('%'),
            \ 'changedtick': b:changedtick,
            \ 'lnum': line('.'),
            \ 'col': col('.'),
            \ }
    endif

    let l:payload = json_encode(l:req)
    let l:msg = 'Content-Length: ' . strlen(l:payload) . "\r\n\r\n" . l:payload
    call s:log(a:ft, 'SEND', l:payload)
    try
        call ch_sendraw(l:s.channel, l:msg)
        return l:is_notify ? 1 : l:s.last_id
    catch
        call s:log(a:ft, 'SEND_ERR', v:exception)
        return 0
    endtry
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
    if !has_key(s:servers, a:ft) | return | endif
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

function! s:request_is_current(req, method) abort
    if a:method !~# '^textDocument/' | return 1 | endif
    if type(a:req) != v:t_dict | return 1 | endif
    let l:buf = get(a:req, 'bufnr', -1)
    let l:uri = get(a:req, 'uri', '')
    if l:buf <= 0 || !bufloaded(l:buf) || empty(l:uri)
        return 0
    endif
    if s:get_buf_uri(l:buf) !=# l:uri || getbufvar(l:buf, 'changedtick', -1) != get(a:req, 'changedtick', -2)
        return 0
    endif
    if get(a:req, 'is_user', 0) && a:method =~# '^textDocument/\%(hover\|completion\|signatureHelp\|definition\|references\)$'
        return bufnr('%') == l:buf && line('.') == get(a:req, 'lnum', -1) && col('.') == get(a:req, 'col', -1)
    endif
    return 1
endfunction

function! s:handle_request_result(ft, method, result, ...) abort
    let l:req = a:0 ? a:1 : {}
    let l:req_uri = type(l:req) == v:t_dict ? get(l:req, 'uri', '') : ''
    if a:method ==# 'initialize'
        let s:servers[a:ft].caps = get(a:result, 'capabilities', {})
        let s:servers[a:ft].initialized = 1
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
    elseif a:method ==# 'textDocument/formatting'
        if !empty(a:result) && !empty(l:req_uri)
            let l:buf = get(l:req, 'bufnr', -1)
            if l:buf > 0 && bufloaded(l:buf) && getbufvar(l:buf, 'changedtick', -1) == get(l:req, 'changedtick', -2)
                call s:apply_text_edits(s:decode_uri_path(l:req_uri), a:result)
            elseif get(l:req, 'is_user', 0)
                call wplus#util#warn_msg('lsp', 'format result discarded: buffer changed or unloaded')
            endif
        endif
    elseif a:method ==# 'textDocument/documentSymbol'
        let l:uri = s:get_buf_uri(bufnr('%'))
        if !empty(l:uri)
            let s:symbol_cache[l:uri] = a:result
            silent! doautocmd User WplusLspSymbolsUpdate
        endif
    elseif a:method ==# 'textDocument/foldingRange'
        if !empty(a:result)
            let b:wplus_lsp_fold_ranges = a:result
            silent! doautocmd User WplusLspFoldsUpdate
        endif
    elseif a:method ==# 'textDocument/documentHighlight'
        call s:show_document_highlights(a:result)
    endif
endfunction

function! s:handle_response(ft, resp) abort
    if !has_key(a:resp, 'id')
        call s:handle_notification(a:ft, a:resp)
        return
    endif
    let l:id = a:resp.id
    if !has_key(s:servers, a:ft) | return | endif
    let l:req_info = get(s:servers[a:ft].requests, l:id, {})
    if empty(l:req_info) | return | endif
    unlet s:servers[a:ft].requests[l:id]

    let l:method = type(l:req_info) == v:t_dict ? get(l:req_info, 'method', '') : l:req_info
    let l:is_user = type(l:req_info) == v:t_dict ? get(l:req_info, 'is_user', 0) : 0

    if has_key(a:resp, 'error')
        let l:err_msg = type(a:resp.error) == v:t_dict ? get(a:resp.error, 'message', string(a:resp.error)) : string(a:resp.error)
        call s:log(a:ft, 'ERROR_RESP', l:err_msg)
        if l:is_user
            call wplus#util#warn_msg('lsp', 'LSP error (' . l:method . '): ' . l:err_msg)
        endif
        return
    endif

    if !s:request_is_current(l:req_info, l:method)
        if l:is_user
            call wplus#util#warn_msg('lsp', 'stale response discarded: ' . l:method)
        endif
        return
    endif

    let l:result = get(a:resp, 'result', {})

    if (l:method ==# 'textDocument/definition' || l:method ==# 'textDocument/references') && !empty(l:result)
        let l:uri = s:get_buf_uri(bufnr('%'))
        if !empty(l:uri)
            let l:cache = l:method ==# 'textDocument/definition' ? s:def_cache : s:ref_cache
            call s:store_cache(l:cache, l:uri, line('.') - 1, col('.') - 1, l:result)
        endif
    endif

    call s:handle_request_result(a:ft, l:method, l:result, l:req_info)
endfunction

function! s:diag_style(sev) abort
    if a:sev == 1
        return {'sign': 'WplusLspError', 'type': 'WplusLspDiagErr', 'key': 'error', 'hl': 'ErrorMsg'}
    elseif a:sev == 2
        return {'sign': 'WplusLspWarn',  'type': 'WplusLspDiagWarn', 'key': 'warning', 'hl': 'WarningMsg'}
    elseif a:sev == 3
        return {'sign': 'WplusLspInfo',  'type': 'WplusLspDiagInfo', 'key': 'info', 'hl': 'None'}
    else
        return {'sign': 'WplusLspHint',  'type': 'WplusLspDiagHint', 'key': 'hint', 'hl': 'None'}
    endif
endfunction

function! s:define_signs() abort
    call sign_define('WplusLspError', {'text': 'E', 'texthl': 'ErrorMsg'})
    call sign_define('WplusLspWarn',  {'text': 'W', 'texthl': 'WarningMsg'})
    call sign_define('WplusLspInfo',  {'text': 'I', 'texthl': 'None'})
    call sign_define('WplusLspHint',  {'text': 'H', 'texthl': 'None'})

    if has('textprop')
        if empty(prop_type_get('WplusLspDiagErr'))
            call prop_type_add('WplusLspDiagErr', {'highlight': 'WplusDiagError'})
        endif
        if empty(prop_type_get('WplusLspDiagWarn'))
            call prop_type_add('WplusLspDiagWarn', {'highlight': 'WplusDiagWarn'})
        endif
        if empty(prop_type_get('WplusLspDiagInfo'))
            call prop_type_add('WplusLspDiagInfo', {'highlight': 'WplusDiagInfo'})
        endif
        if empty(prop_type_get('WplusLspDiagHint'))
            call prop_type_add('WplusLspDiagHint', {'highlight': 'WplusDiagHint'})
        endif
        if empty(prop_type_get('WplusLspInlay'))
            silent! call prop_type_add('WplusLspInlay', {'highlight': 'WplusDiagHint'})
        endif
        if empty(prop_type_get('WplusLspHighlight'))
            silent! call prop_type_add('WplusLspHighlight', {'highlight': 'WplusIlluminate'})
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

function! s:show_document_highlights(result) abort
    if !has('textprop') || empty(a:result) | return | endif
    let l:bufnr = bufnr('%')
    silent! call prop_remove({'type': 'WplusLspHighlight', 'bufnr': l:bufnr, 'all': v:true})
    for l:hl in a:result
        let l:range = get(l:hl, 'range', {})
        if empty(l:range) | continue | endif
        let l:sl = l:range.start.line + 1
        let l:sc = l:range.start.character + 1
        let l:el = l:range.end.line + 1
        let l:ec = l:range.end.character + 1
        silent! call prop_add(l:sl, l:sc, {
            \ 'bufnr': l:bufnr,
            \ 'end_lnum': l:el,
            \ 'end_col': l:ec,
            \ 'type': 'WplusLspHighlight',
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

function! s:do_update_diagnostics(ft, params) abort
    let l:path = s:decode_uri_path(a:params.uri)
    let l:bufnr = bufnr(l:path)
    if l:bufnr == -1 | return | endif

    call sign_unplace('wplus_lsp', {'buffer': l:bufnr})
    if has('textprop')
        for l:pt in ['WplusLspDiagErr', 'WplusLspDiagWarn', 'WplusLspDiagInfo', 'WplusLspDiagHint']
            silent! call prop_remove({'type': l:pt, 'bufnr': l:bufnr, 'all': v:true})
        endfor
    endif

    let l:diag_map   = {}
    let l:counts     = {'error': 0, 'warning': 0, 'info': 0, 'hint': 0}
    let l:seen_signs = {}

    for l:d in a:params.diagnostics
        let l:lnum = l:d.range.start.line + 1
        let l:col  = l:d.range.start.character + 1
        let l:sev  = get(l:d, 'severity', 1)
        let l:st   = s:diag_style(l:sev)

        let l:counts[l:st.key] += 1

        if !has_key(l:diag_map, l:lnum)
            let l:diag_map[l:lnum] = []
        endif
        call add(l:diag_map[l:lnum], {'msg': l:d.message, 'sev': l:sev, 'col': l:col})

        if !has_key(l:seen_signs, l:lnum)
            let l:seen_signs[l:lnum] = 1
            call sign_place(0, 'wplus_lsp', l:st.sign, l:bufnr, {'lnum': l:lnum})
        endif

        if has('textprop')
            let l:end_lnum = get(l:d.range, 'end', {}).line + 1
            let l:end_col  = get(l:d.range, 'end', {}).character + 1
            if l:end_lnum < l:lnum || (l:end_lnum == l:lnum && l:end_col <= l:col)
                let l:end_lnum = l:lnum
                let l:end_col  = l:col + 1
            endif
            silent! call prop_add(l:lnum, l:col, {
                \ 'bufnr':    l:bufnr,
                \ 'end_lnum': l:end_lnum,
                \ 'end_col':  l:end_col,
                \ 'type':     l:st.type,
                \ })
        endif
    endfor

    call setbufvar(l:bufnr, 'wplus_lsp_diags',       l:diag_map)
    call setbufvar(l:bufnr, 'wplus_lsp_diag_counts', l:counts)
    redrawstatus
endfunction

function! s:echo_diag() abort
    let l:diags = getbufvar(bufnr('%'), 'wplus_lsp_diags', {})
    let l:lnum = line('.')
    if has_key(l:diags, l:lnum) && !empty(l:diags[l:lnum])
        let l:info = l:diags[l:lnum][0]
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
    if !has_key(l:diags, l:lnum) || empty(l:diags[l:lnum])
        call wplus#util#info_msg('lsp', 'No diagnostic on this line')
        return
    endif
    let l:msgs = map(copy(l:diags[l:lnum]), 'v:val.msg')
    let l:style = s:diag_style(l:diags[l:lnum][0].sev)
    call popup_create(l:msgs, wplus#util#popup_options({
        \ 'line':     'cursor+1',
        \ 'col':      'cursor',
        \ 'moved':    'any',
        \ 'borderhighlight': [l:style.hl],
        \ }))
endfunction

function! s:make_cache_key(uri, lnum, col) abort
    return a:uri . ':' . a:lnum . ':' . a:col
endfunction

function! s:lookup_cache(cache, uri, lnum, col) abort
    let l:key = s:make_cache_key(a:uri, a:lnum, a:col)
    if !has_key(a:cache, l:key) | return v:null | endif

    let l:entry = a:cache[l:key]
    let l:now = reltime()[0]
    let l:age = l:now - l:entry.timestamp

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

function! wplus#lsp#hover() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    call s:send(l:ft, 'textDocument/hover', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}}, 0, 1)
endfunction

function! wplus#lsp#definition() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    let l:cached = s:lookup_cache(s:def_cache, l:uri, l:pos[1] - 1, l:pos[2] - 1)
    if l:cached isnot v:null
        call s:goto_location(l:cached)
        return
    endif
    call s:send(l:ft, 'textDocument/definition', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}}, 0, 1)
endfunction

function! wplus#lsp#references() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    let l:cached = s:lookup_cache(s:ref_cache, l:uri, l:pos[1] - 1, l:pos[2] - 1)
    if l:cached isnot v:null
        call s:show_references(l:cached)
        return
    endif
    call s:send(l:ft, 'textDocument/references', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}, 'context': {'includeDeclaration': v:true}}, 0, 1)
endfunction

function! wplus#lsp#completion() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    call s:send(l:ft, 'textDocument/completion', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}})
endfunction

function! wplus#lsp#rename() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:word = expand('<cword>')
    let l:new_name = input('New name: ', l:word)
    if empty(l:new_name) || l:new_name ==# l:word | return | endif
    let l:pos = getcurpos()
    call s:send(l:ft, 'textDocument/rename', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}, 'newName': l:new_name}, 0, 1)
endfunction

function! wplus#lsp#code_action() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    let l:diags = get(b:, 'wplus_lsp_diags', {})
    let l:line_diags = get(l:diags, l:pos[1], [])
    call s:send(l:ft, 'textDocument/codeAction', {'textDocument': {'uri': l:uri}, 'range': {'start': {'line': l:pos[1] - 1, 'character': 0}, 'end': {'line': l:pos[1], 'character': 0}}, 'context': {'diagnostics': l:line_diags}}, 0, 1)
endfunction

function! wplus#lsp#signature_help() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    call s:send(l:ft, 'textDocument/signatureHelp', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}})
endfunction

function! wplus#lsp#format(bufnr) abort
    let l:buf = a:bufnr == 0 ? bufnr('%') : a:bufnr
    let l:ft = getbufvar(l:buf, '&filetype', '')
    if !s:supports(l:ft, 'textDocument/formatting') | return 0 | endif
    let l:uri = s:get_buf_uri(l:buf)
    if empty(l:uri) | return 0 | endif
    let l:tabsize = getbufvar(l:buf, '&shiftwidth', 4)
    if l:tabsize == 0 | let l:tabsize = getbufvar(l:buf, '&tabstop', 4) | endif
    let l:insert_spaces = getbufvar(l:buf, '&expandtab', 1) ? v:true : v:false
    return s:send(l:ft, 'textDocument/formatting', {
        \ 'textDocument': {'uri': l:uri},
        \ 'options': {'tabSize': l:tabsize, 'insertSpaces': l:insert_spaces}
        \ }, 0, 1) > 0
endfunction

function! wplus#lsp#request_document_symbols(bufnr) abort
    let l:buf = a:bufnr == 0 ? bufnr('%') : a:bufnr
    let l:ft = getbufvar(l:buf, '&filetype', '')
    if !s:supports(l:ft, 'textDocument/documentSymbol') | return | endif
    let l:uri = s:get_buf_uri(l:buf)
    if empty(l:uri) | return | endif
    call s:send(l:ft, 'textDocument/documentSymbol', {'textDocument': {'uri': l:uri}})
endfunction

function! wplus#lsp#get_symbols(bufnr) abort
    let l:buf = a:bufnr == 0 ? bufnr('%') : a:bufnr
    let l:uri = s:get_buf_uri(l:buf)
    return get(s:symbol_cache, l:uri, [])
endfunction

function! wplus#lsp#request_fold_ranges(...) abort
    let l:buf = a:0 >= 1 && a:1 != 0 ? a:1 : bufnr('%')
    let l:ft = getbufvar(l:buf, '&filetype', '')
    if !s:supports(l:ft, 'textDocument/foldingRange') | return | endif
    let l:uri = s:get_buf_uri(l:buf)
    if empty(l:uri) | return | endif
    call s:send(l:ft, 'textDocument/foldingRange', {'textDocument': {'uri': l:uri}})
endfunction

function! s:show_hover(result) abort
    if empty(a:result) | return | endif
    let l:contents = a:result.contents
    let l:lines = []
    if type(l:contents) == v:t_string
        let l:lines = split(l:contents, "\n")
    elseif type(l:contents) == v:t_dict
        let l:lines = split(l:contents.value, "\n")
    elseif type(l:contents) == v:t_list
        for l:item in l:contents
            let l:txt = type(l:item) == v:t_string ? l:item : l:item.value
            call extend(l:lines, split(l:txt, "\n"))
        endfor
    endif
    if empty(l:lines) | return | endif
    call s:close_popup(s:hover_winid)
    let s:hover_winid = popup_create(l:lines, wplus#util#popup_options({'line': 'cursor-1', 'col': 'cursor', 'moved': 'any'}))
endfunction

function! s:show_signature_help(result) abort
    if empty(a:result) || empty(a:result.signatures) | return | endif
    let l:idx = get(a:result, 'activeSignature', 0)
    let l:sig = a:result.signatures[l:idx]
    let l:lines = [l:sig.label]
    if has_key(l:sig, 'documentation')
        let l:doc = type(l:sig.documentation) == v:t_string ? l:sig.documentation : l:sig.documentation.value
        call extend(l:lines, split(l:doc, "\n"))
    endif
    call s:close_popup(s:sig_winid)
    let s:sig_winid = popup_create(l:lines, wplus#util#popup_options({'line': 'cursor+1', 'col': 'cursor', 'moved': 'any'}))
endfunction

function! s:close_popup(winid) abort
    if a:winid != -1 && popup_getoptions(a:winid) != {}
        call popup_close(a:winid)
    endif
endfunction

function! s:goto_location(result) abort
    if empty(a:result) | return | endif
    let l:loc = type(a:result) == v:t_list ? a:result[0] : a:result
    let l:uri = get(l:loc, 'uri', get(l:loc, 'targetUri', ''))
    let l:range = get(l:loc, 'range', get(l:loc, 'targetSelectionRange', {}))
    if empty(l:uri) || empty(l:range) | return | endif
    let l:path = s:decode_uri_path(l:uri)
    let l:split = get(g:, 'wplus_lsp_definition_split', 0)
    if l:split == 1
        execute 'split ' . fnameescape(l:path)
    elseif l:split == 2
        execute 'vsplit ' . fnameescape(l:path)
    elseif l:split == 3
        execute 'tabedit ' . fnameescape(l:path)
    else
        execute 'edit ' . fnameescape(l:path)
    endif
    call cursor(l:range.start.line + 1, l:range.start.character + 1)
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
    let l:bufnr = wplus#util#ensure_bufloaded(a:path)

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

        call deletebufline(l:bufnr, l:sl, l:el)
        call appendbufline(l:bufnr, l:sl - 1, l:replacement)
    endfor
endfunction

function! s:show_code_actions(result) abort
    if empty(a:result) | return | endif
    let l:actions = a:result
    let l:options = []
    for l:a in l:actions
        call add(l:options, type(l:a) == v:t_string ? l:a : l:a.title)
    endfor
    call popup_menu(l:options, {
        \ 'callback': {id, idx -> idx > 0 ? s:execute_code_action(l:actions[idx - 1]) : 0},
        \ 'title': ' Code Actions ',
        \ })
endfunction

function! s:execute_code_action(action) abort
    if type(a:action) == v:t_dict
        if has_key(a:action, 'edit')
            call s:apply_workspace_edit(a:action.edit)
        endif
        if has_key(a:action, 'command')
            let l:cmd = type(a:action.command) == v:t_string ? a:action.command : a:action.command.command
            call s:send(&filetype, 'workspace/executeCommand', {'command': l:cmd, 'arguments': get(a:action.command, 'arguments', [])})
        endif
    endif
endfunction

function! wplus#lsp#stop(ft) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:server = s:servers[a:ft]
    if s:job_running(l:server.job)
        call s:send(a:ft, 'shutdown', {})
        call s:send(a:ft, 'exit', {}, 1)
        silent! call job_stop(l:server.job)
    endif
    call remove(s:servers, a:ft)
endfunction

function! wplus#lsp#stop_all() abort
    for [l:ft, l:server] in items(s:servers)
        if s:job_running(l:server.job)
            call s:send(l:ft, 'shutdown', {})
            call s:send(l:ft, 'exit', {}, 1)
            let l:i = 0
            while l:i < 10 && s:job_running(l:server.job)
                sleep 20m
                let l:i += 1
            endwhile
            if s:job_running(l:server.job)
                silent! call job_stop(l:server.job)
            endif
        endif
    endfor
    let s:servers = {}
endfunction

function! s:check_request_timeouts(timer) abort
    let l:now = localtime()
    for [l:ft, l:server] in items(s:servers)
        for [l:id, l:req] in items(l:server.requests)
            let l:at = type(l:req) == v:t_dict ? get(l:req, 'at', l:now) : l:now
            if (l:now - l:at) >= g:wplus_lsp_request_timeout
                call remove(l:server.requests, l:id)
                let l:method = type(l:req) == v:t_dict ? get(l:req, 'method', '') : l:req
                if type(l:req) == v:t_dict && get(l:req, 'is_user', 0)
                    call wplus#util#warn_msg('lsp', 'LSP request timed out: ' . l:method)
                endif
            endif
        endfor
    endfor
endfunction

function! wplus#lsp#_test_apply_workspace_edit(edit) abort
    call s:apply_workspace_edit(a:edit)
endfunction

function! wplus#lsp#_test_supports(ft, method) abort
    return s:supports(a:ft, a:method)
endfunction

function! wplus#lsp#_test_set_caps(ft, caps) abort
    if !has_key(s:servers, a:ft)
        let s:servers[a:ft] = {'job': v:null, 'channel': v:null, 'last_id': 0, 'requests': {}, 'buffer': '', 'caps': a:caps, 'initialized': 1}
    else
        let s:servers[a:ft].caps = a:caps
        let s:servers[a:ft].initialized = 1
    endif
endfunction

function! wplus#lsp#setup() abort
    call s:define_signs()

    let s:timeout_timer = timer_start(5000, function('s:check_request_timeouts'), {'repeat': -1})

    command! WlspHover          call wplus#lsp#hover()
    command! WlspDefinition     call wplus#lsp#definition()
    command! WlspReferences     call wplus#lsp#references()
    command! WlspRename         call wplus#lsp#rename()
    command! WlspCodeAction     call wplus#lsp#code_action()
    command! WlspNextDiag       call wplus#lsp#next_diag()
    command! WlspPrevDiag       call wplus#lsp#prev_diag()
    command! WlspDiagPopup      call wplus#lsp#diag_popup()
    command! WlspSignatureHelp  call wplus#lsp#signature_help()
    command! WlspFormat         call wplus#lsp#format(0)

    nnoremap <silent> K          :WlspHover<CR>
    nnoremap <silent> gd         :WlspDefinition<CR>
    nnoremap <silent> gr         :WlspReferences<CR>
    nnoremap <silent> <leader>rn :WlspRename<CR>
    nnoremap <silent> <leader>ca :WlspCodeAction<CR>
    nnoremap <silent> ]d         :WlspNextDiag<CR>
    nnoremap <silent> [d         :WlspPrevDiag<CR>
    nnoremap <silent> <leader>d  :WlspDiagPopup<CR>
    inoremap <silent> <C-s>      <C-o>:WlspSignatureHelp<CR>

    augroup wplus_lsp
        autocmd!
        autocmd FileType * call s:start_server(&filetype)
        autocmd BufReadPost * call s:did_open(&filetype)
        autocmd TextChanged,TextChangedI * call s:did_change(&filetype, bufnr('%'))
        autocmd BufWritePost * call s:did_save(&filetype)
        autocmd BufUnload * call s:did_close(expand('<abuf>'))
        autocmd VimLeavePre * call wplus#lsp#stop_all()
    augroup END
endfunction
