" wplus/ai/suggest.vim — Ghost Text suggestion and smart tab engine

if exists('g:autoloaded_wplus_ai_suggest') | finish | endif
let g:autoloaded_wplus_ai_suggest = 1

let s:suggest_content = ''
let s:suggest_line = 0
let s:suggest_col = 0
let s:suggest_bufnr = 0
let s:suggest_timer = v:null
let s:suggest_changedtick = 0
let s:suggest_keystroke_count = 0
let s:last_suggest_error = ''
let s:last_suggest_error_at = 0

function! wplus#ai#suggest#setup() abort
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

    if g:wplus_ai_suggest_enabled
        augroup WplusAISuggest
            autocmd!
            autocmd InsertEnter * call s:on_insert_enter()
            autocmd InsertLeave * call wplus#ai#suggest#dismiss()
            autocmd TextChangedI * call s:on_text_changed()
        augroup END
    endif
endfunction

function! wplus#ai#suggest#show() abort
    let l:bufnr = s:suggest_bufnr

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
        if !empty(l:lines[0])
            call prop_add(l:line, l:col, {
                \ 'type': 'WplusAISuggest',
                \ 'bufnr': l:bufnr,
                \ 'text': l:lines[0],
                \ 'id': 1,
                \ })
        endif

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

function! wplus#ai#suggest#dismiss() abort
    let l:bufnr = s:suggest_bufnr
    let s:suggest_content = ''
    let s:suggest_line = 0
    let s:suggest_col = 0
    let s:suggest_bufnr = 0

    if s:suggest_timer != v:null
        call timer_stop(s:suggest_timer)
        let s:suggest_timer = v:null
    endif
    call wplus#ai#http#cancel_suggest()

    if l:bufnr > 0 && bufloaded(l:bufnr)
        call prop_remove({'type': 'WplusAISuggest', 'all': 1, 'bufnr': l:bufnr})
    endif
endfunction

function! s:insert_text_at_cursor(content) abort
    let l:lines = split(wplus#ai#security#sanitize_text(a:content), "\n", 1)
    if empty(l:lines) | return | endif
    let l:lnum = line('.')
    let l:byte = col('.') - 1
    let l:current = getline(l:lnum)
    let l:prefix = strpart(l:current, 0, l:byte)
    let l:suffix = strpart(l:current, l:byte)
    let l:replacement = copy(l:lines)
    let l:replacement[0] = l:prefix . l:replacement[0]
    let l:replacement[-1] .= l:suffix
    call setline(l:lnum, l:replacement[0])
    if len(l:replacement) > 1
        call appendbufline(bufnr('%'), l:lnum, l:replacement[1:])
    endif
    call cursor(l:lnum + len(l:replacement) - 1, strlen(l:replacement[-1]) + 1)
endfunction

function! wplus#ai#suggest#accept() abort
    if empty(s:suggest_content)
        return "\<Tab>"
    endif

    let l:content = wplus#ai#security#sanitize_text(s:suggest_content)
    call wplus#ai#suggest#dismiss()
    call s:suggest_debug('suggestion accepted')
    return substitute(l:content, '\n', "\<CR>", 'g')
endfunction

function! wplus#ai#suggest#accept_insert() abort
    if empty(s:suggest_content)
        return
    endif
    let l:content = wplus#ai#security#sanitize_text(s:suggest_content)
    call wplus#ai#suggest#dismiss()
    if mode() =~# 'i'
        call s:insert_text_at_cursor(l:content)
    else
        call append(line('.'), split(l:content, "\n", 1))
    endif
    call s:suggest_debug('suggestion accepted (insert)')
endfunction

function! wplus#ai#suggest#smart_tab() abort
    if wplus#ai#suggest#has_suggestion()
        return wplus#ai#suggest#accept()
    endif
    if pumvisible()
        return "\<C-n>"
    endif
    return "\<Tab>"
endfunction

function! wplus#ai#suggest#has_suggestion() abort
    return !empty(s:suggest_content)
endfunction

function! wplus#ai#suggest#accept_word() abort
    if empty(s:suggest_content)
        return "\<Space>"
    endif
    let l:content = s:suggest_content
    let l:match = matchlist(l:content, '^\(\s*\S\+\)\(\s\?\)\(.*\)$')
    if empty(l:match)
        call wplus#ai#suggest#dismiss()
        return ''
    endif
    let l:word = wplus#ai#security#sanitize_text(l:match[1])
    let l:rest = wplus#ai#security#sanitize_text(l:match[3])
    if empty(l:rest)
        call wplus#ai#suggest#dismiss()
    else
        let s:suggest_content = l:rest
        call wplus#ai#suggest#show()
    endif
    call s:suggest_debug('accepted word: ' . l:word)
    return substitute(l:word, '\n', "\<CR>", 'g')
endfunction

function! wplus#ai#suggest#accept_insert_word() abort
    if empty(s:suggest_content)
        return
    endif
    let l:word = wplus#ai#suggest#accept_word()
    if !empty(l:word) && mode() =~# 'i'
        call s:insert_text_at_cursor(l:word)
    endif
endfunction

function! wplus#ai#suggest#toggle() abort
    let g:wplus_ai_suggest_enabled = !g:wplus_ai_suggest_enabled
    if g:wplus_ai_suggest_enabled
        call wplus#util#info_msg('ai', 'Ghost Text suggestions enabled')
        augroup WplusAISuggest
            autocmd!
            autocmd InsertEnter * call s:on_insert_enter()
            autocmd InsertLeave * call wplus#ai#suggest#dismiss()
            autocmd TextChangedI * call s:on_text_changed()
        augroup END
    else
        call wplus#util#info_msg('ai', 'Ghost Text suggestions disabled')
        call wplus#ai#suggest#dismiss()
        augroup WplusAISuggest
            autocmd!
        augroup END
    endif
endfunction

function! s:handoff_lsp_popup() abort
    if !pumvisible()
        return 1
    endif
    " An automatically-triggered LSP popup is only a preview. If the user
    " waits without typing, hand control to ghost text instead of keeping
    " both completion UIs active at once.
    if !get(b:, 'wplus_lsp_completion_auto', 0) || get(b:, 'wplus_lsp_completion_tick', -1) != b:changedtick
        return 0
    endif
    call feedkeys("\<C-e>", 'nx')
    if pumvisible()
        return 0
    endif
    let b:wplus_lsp_completion_auto = 0
    return 1
endfunction

function! s:on_suggest_timer(timer) abort
    if mode() !~# '^i' || bufnr('%') != s:suggest_bufnr
        return
    endif
    if b:changedtick != s:suggest_changedtick || line('.') != s:suggest_line || col('.') != s:suggest_col
        return
    endif
    if !s:handoff_lsp_popup()
        return
    endif
    
    if wplus#ai#context#is_in_comment()
        return
    endif
    
    let l:prefix = wplus#ai#context#get_prefix(s:suggest_line, s:suggest_col, g:wplus_ai_suggest_context_lines)
    let l:suffix = wplus#ai#context#get_suffix(s:suggest_line, s:suggest_col, g:wplus_ai_suggest_suffix_lines)

    if wplus#ai#security#reject_sensitive(l:prefix . "\n" . l:suffix)
        return
    endif

    if empty(trim(l:prefix)) && empty(trim(l:suffix))
        call s:suggest_debug('skipped empty context')
        return
    endif

    call wplus#ai#http#send_suggest_request(l:prefix, l:suffix, '', function('s:on_suggest_complete'))
endfunction

function! s:on_suggest_complete(request, json) abort
    if mode() !~# '^i' || bufnr('%') != get(a:request, 'bufnr', -1)
        return
    endif
    if !s:handoff_lsp_popup()
        return
    endif
    if b:changedtick != get(a:request, 'changedtick', -1)
        call s:suggest_debug('dropped stale suggestion response')
        return
    endif
    if line('.') != get(a:request, 'line', -1) || col('.') != get(a:request, 'col', -1)
        return
    endif
    if get(a:request, 'fim', 0)
        let l:content = get(a:json, 'response', '')
    else
        let l:content = wplus#ai#provider#extract_content(a:json)
    endif

    if empty(l:content)
        let l:error_msg = wplus#ai#provider#extract_error(a:json)
        if l:error_msg =~? 'does not support insert'
            let g:wplus_ai_ollama_fim = 0
            call wplus#ai#provider#mark_fim_unsupported(wplus#ai#provider#get_completion_model())
            call s:report_suggest_error('Model does not support FIM -> fallback to chat (g:wplus_ai_ollama_fim=0)')
            if line('.') == a:request.line && col('.') == a:request.col && bufnr('%') == a:request.bufnr
                let l:prefix = wplus#ai#context#get_prefix(a:request.line, a:request.col, g:wplus_ai_suggest_context_lines)
                let l:suffix = wplus#ai#context#get_suffix(a:request.line, a:request.col, g:wplus_ai_suggest_suffix_lines)
                call wplus#ai#http#send_suggest_request(l:prefix, l:suffix, '', function('s:on_suggest_complete'))
            endif
        elseif !empty(l:error_msg)
            call s:suggest_debug('api error: ' . l:error_msg)
            call s:report_suggest_error(l:error_msg)
        else
            call s:suggest_debug('no suggestion content in response')
        endif
        return
    endif

    let l:content = wplus#ai#security#clean_suggest_content(l:content)
    if empty(l:content)
        return
    endif
    let l:max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
    let l:lines = split(l:content, "\n", 1)
    if len(l:lines) > l:max_lines
        let l:content = join(l:lines[:l:max_lines - 1], "\n")
    endif

    if line('.') == a:request.line && col('.') == a:request.col && bufnr('%') == a:request.bufnr
        let s:suggest_content = l:content
        let s:suggest_line = a:request.line
        let s:suggest_col = a:request.col
        let s:suggest_bufnr = a:request.bufnr
        call wplus#ai#suggest#show()
    else
        call s:suggest_debug('dropped stale suggestion response')
    endif
endfunction

function! s:on_text_changed() abort
    if !g:wplus_ai_suggest_enabled
        return
    endif

    let s:suggest_keystroke_count += 1
    if get(b:, 'wplus_lsp_completion_auto', 0) && get(b:, 'wplus_lsp_completion_tick', -1) != b:changedtick
        let b:wplus_lsp_completion_auto = 0
    endif
    call wplus#ai#suggest#dismiss()
    let s:suggest_line = line('.')
    let s:suggest_col = col('.')
    let s:suggest_bufnr = bufnr('%')
    let s:suggest_changedtick = b:changedtick
    
    let l:delay = g:wplus_ai_suggest_delay
    if s:suggest_keystroke_count > 5
        let l:delay = l:delay * 2
    endif
    
    let s:suggest_timer = timer_start(l:delay, function('s:on_suggest_timer'))
endfunction

function! s:on_insert_enter() abort
    let s:suggest_keystroke_count = 0
    let s:suggest_changedtick = b:changedtick
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

function! wplus#ai#suggest#set_test_content(content) abort
    let s:suggest_content = a:content
    let s:suggest_line = line('.')
    let s:suggest_col = col('.')
    let s:suggest_bufnr = bufnr('%')
endfunction
