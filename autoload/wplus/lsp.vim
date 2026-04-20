" wplus/lsp.vim — Minimal LSP client using Vim 9 jobs/channels

if exists('g:autoloaded_wplus_lsp') | finish | endif
let g:autoloaded_wplus_lsp = 1

let s:servers = {} " ft -> {job, channel, last_id, requests, buffer}
let g:wplus_lsp_log_enabled = get(g:, 'wplus_lsp_log_enabled', 0)

function! s:log(ft, type, msg) abort
    if !g:wplus_lsp_log_enabled | return | endif
    let l:log_file = getcwd() . '/lsp.log'
    let l:time = strftime('%H:%M:%S')
    let l:line = printf('[%s][%s][%s] %s', l:time, a:ft, a:type, a:msg)
    call writefile([l:line], l:log_file, 'a')
endfunction

function! wplus#lsp#setup() abort
    if !has('job') || !has('channel') | return | endif
    
    augroup WplusLSP
        autocmd!
        autocmd FileType go,c,cpp,python call s:start_server(&filetype)
        autocmd BufReadPost,BufNewFile go,c,cpp,python call s:did_open(&filetype)
        autocmd BufWritePost go,c,cpp,python call s:did_save(&filetype)
        autocmd FileType go,c,cpp,python nmap <buffer><silent> gd <Plug>WplusLspDefinition
        autocmd FileType go,c,cpp,python nmap <buffer><silent> K  <Plug>WplusLspHover
        autocmd FileType go,c,cpp,python nmap <buffer><silent> gr <Plug>WplusLspReferences
        
        " Tab completion mapping
        autocmd FileType go,c,cpp,python inoremap <buffer><silent><expr> <Tab>
            \ pumvisible() ? "\<C-n>" :
            \ <SID>check_backspace() ? "\<Tab>" :
            \ "\<C-r>=wplus#lsp#request('textDocument/completion')\<CR>\<Ignore>"
        autocmd FileType go,c,cpp,python inoremap <buffer><silent><expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<C-h>"
    augroup END

    nnoremap <silent> <Plug>WplusLspDefinition :call wplus#lsp#request('textDocument/definition')<CR>
    nnoremap <silent> <Plug>WplusLspHover      :call wplus#lsp#request('textDocument/hover')<CR>
    nnoremap <silent> <Plug>WplusLspReferences :call wplus#lsp#request('textDocument/references')<CR>
endfunction

function! s:check_backspace() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~# '\s'
endfunction

function! s:did_save(ft) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:params = {
        \ 'textDocument': {'uri': s:get_uri(expand('%:p'))}
        \ }
    call s:send(a:ft, 'textDocument/didSave', l:params, 1)
endfunction

function! s:get_uri(path) abort
    return 'file://' . (a:path[0] ==# '/' ? '' : '/') . a:path
endfunction

function! s:did_open(ft) abort
    if !has_key(s:servers, a:ft) | return | endif
    let l:params = {
        \ 'textDocument': {
        \   'uri': s:get_uri(expand('%:p')),
        \   'languageId': a:ft,
        \   'version': 1,
        \   'text': join(getline(1, '$'), "\n") . "\n"
        \  }
        \ }
    call s:send(a:ft, 'textDocument/didOpen', l:params, 1)
endfunction

function! s:start_server(ft) abort
    if has_key(s:servers, a:ft) && job_status(s:servers[a:ft].job) ==# 'run'
        call s:did_open(a:ft)
        return
    endif

    let l:cmds = {
        \ 'go': ['gopls'],
        \ 'c': ['clangd'],
        \ 'cpp': ['clangd'],
        \ 'python': ['pyright-langserver', '--stdio']
        \ }
    
    if !has_key(l:cmds, a:ft) || !executable(l:cmds[a:ft][0]) 
        call s:log(a:ft, 'ERROR', 'Binary not found: ' . get(l:cmds, a:ft, [''])[0])
        return 
    endif

    let l:job = job_start(l:cmds[a:ft], {
        \ 'in_mode': 'raw',
        \ 'out_mode': 'raw',
        \ 'out_cb': {c, m -> s:on_stdout(a:ft, c, m)},
        \ 'err_cb': {c, m -> s:log(a:ft, 'STDERR', m)},
        \ })
    
    let s:servers[a:ft] = {
        \ 'job': l:job,
        \ 'channel': job_getchannel(l:job),
        \ 'last_id': 0,
        \ 'requests': {},
        \ 'buffer': ''
        \ }

    " Initialize with minimal capabilities
    call s:send(a:ft, 'initialize', {
        \ 'processId': getpid(),
        \ 'rootUri': s:get_uri(getcwd()),
        \ 'capabilities': {
        \   'textDocument': {
        \     'hover': {'contentFormat': ['plaintext', 'markdown']},
        \     'definition': {'dynamicRegistration': v:true},
        \     'references': {'dynamicRegistration': v:true},
        \     'synchronization': {'didSave': v:true, 'willSave': v:true}
        \   }
        \ }
        \ })
endfunction

function! s:send(ft, method, params, ...) abort
    let l:s = s:servers[a:ft]
    let l:is_notification = a:0 > 0 ? a:1 : 0
    let l:req = {'jsonrpc': '2.0', 'method': a:method, 'params': a:params}
    
    if !l:is_notification
        let l:s.last_id += 1
        let l:req.id = l:s.last_id
        let l:s.requests[l:s.last_id] = a:method
    endif
    
    let l:body = json_encode(l:req)
    let l:msg = 'Content-Length: ' . strlen(l:body) . "\r\n\r\n" . l:body
    call s:log(a:ft, 'SEND', l:body)
    call ch_sendraw(l:s.channel, l:msg)
endfunction

function! s:on_stdout(ft, channel, msg) abort
    let l:s = s:servers[a:ft]
    let l:s.buffer .= a:msg
    
    while 1
        let l:idx = stridx(l:s.buffer, "Content-Length: ")
        if l:idx == -1 | break | endif
        
        " Ensure we start at Content-Length
        if l:idx > 0 | let l:s.buffer = l:s.buffer[l:idx :] | let l:idx = 0 | endif
        
        let l:end_idx = stridx(l:s.buffer, "\r\n\r\n")
        if l:end_idx == -1 | break | endif
        
        let l:len = str2nr(l:s.buffer[16 : l:end_idx])
        let l:body_start = l:end_idx + 4
        if strlen(l:s.buffer) < l:body_start + l:len | break | endif
        
        let l:body = l:s.buffer[l:body_start : l:body_start + l:len - 1]
        let l:s.buffer = l:s.buffer[l:body_start + l:len :]
        
        call s:log(a:ft, 'RECV', l:body)
        try
            let l:resp = json_decode(l:body)
            if type(l:resp) == v:t_dict
                call s:handle_response(a:ft, l:resp)
            endif
        catch
            call s:log(a:ft, 'JSON_ERR', l:body)
        endtry
    endwhile
endfunction

function! s:handle_response(ft, resp) abort
    if !has_key(a:resp, 'id') | return | endif
    let l:id = a:resp.id
    let l:method = get(s:servers[a:ft].requests, l:id, '')
    if empty(l:method) | return | endif
    unlet s:servers[a:ft].requests[l:id]

    if has_key(a:resp, 'error')
        echohl ErrorMsg | echo "LSP Error (" . l:method . "): " . a:resp.error.message | echohl None
        return
    endif

    let l:result = get(a:resp, 'result', {})
    if l:method ==# 'initialize'
        call s:send(a:ft, 'initialized', {}, 1)
        call s:did_open(a:ft)
    elseif l:method ==# 'textDocument/definition'
        call s:goto_location(l:result)
    elseif l:method ==# 'textDocument/hover'
        call s:show_hover(l:result)
    elseif l:method ==# 'textDocument/references'
        call s:show_references(l:result)
    elseif l:method ==# 'textDocument/completion'
        call s:show_completion(l:result)
    endif
endfunction

function! s:show_completion(result) abort
    if empty(a:result) | return | endif
    let l:items = type(a:result) == v:t_list ? a:result : a:result.items
    if empty(l:items) | return | endif

    let l:matches = []
    let l:kind_map = {1: 'v', 2: 'f', 3: 'm', 4: 'f', 5: 'f', 6: 'c', 7: 'i', 8: 's', 9: 'm', 10: 'p', 11: 'u', 12: 'e', 13: 'k', 14: 's', 15: 's'}
    
    for l:item in l:items
        call add(l:matches, {
            \ 'word': get(l:item, 'insertText', l:item.label),
            \ 'abbr': l:item.label,
            \ 'kind': get(l:kind_map, get(l:item, 'kind', 0), 't'),
            \ 'menu': get(l:item, 'detail', ''),
            \ })
    endfor

    " Get the start of the word for completion
    let l:line = getline('.')
    let l:start = col('.') - 1
    while l:start > 0 && l:line[l:start - 1] =~# '\k'
        let l:start -= 1
    endwhile

    call complete(l:start + 1, l:matches)
endfunction

function! wplus#lsp#request(method) abort
    let l:ft = &filetype
    if !has_key(s:servers, l:ft) | return | endif
    
    let l:params = {
        \ 'textDocument': {'uri': s:get_uri(expand('%:p'))},
        \ 'position': {'line': line('.') - 1, 'character': col('.') - 1}
        \ }
    if a:method ==# 'textDocument/references'
        let l:params.context = {'includeDeclaration': v:true}
    endif
    call s:send(l:ft, a:method, l:params)
endfunction

function! s:goto_location(result) abort
    let l:loc = type(a:result) == v:t_list ? get(a:result, 0) : a:result
    if empty(l:loc) | return | endif
    let l:uri = type(l:loc) == v:t_dict && has_key(l:loc, 'uri') ? l:loc.uri : (has_key(l:loc, 'targetUri') ? l:loc.targetUri : '')
    if empty(l:uri) | return | endif
    let l:file = substitute(l:uri, '^file://', '', '')
    let l:range = has_key(l:loc, 'range') ? l:loc.range : l:loc.targetSelectionRange
    let l:line = l:range.start.line + 1
    execute 'edit +' . l:line . ' ' . fnameescape(l:file)
endfunction

function! s:show_hover(result) abort
    if empty(a:result) || empty(a:result.contents) | return | endif
    let l:contents = a:result.contents
    let l:text = ''

    if type(l:contents) == v:t_dict
        let l:text = l:contents.value
    elseif type(l:contents) == v:t_list
        let l:lines = []
        for l:item in l:contents
            call add(l:lines, type(l:item) == v:t_dict ? l:item.value : l:item)
        endfor
        let l:text = join(l:lines, "\n")
    else
        let l:text = l:contents
    endif
    
    if empty(l:text) | return | endif
    
    if has('popupwin')
        let l:display_lines = split(l:text, "\n")
        " Clean up formatting
        while !empty(l:display_lines) && empty(trim(l:display_lines[0])) | call remove(l:display_lines, 0) | endwhile
        while !empty(l:display_lines) && empty(trim(l:display_lines[-1])) | call remove(l:display_lines, -1) | endwhile
        if empty(l:display_lines) | return | endif

        let l:symbol = expand('<cword>')
        let l:winid = popup_atcursor(l:display_lines, {
            \ 'title': ' ' . l:symbol . ' ',
            \ 'padding': [1,2,1,2],
            \ 'border': [1,1,1,1],
            \ 'moved': 'any',
            \ 'maxwidth': float2nr(&columns * 0.6),
            \ 'maxheight': float2nr(&lines * 0.5),
            \ 'borderchars': ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
            \ 'highlight': 'Normal',
            \ 'borderhighlight': ['Special'],
            \ })
        
        " Apply markdown highlighting to the popup buffer
        let l:bufnr = winbufnr(l:winid)
        call setbufvar(l:bufnr, '&filetype', 'markdown')
        " Ensure code blocks are highlighted inside markdown
        call win_execute(l:winid, 'setlocal concealcursor=n conceallevel=2')
    else
        echo l:text
    endif
endfunction

function! s:show_references(result) abort
    if empty(a:result) | return | endif
    let l:qf = []
    for l:loc in a:result
        let l:file = substitute(l:loc.uri, '^file://', '', '')
        call add(l:qf, {
            \ 'filename': l:file,
            \ 'lnum': l:loc.range.start.line + 1,
            \ 'col': l:loc.range.start.character + 1,
            \ 'text': getline(l:loc.range.start.line + 1)
            \ })
    endfor
    call setqflist(l:qf)
    botright copen
endfunction
