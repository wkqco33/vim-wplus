" wplus/lsp.vim — Minimal LSP client using Vim 9 jobs/channels

if exists('g:autoloaded_wplus_lsp') | finish | endif
let g:autoloaded_wplus_lsp = 1

let s:servers = {} " ft -> {job, channel, last_id, requests, buffer}
let g:wplus_lsp_log_enabled = get(g:, 'wplus_lsp_log_enabled', 1)
let g:wplus_lsp_signcolumn = get(g:, 'wplus_lsp_signcolumn', 'yes')

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
        autocmd FileType go,c,cpp,python call s:on_filetype_changed()
    augroup END
    nnoremap <silent> <Plug>WplusLspDefinition :call wplus#lsp#request('textDocument/definition')<CR>
    nnoremap <silent> <Plug>WplusLspHover      :call wplus#lsp#request('textDocument/hover')<CR>
    nnoremap <silent> <Plug>WplusLspReferences :call wplus#lsp#request('textDocument/references')<CR>
endfunction

function! s:on_filetype_changed() abort
    let l:ft = &filetype
    call s:ensure_signcolumn()
    call s:start_server(l:ft)
    augroup WplusLSPBuffer
        autocmd! * <buffer>
        autocmd BufWritePost <buffer> call s:did_save(&filetype)
        autocmd TextChanged,TextChangedI <buffer> call s:on_change(&filetype)
        autocmd CursorMoved,CursorHold <buffer> call s:echo_diag()
    augroup END
    nmap <buffer><silent> gd <Plug>WplusLspDefinition
    nmap <buffer><silent> K  <Plug>WplusLspHover
    nmap <buffer><silent> gr <Plug>WplusLspReferences
    inoremap <buffer><silent><expr> <Tab> pumvisible() ? "\<C-n>" : <SID>check_backspace() ? "\<Tab>" : "\<C-r>=wplus#lsp#request('textDocument/completion')\<CR>\<Ignore>"
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

function! s:get_uri(path) abort
    let l:p = fnamemodify(a:path, ':p')
    let l:p = substitute(l:p, '[^A-Za-z0-9._~/-]', '\=printf("%%%02X", char2nr(submatch(0)))', 'g')
    return 'file://' . (l:p[0] ==# '/' ? '' : '/') . l:p
endfunction

function! s:get_buf_uri(buf) abort
    let l:name = bufname(a:buf)
    return empty(l:name) ? '' : s:get_uri(l:name)
endfunction

function! s:decode_uri_path(uri) abort
    let l:path = substitute(a:uri, '\v^file:/*(localhost)?', '', '')
    let l:path = substitute(l:path, '%\(\x\x\)', '\=nr2char("0x".submatch(1))', 'g')
    return l:path[0] ==# '/' ? l:path : '/' . l:path
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
endfunction

function! s:on_change(ft) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:buf = bufnr('%')
    silent! timer_stop(getbufvar(l:buf, 'wplus_lsp_timer', -1))
    let l:timer = timer_start(500, {-> s:send_change(l:buf, a:ft)})
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
endfunction

function! s:start_server(ft) abort
    if has_key(s:servers, a:ft) && job_status(s:servers[a:ft].job) ==# 'run' | call s:did_open(a:ft) | return | endif
    let l:cmds = {'go': ['gopls'], 'c': ['clangd'], 'cpp': ['clangd'], 'python': ['pyright-langserver', '--stdio']}
    if !has_key(l:cmds, a:ft) || !executable(l:cmds[a:ft][0]) | return | endif
    let l:job = job_start(l:cmds[a:ft], {'in_mode': 'raw', 'out_mode': 'raw', 'out_cb': {c, m -> s:on_stdout(a:ft, c, m)}, 'err_cb': {c, m -> s:log(a:ft, 'STDERR', m)}})
    let s:servers[a:ft] = {'job': l:job, 'channel': job_getchannel(l:job), 'last_id': 0, 'requests': {}, 'buffer': ''}
    call s:send(a:ft, 'initialize', {'processId': getpid(), 'rootUri': s:get_uri(getcwd()), 'capabilities': {'textDocument': {'synchronization': {'didChange': 1, 'willSave': v:true, 'didSave': v:true}, 'hover': {'contentFormat': ['plaintext', 'markdown']}, 'definition': {'dynamicRegistration': v:true}, 'references': {'dynamicRegistration': v:true}, 'completion': {'completionItem': {'snippetSupport': v:false}}}}})
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
        if l:idx > 0 | let l:s.buffer = l:s.buffer[l:idx :] | let l:idx = 0 | endif
        let l:end = stridx(l:s.buffer, "\r\n\r\n")
        if l:end == -1 | break | endif
        let l:len = str2nr(l:s.buffer[16 : l:end])
        if strlen(l:s.buffer) < l:end + 4 + l:len | break | endif
        let l:body = l:s.buffer[l:end + 4 : l:end + 3 + l:len]
        let l:s.buffer = l:s.buffer[l:end + 4 + l:len :]
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
    call s:handle_request_result(a:ft, l:method, get(a:resp, 'result', {}))
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
    endif
endfunction

function! s:update_diagnostics(ft, params) abort
    call timer_start(0, {-> s:do_update_diagnostics(a:ft, a:params)})
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
    for l:diag in a:params.diagnostics
        let l:lnum = l:diag.range.start.line + 1
        if l:lnum <= 0 || l:lnum > l:last_line | continue | endif

        let l:sev = get(l:diag, 'severity', 1)
        let l:style = s:diag_style(l:sev)
        let l:counts[l:style.key] += 1

        call sign_place(0, 'WplusLspGroup', l:style.sign, l:bufnr, {'lnum': l:lnum, 'priority': 20})
        if has('textprop')
            let l:msg = '  // ' . split(l:diag.message, "\n")[0]
            silent! call prop_add(l:lnum, 0, {'bufnr': l:bufnr, 'type': l:style.type, 'text': l:msg, 'text_align': 'after'})
        endif
        if !has_key(l:diags, l:lnum) || l:sev < l:diags[l:lnum].sev
            let l:diags[l:lnum] = {'msg': l:diag.message, 'sev': l:sev}
        endif
    endfor

    call setbufvar(l:bufnr, 'wplus_lsp_diags', l:diags)
    call setbufvar(l:bufnr, 'wplus_lsp_diag_counts', l:counts)
    redrawstatus
    if bufnr('%') == l:bufnr | redraw! | call s:echo_diag() | endif
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

function! wplus#lsp#request(method) abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    let l:params = s:get_request_params(a:method)
    if empty(l:params) | return | endif
    call s:send(l:ft, a:method, l:params, 0)
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
