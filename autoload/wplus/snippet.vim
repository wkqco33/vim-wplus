" wplus/snippet.vim — Minimal snippet engine with TextObj integration

if exists('g:autoloaded_wplus_snippet') | finish | endif
let g:autoloaded_wplus_snippet = 1

let s:snippets = {} " ft -> [{trigger, body, expand_fn}...]
let s:active_snippet = {} " {bufnr, start_lnum, end_lnum, placeholders [...]}
let g:wplus_snippet_enabled = get(g:, 'wplus_snippet_enabled', 1)

function! s:collect_placeholders(lines, start_lnum) abort
    let l:placeholders = []
    let l:pattern = '\${\([0-9]\+\):\([^}]*\)}'

    for l:idx in range(len(a:lines))
        let l:line = a:lines[l:idx]
        let l:start = 0
        while 1
            let l:match = matchlist(l:line, l:pattern, l:start)
            if empty(l:match)
                break
            endif
            call add(l:placeholders, {
                \ 'num': str2nr(l:match[1]),
                \ 'lnum': a:start_lnum + l:idx,
                \ 'default': l:match[2],
                \ 'col': match(l:line, l:pattern, l:start) + 1
                \ })
            let l:start = matchend(l:line, l:pattern, l:start)
            if l:start < 0
                break
            endif
        endwhile
    endfor

    return l:placeholders
endfunction

function! s:register_snippet(ft, trigger, body) abort
    if !has_key(s:snippets, a:ft)
        let s:snippets[a:ft] = []
    endif
    let l:body_lines = split(a:body, "\n")
    call add(s:snippets[a:ft], {
        \ 'trigger': a:trigger,
        \ 'body': a:body,
        \ 'placeholder_count': len(s:collect_placeholders(l:body_lines, 1))
        \ })
endfunction

function! s:expand_snippet(trigger, body) abort
    if empty(a:body) | return | endif
    
    let l:bufnr = bufnr('%')
    let l:lnum = line('.')
    let l:col = col('.')
    
    " Remove trigger text
    call deletebufline(l:bufnr, l:lnum, l:lnum)
    call append(l:lnum - 1, split(a:body, "\n"))
    
    " Parse placeholders: ${1:default} or ${0:end_marker}
    let s:active_snippet = {
        \ 'bufnr': l:bufnr,
        \ 'start_lnum': l:lnum,
        \ 'end_lnum': l:lnum + len(split(a:body, "\n")) - 1,
        \ 'placeholders': [],
        \ 'current_idx': 1
        \ }
    
    " Extract and highlight placeholders
    let l:body_lines = split(a:body, "\n")
    let s:active_snippet.placeholders = s:collect_placeholders(l:body_lines, l:lnum)
    
    " Sort by placeholder number
    call sort(s:active_snippet.placeholders, {a, b -> a.num - b.num})
    
    " Jump to first placeholder
    if !empty(s:active_snippet.placeholders)
        let l:first = s:active_snippet.placeholders[0]
        call cursor(l:first.lnum, l:first.col)
        
        " Select default text
        let l:default_len = len(l:first.default)
        if l:default_len > 0
            execute 'normal! v' . (l:default_len - 1) . 'l'
        endif
    else
        call cursor(s:active_snippet.end_lnum, 1)
    endif
endfunction

function! s:jump_next_placeholder() abort
    if empty(s:active_snippet) || empty(s:active_snippet.placeholders) | return | endif
    
    let l:current_idx = s:active_snippet.current_idx
    if l:current_idx < len(s:active_snippet.placeholders)
        let l:next = s:active_snippet.placeholders[l:current_idx]
        let s:active_snippet.current_idx = l:current_idx + 1
        call cursor(l:next.lnum, l:next.col)
        
        " Select default text
        let l:default_len = len(l:next.default)
        if l:default_len > 0
            execute 'normal! v' . (l:default_len - 1) . 'l'
        endif
    else
        " End of snippet, clear active
        let s:active_snippet = {}
    endif
endfunction

function! s:jump_prev_placeholder() abort
    if empty(s:active_snippet) || empty(s:active_snippet.placeholders) | return | endif
    
    let l:current_idx = s:active_snippet.current_idx
    if l:current_idx > 1
        let l:current_idx = l:current_idx - 2
        let l:prev = s:active_snippet.placeholders[l:current_idx]
        let s:active_snippet.current_idx = l:current_idx + 1
        call cursor(l:prev.lnum, l:prev.col)
        
        " Select default text
        let l:default_len = len(l:prev.default)
        if l:default_len > 0
            execute 'normal! v' . (l:default_len - 1) . 'l'
        endif
    endif
endfunction

function! wplus#snippet#expand_or_jump(direction) abort
    if !g:wplus_snippet_enabled | return | endif
    
    if !empty(s:active_snippet)
        " We're in a snippet, jump
        if a:direction == 'next'
            call s:jump_next_placeholder()
        else
            call s:jump_prev_placeholder()
        endif
        return
    endif
    
    " Try to expand snippet at cursor
    let l:ft = &filetype
    if !has_key(s:snippets, l:ft) | return | endif
    
    let l:word = expand('<cword>')
    if empty(l:word) | return | endif
    
    " Find matching snippet
    for l:snippet in s:snippets[l:ft]
        if l:snippet.trigger ==# l:word
            call s:expand_snippet(l:snippet.trigger, l:snippet.body)
            return
        endif
    endfor
endfunction

function! wplus#snippet#setup() abort
    if !g:wplus_snippet_enabled | return | endif
    
    augroup WplusSnippet
        autocmd!
        autocmd BufDelete * if bufnr('%') == get(s:active_snippet, 'bufnr', -1) | let s:active_snippet = {} | endif
    augroup END
    
    " Built-in snippets
    " Python
    call s:register_snippet('python', 'def', "def ${1:func_name}(${2:args}):\n    ${0:pass}")
    call s:register_snippet('python', 'class', "class ${1:ClassName}:\n    def __init__(self):\n        ${0:pass}")
    call s:register_snippet('python', 'try', "try:\n    ${1:pass}\nexcept ${2:Exception}:\n    ${0:pass}")
    
    " Go
    call s:register_snippet('go', 'if', "if ${1:condition} {\n    ${0:}\n}")
    call s:register_snippet('go', 'for', "for ${1:i} := 0; ${1:i} < ${2:n}; ${1:i}++ {\n    ${0:}\n}")
    call s:register_snippet('go', 'func', "func ${1:funcName}(${2:args}) ${3:returnType} {\n    ${0:}\n}")
    
    " C/C++
    call s:register_snippet('c', 'if', "if (${1:condition}) {\n    ${0:}\n}")
    call s:register_snippet('cpp', 'if', "if (${1:condition}) {\n    ${0:}\n}")
    call s:register_snippet('c', 'for', "for (${1:int i = 0}; ${2:i < n}; ${3:i++}) {\n    ${0:}\n}")
    call s:register_snippet('cpp', 'for', "for (${1:int i = 0}; ${2:i < n}; ${3:i++}) {\n    ${0:}\n}")
    
    " Mappings
    inoremap <silent> <Plug>WplusSnippetExpand <C-o>:call wplus#snippet#expand_or_jump('next')<CR>
    inoremap <silent> <Plug>WplusSnippetJumpNext <C-o>:call wplus#snippet#expand_or_jump('next')<CR>
    inoremap <silent> <Plug>WplusSnippetJumpPrev <C-o>:call wplus#snippet#expand_or_jump('prev')<CR>
endfunction
