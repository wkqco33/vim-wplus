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
let g:wplus_lsp_auto_complete   = get(g:, 'wplus_lsp_auto_complete',   1)
let g:wplus_lsp_complete_delay  = get(g:, 'wplus_lsp_complete_delay',  300)
" Show identifier completion after a short token, while still relying on
" server triggerCharacters for punctuation-driven member completion.
let g:wplus_lsp_complete_min_chars = get(g:, 'wplus_lsp_complete_min_chars', 2)
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
let s:auto_complete_timer       = -1
let s:semantic_prop_types       = {}
let s:token_type_hl = {
    \ 0: 'Identifier', 1: 'Type', 2: 'Type', 3: 'Type', 4: 'Type', 5: 'Type',
    \ 6: 'Identifier', 7: 'Identifier', 8: 'Identifier', 9: 'Identifier',
    \ 10: 'Constant', 11: 'Function', 12: 'Function', 13: 'Function',
    \ 14: 'PreProc', 15: 'Statement', 16: 'Special', 17: 'Comment',
    \ 18: 'String', 19: 'Number', 20: 'String', 21: 'Operator', 22: 'PreProc',
    \ }

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

function! s:supports(ft, method, ...) abort
    let l:silent = a:0 > 0 ? a:1 : 0
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
        \ 'textDocument/prepareRename': 'renameProvider',
        \ 'textDocument/typeDefinition': 'typeDefinitionProvider',
        \ 'textDocument/implementation': 'implementationProvider',
        \ 'workspace/symbol': 'workspaceSymbolProvider',
        \ 'textDocument/semanticTokens': 'semanticTokensProvider',
        \ 'textDocument/documentLink': 'documentLinkProvider',
        \ 'textDocument/prepareCallHierarchy': 'callHierarchyProvider',
        \ 'callHierarchy/incomingCalls': 'callHierarchyProvider',
        \ 'callHierarchy/outgoingCalls': 'callHierarchyProvider',
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
            if !l:silent && !has_key(s:warned_caps, l:wkey)
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
    call setbufvar(l:buf, 'wplus_lsp_prev_lines', getline(1, '$'))
    let l:params = {'textDocument': {'uri': l:uri, 'languageId': a:ft, 'version': 1, 'text': join(getline(1, '$'), "\n") . "\n"}}
    call s:send(a:ft, 'textDocument/didOpen', l:params, 1)
    call wplus#lsp#request_inlay_hints()
    call wplus#lsp#request_semantic_tokens()
    call wplus#lsp#request_document_links()
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

" Compute the minimal changed range between two line lists for LSP incremental
" (range-based) didChange. Returns a dict {start, end, text, rangeLength} with
" 0-based LSP line numbers, or {} when the documents are identical.
"
"   start       first differing line (0-based)
"   end         exclusive end line in the OLD document (0-based)
"   text        replacement for old_lines[start:end] (with trailing newline)
"   rangeLength character length of the replaced old text (incl. newlines)
"
" The range always refers to the OLD document per the LSP spec, so a pure
" insertion or append yields a zero-width range (start == end).
function! s:compute_change_range(old_lines, new_lines) abort
    let l:old_len = len(a:old_lines)
    let l:new_len = len(a:new_lines)
    let l:common = min([l:old_len, l:new_len])

    " First differing line (0-based).
    let l:start = 0
    while l:start < l:common && a:old_lines[l:start] ==# a:new_lines[l:start]
        let l:start += 1
    endwhile

    " Last differing line, walking back from the end (exclusive).
    let l:old_end = l:old_len
    let l:new_end = l:new_len
    while l:old_end > l:start && l:new_end > l:start
        if a:old_lines[l:old_end - 1] ==# a:new_lines[l:new_end - 1]
            let l:old_end -= 1
            let l:new_end -= 1
        else
            break
        endif
    endwhile

    if l:start == l:old_end && l:start == l:new_end
        return {}
    endif

    " Range end is in the OLD document.
    let l:end = l:old_end

    let l:text = ''
    if l:new_end > l:start
        let l:text = join(a:new_lines[l:start : l:new_end - 1], "\n") . "\n"
    endif

    let l:rangeLength = 0
    for l:i in range(l:start, l:old_end - 1)
        let l:rangeLength += len(a:old_lines[l:i]) + 1
    endfor

    return {'start': l:start, 'end': l:end, 'text': l:text, 'rangeLength': l:rangeLength}
endfunction

function! s:do_did_change(ft, buf) abort
    call setbufvar(a:buf, 'wplus_lsp_change_timer', -1)
    let l:uri = s:get_buf_uri(a:buf)
    if empty(l:uri) | return | endif
    let l:ver = getbufvar(a:buf, 'wplus_lsp_version', 1) + 1
    call setbufvar(a:buf, 'wplus_lsp_version', l:ver)

    let l:new_lines = getbufline(a:buf, 1, '$')
    let l:prev_lines = getbufvar(a:buf, 'wplus_lsp_prev_lines', [])
    let l:change = s:compute_change_range(l:prev_lines, l:new_lines)
    call setbufvar(a:buf, 'wplus_lsp_prev_lines', l:new_lines)

    if empty(l:change)
        return
    endif

    let l:content_change = {
        \ 'range': {
        \   'start': {'line': l:change.start, 'character': 0},
        \   'end':   {'line': l:change.end,   'character': 0},
        \ },
        \ 'rangeLength': l:change.rangeLength,
        \ 'text': l:change.text,
        \ }
    let l:params = {'textDocument': {'uri': l:uri, 'version': l:ver}, 'contentChanges': [l:content_change]}
    call s:send(a:ft, 'textDocument/didChange', l:params, 1)
endfunction

function! s:did_save(ft) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    call s:send(a:ft, 'textDocument/didSave', {'textDocument': {'uri': l:uri}}, 1)
    call wplus#lsp#request_inlay_hints()
    call wplus#lsp#request_semantic_tokens()
    call wplus#lsp#request_document_links()
endfunction

function! s:job_running(job) abort
    return type(a:job) == v:t_job && job_status(a:job) ==# 'run'
endfunction

function! s:project_root() abort
    let l:root = exists('*wplus#root#find_root') ? wplus#root#find_root() : ''
    return empty(l:root) ? getcwd() : resolve(fnamemodify(l:root, ':p'))
endfunction

" Resolve the server command list for a filetype at a given project root.
" Supports three shapes for g:wplus_lsp_servers[ft]:
"   ['cmd', ...]                          plain command list
"   {'cmd': [...], 'root': '/proj'}       dict, optionally scoped to a root
"   [{'root': '/a', 'cmd': [...]}, ...]   list of dicts; first matching root
"                                          (or first without a root) wins
" Returns [] when nothing applies to the current root.
function! s:resolve_server_config(ft, root) abort
    let l:configured = get(g:wplus_lsp_servers, a:ft, [])
    if type(l:configured) == v:t_dict
        let l:root = get(l:configured, 'root', '')
        if !empty(l:root) && l:root !=# a:root
            return []
        endif
        return get(l:configured, 'cmd', [])
    elseif type(l:configured) == v:t_list
        " A plain command list (all strings) is returned as-is.
        if !empty(l:configured) && type(l:configured[0]) != v:t_dict
            return l:configured
        endif
        for l:cand in l:configured
            if type(l:cand) == v:t_dict
                let l:root = get(l:cand, 'root', '')
                if empty(l:root) || l:root ==# a:root
                    return get(l:cand, 'cmd', [])
                endif
            endif
        endfor
        return []
    endif
    return l:configured
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
    let l:cmd = s:resolve_server_config(a:ft, l:root)
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
        \   'completion': {'completionItem': {'snippetSupport': v:true, 'documentationFormat': ['plaintext', 'markdown']}},
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
    let l:tag       = a:0 > 2 ? a:3 : ''

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
            \ 'tag': l:tag,
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
        if get(l:req, 'tag', '') ==# 'peek'
            call s:peek_definition(a:result)
        else
            call s:goto_location(a:result)
        endif
    elseif a:method ==# 'textDocument/typeDefinition' || a:method ==# 'textDocument/implementation'
        call s:goto_location(a:result)
    elseif a:method ==# 'textDocument/hover'
        call s:show_hover(a:result)
    elseif a:method ==# 'textDocument/references'
        call s:show_references(a:result)
    elseif a:method ==# 'textDocument/completion'
        call s:show_completion(a:result, l:req)
    elseif a:method ==# 'textDocument/rename'
        call s:preview_rename(a:result)
    elseif a:method ==# 'textDocument/prepareRename'
        call s:on_prepare_rename(a:ft, a:result)
    elseif a:method ==# 'textDocument/codeAction'
        if get(l:req, 'tag', '') ==# 'organize_imports'
            call s:execute_organize_imports(a:result)
        else
            call s:show_code_actions(a:result)
        endif
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
    elseif a:method ==# 'workspace/symbol'
        call s:show_workspace_symbols(a:result)
    elseif a:method ==# 'textDocument/semanticTokens/full'
        call s:show_semantic_tokens(a:result)
    elseif a:method ==# 'textDocument/documentLink'
        call s:store_document_links(a:result)
    elseif a:method ==# 'textDocument/prepareCallHierarchy'
        call s:on_prepare_call_hierarchy(get(l:req, 'tag', 'incoming'), a:result)
    elseif a:method ==# 'callHierarchy/incomingCalls'
        call s:show_call_hierarchy(a:result, 'incoming')
    elseif a:method ==# 'callHierarchy/outgoingCalls'
        call s:show_call_hierarchy(a:result, 'outgoing')
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
    " Inlay hints are optional; do not warn on automatic refresh when the
    " server omitted textDocument/inlayHint from its capabilities.
    if !s:supports(l:ft, 'textDocument/inlayHint', 1) | return | endif
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

" Peek definition: show the definition source in a popup without navigating.
function! wplus#lsp#peek_definition() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    call s:send(l:ft, 'textDocument/definition', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}}, 0, 1, 'peek')
endfunction

function! s:peek_definition(result) abort
    if empty(a:result) | return | endif
    let l:loc = type(a:result) == v:t_list ? a:result[0] : a:result
    let l:uri = get(l:loc, 'uri', get(l:loc, 'targetUri', ''))
    let l:range = get(l:loc, 'range', get(l:loc, 'targetSelectionRange', {}))
    if empty(l:uri) || empty(l:range) | return | endif
    let l:path = s:decode_uri_path(l:uri)
    let l:lines = filereadable(l:path) ? readfile(l:path) : []
    if empty(l:lines) | return | endif
    let l:sl = l:range.start.line + 1
    let l:el = min([l:range.end.line + 1, len(l:lines)])
    let l:start = max([1, l:sl - 3])
    let l:end = min([len(l:lines), l:el + 3])
    let l:content = []
    for l:i in range(l:start, l:end)
        let l:marker = l:i >= l:sl && l:i <= l:el ? '▸ ' : '  '
        call add(l:content, printf('%s%4d %s', l:marker, l:i, l:lines[l:i - 1]))
    endfor
    call popup_create(l:content, wplus#util#popup_options({
        \ 'line': 'cursor-1',
        \ 'col': 'cursor',
        \ 'moved': 'any',
        \ 'title': ' ' . fnamemodify(l:path, ':t') . ':' . l:sl . ' ',
        \ }))
endfunction

" List all LSP diagnostics across loaded buffers in the quickfix list.
function! wplus#lsp#problems() abort
    let l:qf = []
    for l:buf in getbufinfo({'buflisted': 1})
        let l:diags = getbufvar(l:buf.bufnr, 'wplus_lsp_diags', {})
        if empty(l:diags) | continue | endif
        let l:name = bufname(l:buf.bufnr)
        for [l:lnum, l:list] in items(l:diags)
            for l:d in l:list
                call add(l:qf, {
                    \ 'filename': l:name,
                    \ 'lnum': str2nr(l:lnum),
                    \ 'col': get(l:d, 'col', 1),
                    \ 'text': l:d.msg,
                    \ 'type': l:d.sev == 1 ? 'E' : 'W',
                    \ })
            endfor
        endfor
    endfor
    if empty(l:qf)
        call wplus#util#info_msg('lsp', 'No problems found')
        return
    endif
    call setqflist(l:qf)
    botright copen
endfunction

function! wplus#lsp#type_definition() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    call s:send(l:ft, 'textDocument/typeDefinition', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}}, 0, 1)
endfunction

function! wplus#lsp#implementation() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    call s:send(l:ft, 'textDocument/implementation', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}}, 0, 1)
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

function! wplus#lsp#completion(...) abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    let l:tag = a:0 > 0 ? a:1 : ''
    call s:send(l:ft, 'textDocument/completion', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}}, 0, 0, l:tag)
endfunction

" Whether auto-completion should fire for a filetype. Gated on the user config
" and the server's completionProvider capability. The popup check is applied
" at trigger time (s:do_auto_complete) because pumvisible() is only meaningful
" while actually in insert mode.
function! s:auto_complete_enabled(ft) abort
    if !get(g:, 'wplus_lsp_auto_complete', 1) | return 0 | endif
    if !has_key(s:servers, a:ft) | return 0 | endif
    return s:supports(a:ft, 'textDocument/completion', 1)
endfunction

" Debounced auto-completion trigger for TextChangedI. Restarts the timer on
" every keystroke so completion only fires once the user pauses typing.
function! s:cancel_auto_complete_timer() abort
    if s:auto_complete_timer != -1
        silent! call timer_stop(s:auto_complete_timer)
        let s:auto_complete_timer = -1
    endif
endfunction

function! s:on_insert_enter() abort
    call s:cancel_auto_complete_timer()
    let b:wplus_lsp_insert_enter_tick = b:changedtick
endfunction

function! s:insert_changed(buf) abort
    if bufnr('%') != a:buf || !bufloaded(a:buf) | return 0 | endif
    return getbufvar(a:buf, 'changedtick', -1) != getbufvar(a:buf, 'wplus_lsp_insert_enter_tick', -2)
endfunction

function! s:completion_input_available() abort
    let l:before = strpart(getline('.'), 0, col('.') - 1)
    return !empty(l:before) && l:before =~# '\S$'
endfunction

function! s:auto_completion_trigger_available(ft) abort
    if !s:completion_input_available() || !has_key(s:servers, a:ft) | return 0 | endif
    let l:before = strpart(getline('.'), 0, col('.') - 1)
    let l:provider = get(get(s:servers[a:ft], 'caps', {}), 'completionProvider', {})
    if type(l:provider) != v:t_dict | return 0 | endif
    let l:triggers = get(l:provider, 'triggerCharacters', [])
    if type(l:triggers) == v:t_list && !empty(l:triggers)
        let l:last = strpart(l:before, strlen(l:before) - 1)
        if index(l:triggers, l:last) >= 0
            return 1
        endif
    endif

    " Most language servers provide useful global symbols even when they do
    " not declare a punctuation trigger. Requiring a short identifier avoids
    " a popup on the first character while keeping completion IDE-like.
    let l:token = matchstr(l:before, '\k\+$')
    return strlen(l:token) >= max([1, get(g:, 'wplus_lsp_complete_min_chars', 2)])
endfunction

function! s:trigger_auto_complete(ft, buf) abort
    " Always cancel the previous timer first. A deletion or whitespace input
    " must not leave a timer armed from an earlier completion prefix.
    call s:cancel_auto_complete_timer()
    if !s:auto_complete_enabled(a:ft) || !s:insert_changed(a:buf) || !s:auto_completion_trigger_available(a:ft) | return | endif
    let s:auto_complete_timer = timer_start(g:wplus_lsp_complete_delay, {-> s:do_auto_complete(a:ft, a:buf)})
endfunction

function! s:do_auto_complete(ft, buf) abort
    let s:auto_complete_timer = -1
    if !s:auto_complete_enabled(a:ft) || mode() !~# '^i' | return | endif
    if !s:insert_changed(a:buf) || !s:auto_completion_trigger_available(a:ft) | return | endif
    " Never interrupt an already-open completion menu.
    if pumvisible() | return | endif
    " Only complete while the triggering buffer is still the current one.
    if bufnr('%') != a:buf || !bufloaded(a:buf) | return | endif
    call wplus#lsp#completion('auto')
endfunction

function! wplus#lsp#rename() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    if s:supports(l:ft, 'textDocument/prepareRename')
        " Validate the symbol is renameable before prompting.
        call s:send(l:ft, 'textDocument/prepareRename', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}}, 0, 1)
    else
        call s:do_rename(l:ft, l:uri, l:pos)
    endif
endfunction

function! s:do_rename(ft, uri, pos) abort
    let l:word = expand('<cword>')
    let l:new_name = input('New name: ', l:word)
    if empty(l:new_name) || l:new_name ==# l:word | return | endif
    call s:send(a:ft, 'textDocument/rename', {'textDocument': {'uri': a:uri}, 'position': {'line': a:pos[1] - 1, 'character': a:pos[2] - 1}, 'newName': l:new_name}, 0, 1)
endfunction

function! s:prepare_rename_valid(result) abort
    if type(a:result) != v:t_dict | return 0 | endif
    return has_key(a:result, 'range') || has_key(a:result, 'placeholder')
endfunction

function! s:on_prepare_rename(ft, result) abort
    if !s:prepare_rename_valid(a:result)
        call wplus#util#warn_msg('lsp', 'symbol is not renameable at cursor')
        return
    endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    let l:pos = getcurpos()
    call s:do_rename(a:ft, l:uri, l:pos)
endfunction

" Build human-readable preview lines for a workspace edit (rename result).
function! s:edit_preview_lines(path, edits) abort
    let l:lines = []
    for l:e in a:edits
        let l:lnum = l:e.range.start.line + 1
        let l:col = l:e.range.start.character + 1
        call add(l:lines, printf('%s:%d:%d  →  %s', a:path, l:lnum, l:col, l:e.newText))
    endfor
    return l:lines
endfunction

function! s:rename_preview_lines(edit) abort
    let l:lines = []
    if has_key(a:edit, 'documentChanges')
        for l:change in a:edit.documentChanges
            if has_key(l:change, 'textDocument')
                call extend(l:lines, s:edit_preview_lines(s:decode_uri_path(l:change.textDocument.uri), l:change.edits))
            endif
        endfor
    elseif has_key(a:edit, 'changes')
        for [l:uri, l:edits] in items(a:edit.changes)
            call extend(l:lines, s:edit_preview_lines(s:decode_uri_path(l:uri), l:edits))
        endfor
    endif
    return l:lines
endfunction

" Show a preview of the rename edit and apply only on confirmation.
function! s:preview_rename(edit) abort
    let l:lines = s:rename_preview_lines(a:edit)
    if empty(l:lines)
        call s:apply_workspace_edit(a:edit)
        return
    endif
    let l:options = ['Apply'] + l:lines + ['Cancel']
    call popup_menu(l:options, {
        \ 'callback': {id, idx -> idx == 1 ? s:apply_workspace_edit(a:edit) : 0},
        \ 'title': ' Rename Preview ',
        \ })
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

" Request organize-imports over the whole document and apply it directly.
function! wplus#lsp#organize_imports() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:params = {
        \ 'textDocument': {'uri': l:uri},
        \ 'range': {'start': {'line': 0, 'character': 0}, 'end': {'line': line('$'), 'character': 0}},
        \ 'context': {'diagnostics': [], 'only': ['source.organizeImports']},
        \ }
    call s:send(l:ft, 'textDocument/codeAction', l:params, 0, 1, 'organize_imports')
endfunction

" Pick the organizeImports action, falling back to the first action.
function! s:find_organize_imports_action(result) abort
    if empty(a:result) | return {} | endif
    for l:a in a:result
        if type(l:a) == v:t_dict && get(l:a, 'kind', '') =~# 'source.organizeImports'
            return l:a
        endif
    endfor
    return type(a:result[0]) == v:t_dict ? a:result[0] : {}
endfunction

function! s:execute_organize_imports(result) abort
    let l:action = s:find_organize_imports_action(a:result)
    if !empty(l:action)
        call s:execute_code_action(l:action)
    endif
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

function! wplus#lsp#workspace_symbols(query) abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    if !s:supports(l:ft, 'workspace/symbol') | return | endif
    call s:send(l:ft, 'workspace/symbol', {'query': a:query}, 0, 1)
endfunction

function! s:workspace_symbols_to_qf(result) abort
    let l:qf = []
    for l:sym in a:result
        let l:loc = get(l:sym, 'location', {})
        let l:uri = get(l:loc, 'uri', '')
        let l:range = get(l:loc, 'range', {})
        if empty(l:uri) || empty(l:range) | continue | endif
        call add(l:qf, {
            \ 'filename': s:decode_uri_path(l:uri),
            \ 'lnum': l:range.start.line + 1,
            \ 'col': l:range.start.character + 1,
            \ 'text': get(l:sym, 'name', ''),
            \ })
    endfor
    return l:qf
endfunction

function! s:show_workspace_symbols(result) abort
    if empty(a:result) | return | endif
    let l:qf = s:workspace_symbols_to_qf(a:result)
    if empty(l:qf) | return | endif
    call setqflist(l:qf)
    botright copen
endfunction

" ── Semantic tokens ─────────────────────────────────────────────────────────

" Decode the flat delta-encoded LSP semantic token array into a list of
" {lnum, col, length, type, modifiers} with 1-based lnum/col.
function! s:decode_semantic_tokens(data) abort
    let l:tokens = []
    let l:prev_line = 0
    let l:prev_start = 0
    let l:i = 0
    let l:len = len(a:data)
    while l:i + 4 < l:len
        let l:delta_line = a:data[l:i]
        let l:delta_start = a:data[l:i + 1]
        let l:prev_line += l:delta_line
        if l:delta_line == 0
            let l:prev_start += l:delta_start
        else
            let l:prev_start = l:delta_start
        endif
        call add(l:tokens, {
            \ 'lnum': l:prev_line + 1,
            \ 'col': l:prev_start + 1,
            \ 'length': a:data[l:i + 2],
            \ 'type': a:data[l:i + 3],
            \ 'modifiers': a:data[l:i + 4],
            \ })
        let l:i += 5
    endwhile
    return l:tokens
endfunction

" Get (creating if needed) a textprop type that highlights with a:group.
function! s:semantic_prop_type(group) abort
    let l:name = 'WplusSemantic' . substitute(a:group, '\W', '', 'g')
    if empty(prop_type_get(l:name))
        silent! call prop_type_add(l:name, {'highlight': a:group})
    endif
    return l:name
endfunction

function! s:show_semantic_tokens(result) abort
    if !has('textprop') | return | endif
    let l:bufnr = bufnr('%')
    for l:pt in keys(s:semantic_prop_types)
        silent! call prop_remove({'type': l:pt, 'bufnr': l:bufnr, 'all': v:true})
    endfor
    let l:data = type(a:result) == v:t_dict ? get(a:result, 'data', []) : a:result
    let l:tokens = s:decode_semantic_tokens(l:data)
    for l:t in l:tokens
        let l:group = get(s:token_type_hl, l:t.type, 'Identifier')
        let l:pt = s:semantic_prop_type(l:group)
        let s:semantic_prop_types[l:pt] = 1
        silent! call prop_add(l:t.lnum, l:t.col, {
            \ 'bufnr': l:bufnr,
            \ 'length': l:t.length,
            \ 'type': l:pt,
            \ })
    endfor
endfunction

function! wplus#lsp#request_semantic_tokens() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    if !s:supports(l:ft, 'textDocument/semanticTokens', 1) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    call s:send(l:ft, 'textDocument/semanticTokens/full', {'textDocument': {'uri': l:uri}})
endfunction

" ── Document links ─────────────────────────────────────────────────────────

function! wplus#lsp#request_document_links() abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    if !s:supports(l:ft, 'textDocument/documentLink', 1) | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    call s:send(l:ft, 'textDocument/documentLink', {'textDocument': {'uri': l:uri}})
endfunction

function! s:store_document_links(result) abort
    call setbufvar(bufnr('%'), 'wplus_lsp_document_links', a:result)
endfunction

" Find the document link whose range contains (lnum, col), 1-based.
function! s:find_document_link_at(links, lnum, col) abort
    for l:link in a:links
        let l:range = get(l:link, 'range', {})
        if empty(l:range) | continue | endif
        let l:sl = l:range.start.line + 1
        let l:sc = l:range.start.character + 1
        let l:el = l:range.end.line + 1
        let l:ec = l:range.end.character + 1
        if a:lnum < l:sl || a:lnum > l:el | continue | endif
        if a:lnum == l:sl && a:col < l:sc | continue | endif
        if a:lnum == l:el && a:col > l:ec | continue | endif
        return l:link
    endfor
    return {}
endfunction

function! s:open_link_target(target) abort
    if a:target =~# '^file://'
        execute 'edit ' . fnameescape(s:decode_uri_path(a:target))
    elseif a:target =~# '^https\?://'
        if exists('*netrw#BrowseX')
            call netrw#BrowseX(a:target, 0)
        else
            call wplus#util#warn_msg('lsp', 'no browser available to open ' . a:target)
        endif
    else
        call wplus#util#warn_msg('lsp', 'unsupported link target: ' . a:target)
    endif
endfunction

function! wplus#lsp#open_document_link() abort
    let l:links = get(b:, 'wplus_lsp_document_links', [])
    let l:link = s:find_document_link_at(l:links, line('.'), col('.'))
    if empty(l:link)
        call wplus#util#info_msg('lsp', 'no document link at cursor')
        return
    endif
    call s:open_link_target(get(l:link, 'target', ''))
endfunction

" ── Call hierarchy ────────────────────────────────────────────────────────

" Request call hierarchy for the symbol under the cursor. a:mode is
" 'incoming' (who calls this) or 'outgoing' (what this calls).
function! wplus#lsp#call_hierarchy(mode) abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    if !s:supports(l:ft, 'textDocument/prepareCallHierarchy') | return | endif
    let l:uri = s:get_buf_uri(bufnr('%'))
    if empty(l:uri) | return | endif
    let l:pos = getcurpos()
    call s:send(l:ft, 'textDocument/prepareCallHierarchy', {'textDocument': {'uri': l:uri}, 'position': {'line': l:pos[1] - 1, 'character': l:pos[2] - 1}}, 0, 1, a:mode)
endfunction

function! s:on_prepare_call_hierarchy(mode, result) abort
    if empty(a:result) | return | endif
    let l:item = type(a:result) == v:t_list ? a:result[0] : a:result
    if type(l:item) != v:t_dict | return | endif
    let l:ft = &filetype
    let l:method = a:mode ==# 'outgoing' ? 'callHierarchy/outgoingCalls' : 'callHierarchy/incomingCalls'
    call s:send(l:ft, l:method, {'item': l:item}, 0, 1, a:mode)
endfunction

" Incoming calls: navigate to the call site (first fromRange).
function! s:incoming_calls_to_qf(result) abort
    let l:qf = []
    for l:call in a:result
        let l:from = get(l:call, 'from', {})
        let l:ranges = get(l:call, 'fromRanges', [])
        if empty(l:from) || empty(l:ranges) | continue | endif
        let l:r = l:ranges[0]
        call add(l:qf, {
            \ 'filename': s:decode_uri_path(get(l:from, 'uri', '')),
            \ 'lnum': l:r.start.line + 1,
            \ 'col': l:r.start.character + 1,
            \ 'text': get(l:from, 'name', ''),
            \ })
    endfor
    return l:qf
endfunction

" Outgoing calls: navigate to the callee definition (selectionRange).
function! s:outgoing_calls_to_qf(result) abort
    let l:qf = []
    for l:call in a:result
        let l:to = get(l:call, 'to', {})
        if empty(l:to) | continue | endif
        let l:sel = get(l:to, 'selectionRange', {})
        if empty(l:sel) | continue | endif
        call add(l:qf, {
            \ 'filename': s:decode_uri_path(get(l:to, 'uri', '')),
            \ 'lnum': l:sel.start.line + 1,
            \ 'col': l:sel.start.character + 1,
            \ 'text': get(l:to, 'name', ''),
            \ })
    endfor
    return l:qf
endfunction

function! s:show_call_hierarchy(result, mode) abort
    let l:qf = a:mode ==# 'outgoing' ? s:outgoing_calls_to_qf(a:result) : s:incoming_calls_to_qf(a:result)
    if empty(l:qf)
        call wplus#util#info_msg('lsp', 'No ' . a:mode . ' calls found')
        return
    endif
    call setqflist(l:qf)
    botright copen
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

function! s:completion_context_valid(req) abort
    if type(a:req) != v:t_dict || mode() !~# '^i' | return 0 | endif
    let l:buf = get(a:req, 'bufnr', -1)
    let l:uri = get(a:req, 'uri', '')
    if l:buf <= 0 || bufnr('%') != l:buf || !bufloaded(l:buf) || empty(l:uri)
        return 0
    endif
    if s:get_buf_uri(l:buf) !=# l:uri
        return 0
    endif
    if getbufvar(l:buf, 'changedtick', -1) != get(a:req, 'changedtick', -2)
        return 0
    endif
    if line('.') != get(a:req, 'lnum', -1) || col('.') != get(a:req, 'col', -1)
        return 0
    endif
    if get(a:req, 'tag', '') ==# 'auto' && !s:completion_input_available()
        return 0
    endif
    return !pumvisible()
endfunction

function! s:completion_item_text(item) abort
    if type(a:item) != v:t_dict | return '' | endif
    let l:edit = get(a:item, 'textEdit', {})
    if type(l:edit) == v:t_dict && has_key(l:edit, 'newText')
        return l:edit.newText
    endif
    return get(a:item, 'insertText', get(a:item, 'label', ''))
endfunction

" Return the byte-based Vim column for an LSP UTF-16 character offset.
" ASCII source is the common case, but this prevents completion from starting
" in the middle of a multibyte identifier.
function! s:lsp_character_to_col(text, character) abort
    let l:units = 0
    let l:bytes = 0
    for l:char in split(a:text, '\zs')
        if l:units >= a:character | break | endif
        let l:units += char2nr(l:char) > 0xffff ? 2 : 1
        let l:bytes += strlen(l:char)
    endfor
    return l:bytes + 1
endfunction

function! s:completion_start(items) abort
    let l:line_text = getline('.')
    let l:fallback = col('.') - 1
    while l:fallback > 0 && strpart(l:line_text, l:fallback - 1, 1) =~# '\k'
        let l:fallback -= 1
    endwhile
    let l:start = l:fallback
    let l:has_edit = 0
    for l:item in a:items
        let l:edit = type(l:item) == v:t_dict ? get(l:item, 'textEdit', {}) : {}
        if type(l:edit) != v:t_dict | continue | endif
        let l:range = get(l:edit, 'range', get(l:edit, 'insert', {}))
        if type(l:range) != v:t_dict | continue | endif
        let l:position = get(l:range, 'start', {})
        if type(l:position) != v:t_dict || !has_key(l:position, 'character') | continue | endif
        let l:candidate = s:lsp_character_to_col(l:line_text, l:position.character) - 1
        let l:start = l:has_edit ? min([l:start, l:candidate]) : l:candidate
        let l:has_edit = 1
    endfor
    return max([0, l:start])
endfunction

function! s:show_completion(result, req) abort
    if empty(a:result) || !s:completion_context_valid(a:req) | return | endif
    if exists('*wplus#ai#suggest#has_suggestion') && wplus#ai#suggest#has_suggestion()
        return
    endif
    let l:items = type(a:result) == v:t_list ? a:result : get(a:result, 'items', [])
    if empty(l:items) | return | endif
    call setbufvar(bufnr('%'), 'wplus_lsp_completion_auto', get(a:req, 'tag', '') ==# 'auto')
    call setbufvar(bufnr('%'), 'wplus_lsp_completion_tick', b:changedtick)
    " Keep the raw items so CompleteDone can re-parse snippet insertText.
    call setbufvar(bufnr('%'), 'wplus_lsp_completion_items', l:items)
    let l:completion_start = s:completion_start(l:items)
    call setbufvar(bufnr('%'), 'wplus_lsp_completion_start', l:completion_start)
    call setbufvar(bufnr('%'), 'wplus_lsp_completion_start_line', line('.'))
    call setbufvar(bufnr('%'), 'wplus_lsp_completion_start_col', l:completion_start)
    let l:matches = []
    let l:kind_map = {1: 'v', 2: 'f', 3: 'm', 4: 'f', 5: 'f', 6: 'c', 7: 'i', 8: 's', 9: 'm', 10: 'p', 11: 'u', 12: 'e', 13: 'k', 14: 's', 15: 's'}
    let l:item_index = 0
    for l:item in l:items
        let l:word = s:completion_item_text(l:item)
        if empty(l:word)
            let l:item_index += 1
            continue
        endif
        call add(l:matches, {'word': l:word, 'abbr': get(l:item, 'label', l:word), 'kind': get(l:kind_map, get(l:item, 'kind', 0), 't'), 'menu': get(l:item, 'detail', ''), 'user_data': string(l:item_index)})
        let l:item_index += 1
    endfor
    if empty(l:matches) | return | endif
    call complete(get(b:, 'wplus_lsp_completion_start', col('.') - 1) + 1, l:matches)
endfunction

" ── Snippet support ─────────────────────────────────────────────────────────

" Parse an LSP snippet string into an ordered list of segments:
"   {'type': 'text', 'text': '...'}
"   {'type': 'stop', 'index': N, 'placeholder': '...'}
" Handles $N, ${N}, ${N:placeholder}, $0, and \${ escapes.
function! s:parse_snippet(snippet) abort
    let l:segs = []
    let l:text = ''
    let l:i = 0
    let l:len = len(a:snippet)
    while l:i < l:len
        let l:c = a:snippet[l:i]
        if l:c ==# '\' && l:i + 1 < l:len && a:snippet[l:i + 1] ==# '$'
            let l:text .= '$'
            let l:i += 2
            continue
        endif
        if l:c ==# '$'
            if !empty(l:text)
                call add(l:segs, {'type': 'text', 'text': l:text})
                let l:text = ''
            endif
            let l:j = l:i + 1
            if l:j < l:len && a:snippet[l:j] ==# '{'
                let l:close = stridx(a:snippet, '}', l:j)
                if l:close == -1
                    let l:text .= a:snippet[l:i :]
                    break
                endif
                let l:inner = a:snippet[l:j + 1 : l:close - 1]
                let l:colon = stridx(l:inner, ':')
                if l:colon == -1
                    call add(l:segs, {'type': 'stop', 'index': str2nr(l:inner), 'placeholder': ''})
                else
                    call add(l:segs, {'type': 'stop', 'index': str2nr(l:inner[: l:colon - 1]), 'placeholder': l:inner[l:colon + 1 :]})
                endif
                let l:i = l:close + 1
            else
                while l:j < l:len && a:snippet[l:j] =~# '\d'
                    let l:j += 1
                endwhile
                if l:j > l:i + 1
                    call add(l:segs, {'type': 'stop', 'index': str2nr(a:snippet[l:i + 1 : l:j - 1]), 'placeholder': ''})
                    let l:i = l:j
                else
                    let l:text .= '$'
                    let l:i += 1
                endif
            endif
            continue
        endif
        let l:text .= l:c
        let l:i += 1
    endwhile
    if !empty(l:text)
        call add(l:segs, {'type': 'text', 'text': l:text})
    endif
    return l:segs
endfunction

" Insert text at (lnum, col), handling embedded newlines.
function! s:insert_text_at(lnum, col, text) abort
    let l:lines = split(a:text, "\n", 1)
    let l:cur = getline(a:lnum)
    let l:prefix = a:col > 1 ? l:cur[: a:col - 2] : ''
    let l:suffix = a:col <= len(l:cur) ? l:cur[a:col - 1 :] : ''
    if len(l:lines) == 1
        call setline(a:lnum, l:prefix . l:lines[0] . l:suffix)
    else
        call setline(a:lnum, l:prefix . l:lines[0])
        call append(a:lnum, l:lines[1 : -2] + [l:lines[-1] . l:suffix])
    endif
endfunction

" Advance a (lnum, col) position past a chunk of text.
function! s:advance_pos(lnum, col, text) abort
    let l:lines = split(a:text, "\n", 1)
    if len(l:lines) == 1
        return [a:lnum, a:col + len(l:lines[0])]
    endif
    return [a:lnum + len(l:lines) - 1, len(l:lines[-1]) + 1]
endfunction

" Insert parsed snippet segments at the current cursor, returning the list of
" tab stops (each {index, lnum, col, placeholder}).
function! s:insert_snippet(segs) abort
    let l:stops = []
    let l:lnum = line('.')
    let l:col = col('.')
    for l:seg in a:segs
        if l:seg.type ==# 'text'
            call s:insert_text_at(l:lnum, l:col, l:seg.text)
            let [l:lnum, l:col] = s:advance_pos(l:lnum, l:col, l:seg.text)
        else
            call add(l:stops, {'index': l:seg.index, 'lnum': l:lnum, 'col': l:col, 'placeholder': l:seg.placeholder})
            if !empty(l:seg.placeholder)
                call s:insert_text_at(l:lnum, l:col, l:seg.placeholder)
                let l:col += len(l:seg.placeholder)
            endif
        endif
    endfor
    return l:stops
endfunction

" Move the cursor to a stop, selecting its placeholder so typing replaces it.
function! s:snippet_goto(stop) abort
    call cursor(a:stop.lnum, a:stop.col)
    if !empty(a:stop.placeholder)
        " Visual mode already selects the character under the cursor. Move
        " only len-1 times; len l used to include one character after the
        " placeholder and made typing replace surrounding code.
        let l:count = strchars(a:stop.placeholder)
        if l:count > 1
            execute 'normal! v' . (l:count - 1) . 'l'
        else
            normal! v
        endif
    endif
endfunction

function! s:snippet_clear() abort
    silent! unlet b:wplus_lsp_snippet_stops
    silent! unlet b:wplus_lsp_snippet_pos
    silent! unlet b:wplus_lsp_snippet_active
    silent! execute 'iunmap <buffer> <Tab>'
    silent! execute 'iunmap <buffer> <S-Tab>'
endfunction

function! wplus#lsp#snippet_tab() abort
    if !get(b:, 'wplus_lsp_snippet_active', 0) | return "\<Tab>" | endif
    let l:stops = get(b:, 'wplus_lsp_snippet_stops', [])
    let l:pos = get(b:, 'wplus_lsp_snippet_pos', 0)
    if l:pos >= len(l:stops) - 1
        call s:snippet_clear()
        return "\<Tab>"
    endif
    let l:pos += 1
    call setbufvar(bufnr('%'), 'wplus_lsp_snippet_pos', l:pos)
    call s:snippet_goto(l:stops[l:pos])
    return ''
endfunction

function! wplus#lsp#snippet_shift_tab() abort
    if !get(b:, 'wplus_lsp_snippet_active', 0) | return "\<S-Tab>" | endif
    let l:stops = get(b:, 'wplus_lsp_snippet_stops', [])
    let l:pos = get(b:, 'wplus_lsp_snippet_pos', 0)
    if l:pos <= 0 | return "\<S-Tab>" | endif
    let l:pos -= 1
    call setbufvar(bufnr('%'), 'wplus_lsp_snippet_pos', l:pos)
    call s:snippet_goto(l:stops[l:pos])
    return ''
endfunction

" Replace the just-inserted completion word with a parsed snippet and arm
" tab-stop navigation. Called from CompleteDone.
function! s:apply_snippet(snippet) abort
    let l:segs = s:parse_snippet(a:snippet)
    let l:word = get(v:completed_item, 'word', '')
    let l:lnum = get(b:, 'wplus_lsp_completion_start_line', line('.'))
    let l:col = get(b:, 'wplus_lsp_completion_start_col', 0) + 1
    if empty(l:word)
        let l:lnum = line('.')
        let l:col = max([1, col('.') - strlen(a:snippet)])
    else
        " CompleteDone may leave a multiline snippet on several lines. Remove
        " the exact inserted range, not just bytes on the final line.
        let l:word_lines = split(l:word, "\n", 1)
        let l:end_line = l:lnum + len(l:word_lines) - 1
        let l:end_col = len(l:word_lines) == 1 ? l:col + strlen(l:word_lines[0]) : strlen(l:word_lines[-1]) + 1
        let l:start_text = getline(l:lnum)
        let l:end_text = getline(l:end_line)
        let l:prefix = strpart(l:start_text, 0, l:col - 1)
        let l:suffix = strpart(l:end_text, l:end_col - 1)
        if l:end_line > l:lnum
            call deletebufline(bufnr('%'), l:lnum + 1, l:end_line)
        endif
        call setline(l:lnum, l:prefix . l:suffix)
        call cursor(l:lnum, l:col)
    endif
    let l:stops = s:insert_snippet(l:segs)
    if empty(l:stops)
        return
    endif
    " Order stops by index, with the final $0 stop last.
    call sort(l:stops, {a, b -> a.index == 0 ? 1 : (b.index == 0 ? -1 : a.index - b.index)})
    call setbufvar(bufnr('%'), 'wplus_lsp_snippet_stops', l:stops)
    call setbufvar(bufnr('%'), 'wplus_lsp_snippet_pos', 0)
    call setbufvar(bufnr('%'), 'wplus_lsp_snippet_active', 1)
    inoremap <buffer> <expr> <Tab>   wplus#lsp#snippet_tab()
    inoremap <buffer> <expr> <S-Tab> wplus#lsp#snippet_shift_tab()
    call s:snippet_goto(l:stops[0])
endfunction

function! s:on_complete_done() abort
    let l:item = get(v:, 'completed_item', {})
    let l:items = get(b:, 'wplus_lsp_completion_items', [])
    if empty(l:item) || empty(l:items)
        silent! unlet b:wplus_lsp_completion_items b:wplus_lsp_completion_start b:wplus_lsp_completion_start_line b:wplus_lsp_completion_start_col
        return
    endif
    let l:word = get(l:item, 'word', '')
    let l:raw = {}
    let l:index = get(l:item, 'user_data', '')
    if type(l:index) == v:t_string && l:index =~# '^\d\+$'
        let l:raw = get(l:items, str2nr(l:index), {})
    endif
    if empty(l:raw)
        for l:candidate in l:items
            if s:completion_item_text(l:candidate) ==# l:word
                let l:raw = l:candidate
                break
            endif
        endfor
    endif
    if !empty(l:raw)
        let l:raw_word = s:completion_item_text(l:raw)
        if get(l:raw, 'insertTextFormat', 1) == 2 && !empty(l:raw_word)
            call s:apply_snippet(l:raw_word)
        endif
        let l:additional = get(l:raw, 'additionalTextEdits', [])
        if type(l:additional) == v:t_list && !empty(l:additional)
            let l:path = s:decode_uri_path(s:get_buf_uri(bufnr('%')))
            call s:apply_text_edits(l:path, l:additional)
        endif
    endif
    silent! unlet b:wplus_lsp_completion_items b:wplus_lsp_completion_start b:wplus_lsp_completion_start_line b:wplus_lsp_completion_start_col
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

function! wplus#lsp#_test_compute_change_range(old_lines, new_lines) abort
    return s:compute_change_range(a:old_lines, a:new_lines)
endfunction

function! wplus#lsp#_test_auto_complete_enabled(ft) abort
    return s:auto_complete_enabled(a:ft)
endfunction

function! wplus#lsp#_test_completion_context_valid(req) abort
    return s:completion_context_valid(a:req)
endfunction

function! wplus#lsp#_test_insert_changed(buf) abort
    return s:insert_changed(a:buf)
endfunction

function! wplus#lsp#_test_completion_input_available() abort
    return s:completion_input_available()
endfunction

function! wplus#lsp#_test_auto_completion_trigger_available(ft) abort
    return s:auto_completion_trigger_available(a:ft)
endfunction

function! wplus#lsp#_test_completion_item_text(item) abort
    return s:completion_item_text(a:item)
endfunction

function! wplus#lsp#_test_lsp_character_to_col(text, character) abort
    return s:lsp_character_to_col(a:text, a:character)
endfunction

function! wplus#lsp#_test_parse_snippet(snippet) abort
    return s:parse_snippet(a:snippet)
endfunction

function! wplus#lsp#_test_workspace_symbols_to_qf(result) abort
    return s:workspace_symbols_to_qf(a:result)
endfunction

function! wplus#lsp#_test_decode_semantic_tokens(data) abort
    return s:decode_semantic_tokens(a:data)
endfunction

function! wplus#lsp#_test_resolve_server_config(ft, root) abort
    return s:resolve_server_config(a:ft, a:root)
endfunction

function! wplus#lsp#_test_prepare_rename_valid(result) abort
    return s:prepare_rename_valid(a:result)
endfunction

function! wplus#lsp#_test_rename_preview_lines(edit) abort
    return s:rename_preview_lines(a:edit)
endfunction

function! wplus#lsp#_test_goto_location(result) abort
    call s:goto_location(a:result)
endfunction

function! wplus#lsp#_test_find_organize_imports_action(result) abort
    return s:find_organize_imports_action(a:result)
endfunction

function! wplus#lsp#_test_find_document_link_at(links, lnum, col) abort
    return s:find_document_link_at(a:links, a:lnum, a:col)
endfunction

function! wplus#lsp#_test_incoming_calls_to_qf(result) abort
    return s:incoming_calls_to_qf(a:result)
endfunction

function! wplus#lsp#_test_outgoing_calls_to_qf(result) abort
    return s:outgoing_calls_to_qf(a:result)
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
    command! WlspCompletion     call wplus#lsp#completion()
    command! WlspPeekDefinition call wplus#lsp#peek_definition()
    command! WlspProblems       call wplus#lsp#problems()
    command! WlspDefinition     call wplus#lsp#definition()
    command! WlspTypeDefinition call wplus#lsp#type_definition()
    command! WlspImplementation call wplus#lsp#implementation()
    command! WlspReferences     call wplus#lsp#references()
    command! WlspRename         call wplus#lsp#rename()
    command! WlspCodeAction     call wplus#lsp#code_action()
    command! WlspOrganizeImports call wplus#lsp#organize_imports()
    command! WlspOpenLink       call wplus#lsp#open_document_link()
    command! WlspCallHierarchy        call wplus#lsp#call_hierarchy('incoming')
    command! WlspCallHierarchyOutgoing call wplus#lsp#call_hierarchy('outgoing')
    command! WlspNextDiag       call wplus#lsp#next_diag()
    command! WlspPrevDiag       call wplus#lsp#prev_diag()
    command! WlspDiagPopup      call wplus#lsp#diag_popup()
    command! WlspSignatureHelp  call wplus#lsp#signature_help()
    command! WlspFormat         call wplus#lsp#format(0)
    command! -nargs=? WlspSymbols call wplus#lsp#workspace_symbols(<q-args> != '' ? <q-args> : input('Symbol: '))

    nnoremap <silent> K          :WlspHover<CR>
    nnoremap <silent> gd         :WlspDefinition<CR>
    nnoremap <silent> gy         :WlspTypeDefinition<CR>
    nnoremap <silent> <leader>gi :WlspImplementation<CR>
    nnoremap <silent> gr         :WlspReferences<CR>
    nnoremap <silent> <leader>rn :WlspRename<CR>
    nnoremap <silent> <leader>ca :WlspCodeAction<CR>
    nnoremap <silent> <leader>ci :WlspOrganizeImports<CR>
    nnoremap <silent> <leader>gl :WlspOpenLink<CR>
    nnoremap <silent> ]d         :WlspNextDiag<CR>
    nnoremap <silent> [d         :WlspPrevDiag<CR>
    nnoremap <silent> <leader>d  :WlspDiagPopup<CR>
    inoremap <silent> <C-s>      <C-o>:WlspSignatureHelp<CR>

    augroup wplus_lsp
        autocmd!
        autocmd FileType * call s:start_server(&filetype)
        autocmd BufReadPost * call s:did_open(&filetype)
        autocmd InsertEnter * call s:on_insert_enter()
        autocmd InsertLeave * call s:cancel_auto_complete_timer()
        autocmd InsertLeave * call s:snippet_clear()
        autocmd BufLeave * call s:snippet_clear()
        autocmd TextChanged,TextChangedI * call s:did_change(&filetype, bufnr('%'))
        autocmd TextChangedI * call s:trigger_auto_complete(&filetype, bufnr('%'))
        autocmd CompleteDone * call s:on_complete_done()
        autocmd BufWritePost * call s:did_save(&filetype)
        autocmd BufUnload * call s:did_close(expand('<abuf>'))
        autocmd VimLeavePre * call wplus#lsp#stop_all()
    augroup END
endfunction
