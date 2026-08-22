" wplus/ai/security.vim — Credential blocking and text sanitization

if exists('g:autoloaded_wplus_ai_security') | finish | endif
let g:autoloaded_wplus_ai_security = 1

" Remove control characters before AI output is displayed or inserted. Keep
" newline and tab because they are meaningful in source code. AI output is
" untrusted input and must never be allowed to contain terminal/Vim controls.
function! wplus#ai#security#sanitize_text(content) abort
    let l:out = []
    for l:ch in split(a:content, '\zs')
        let l:n = char2nr(l:ch)
        if l:n == 9 || l:n == 10 || (l:n > 31 && l:n != 127)
            call add(l:out, l:ch)
        endif
    endfor
    return join(l:out, '')
endfunction

function! wplus#ai#security#clean_suggest_content(content) abort
    let l:txt = wplus#ai#security#sanitize_text(a:content)
    " Remove completed <think>...</think> and <thought>...</thought> tags
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.\{-}</\%(think\|thought\)>', '', 'g')
    " Remove unclosed <think> or <thought> tags to the end
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.*$', '', 'g')
    " Remove markdown code blocks
    let l:txt = substitute(l:txt, '```.*\n', '', 'g')
    let l:txt = substitute(l:txt, '```', '', 'g')
    " Keep all response whitespace. A leading newline is often the actual
    " insertion point (for example when completing the next indented line),
    " and indentation must survive acceptance. Use trim() only for checks.
    " Some completion models emit the FIM/decorator marker by itself when
    " there is not enough context. It is not useful ghost text and can cause
    " the same one-character suggestion to be rendered repeatedly.
    if trim(l:txt) ==# '@' || empty(trim(l:txt))
        return ''
    endif
    return l:txt
endfunction

" Normalize chat-model output against the exact text surrounding the cursor.
" Chat fallback models often echo the current line or the first suffix line;
" leaving that echo in a ghost suggestion makes acceptance duplicate code.
function! wplus#ai#security#trim_suggest_content(content, suffix, prefix) abort
    let l:txt = wplus#ai#security#clean_suggest_content(a:content)
    if empty(l:txt)
        return ''
    endif

    let l:prefix_tail = matchstr(a:prefix, '[^\n]*$')
    let l:prefix_indent = matchstr(l:prefix_tail, '^\s*')
    let l:prefix_code = substitute(l:prefix_tail, '^\s*', '', '')
    if !empty(l:prefix_code) && strpart(l:txt, 0, strlen(l:prefix_indent . l:prefix_code)) ==# l:prefix_indent . l:prefix_code
        let l:txt = strpart(l:txt, strlen(l:prefix_indent . l:prefix_code))
    elseif !empty(l:prefix_code) && strpart(l:txt, 0, strlen(l:prefix_code)) ==# l:prefix_code
        let l:txt = strpart(l:txt, strlen(l:prefix_code))
    elseif !empty(trim(l:prefix_tail)) && strpart(l:txt, 0, strlen(l:prefix_tail)) ==# l:prefix_tail
        let l:txt = strpart(l:txt, strlen(l:prefix_tail))
    endif

    if empty(trim(l:txt))
        return ''
    endif

    let l:suffix_lines = split(a:suffix, '\n', 1)
    let l:first_suffix = ''
    for l:line in l:suffix_lines
        if !empty(trim(l:line))
            let l:first_suffix = trim(l:line)
            break
        endif
    endfor
    if !empty(l:first_suffix)
        let l:lines = split(l:txt, '\n', 1)
        for l:i in range(0, len(l:lines) - 1)
            if trim(l:lines[l:i]) ==# l:first_suffix
                let l:lines = l:i > 0 ? l:lines[: l:i - 1] : []
                break
            endif
        endfor
        let l:txt = join(l:lines, "\n")
    endif
    return l:txt
endfunction

function! wplus#ai#security#clean_commit_message(content) abort
    let l:txt = wplus#ai#security#sanitize_text(a:content)
    " Remove completed <think>...</think> and <thought>...</thought> tags
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.\{-}</\%(think\|thought\)>', '', 'g')
    " Remove unclosed <think> or <thought> tags to the end
    let l:txt = substitute(l:txt, '<\%(think\|thought\)\_.*$', '', 'g')
    " Remove markdown code blocks (e.g. ```gitcommit ... ```)
    let l:txt = substitute(l:txt, '\v^```%(gitcommit|text|markdown)?\s*\n', '', 'g')
    let l:txt = substitute(l:txt, '\v\n```\s*$', '', 'g')
    let l:txt = substitute(l:txt, '```', '', 'g')
    return trim(l:txt)
endfunction

" Return true for files or content that should not be sent automatically to an
" AI provider. This is deliberately fail-closed for common credential files
" and strong secret assignments, while avoiding broad matches such as the word
" token in normal prose.
function! wplus#ai#security#is_sensitive(text) abort
    if !get(g:, 'wplus_ai_block_sensitive_context', 1)
        return 0
    endif
    if get(g:, 'wplus_ai_allow_sensitive_context', 0)
        return 0
    endif
    let l:name = expand('%:t')
    if !empty(l:name) && l:name !=# 'COMMIT_EDITMSG'
        for l:pattern in get(g:, 'wplus_ai_sensitive_files', [])
            if exists('*glob2regpat') && l:name =~# glob2regpat(l:pattern)
                return 1
            elseif l:name ==# l:pattern
                return 1
            endif
        endfor
    endif
    for l:line in split(a:text, "\n", 1)
        " Match private key envelopes
        if l:line =~? '-----BEGIN.*PRIVATE KEY-----' && a:text =~? '-----END.*PRIVATE KEY-----'
            return 1
        endif
        if l:line =~? '\cauthorization:\s*bearer\s\+\S\{16,}' || l:line =~? '\cbearer\s\+[A-Za-z0-9._~-]\{16,}'
            return 1
        endif
        " Check credential keyword assignments (api_key, secret_key, password, aws credentials)
        if l:line =~? '\v\c%(api[_-]?key|secret[_-]?key|password|aws_access_key_id|aws_secret_access_key)\s*[=:]'
            let l:value = s:extract_credential_rhs_value(l:line)
            if s:value_is_literal_secret(l:value)
                return 1
            endif
        endif
    endfor
    return 0
endfunction

" Extract only the right-hand side value after an assignment keyword, stripping
" surrounding quotes, inline comments, and delimiters.
function! s:extract_credential_rhs_value(line) abort
    let l:parts = matchlist(a:line, '\v\c%(api[_-]?key|secret[_-]?key|password|aws_access_key_id|aws_secret_access_key)\s*[=:]\s*(.*)')
    if empty(l:parts) || empty(l:parts[1])
        return ''
    endif
    let l:raw = trim(l:parts[1])

    " Single-quoted literal: 'secret_value' [optional comment]
    let l:sq = matchlist(l:raw, "^'\\([^']*\\)'")
    if !empty(l:sq)
        return l:sq[1]
    endif

    " Double-quoted literal: "secret_value" [optional comment]
    let l:dq = matchlist(l:raw, '^"\([^"]*\)"')
    if !empty(l:dq)
        return l:dq[1]
    endif

    " Unquoted identifier / expression / reference: strip trailing inline comments & punctuation
    let l:val = substitute(l:raw, '\s*#.*$', '', '')
    let l:val = substitute(l:val, '\s*//.*$', '', '')
    let l:val = substitute(l:val, '\s*".*$', '', '')
    let l:val = substitute(l:val, '[,;]\s*$', '', '')
    return trim(l:val)
endfunction

" Return true only when the right-hand side of a credential assignment is a
" literal secret value rather than a reference to a secret/config stored
" elsewhere. References (dotted member access, subscript/env lookups, function
" calls, shell variables, documented placeholders) are common in real code and
" must not be treated as leaked secrets.
function! s:value_is_literal_secret(value) abort
    if strlen(a:value) < 12
        return 0
    endif
    " Documented / example / placeholder values.
    if a:value =~? 'your-\|example\|placeholder\|secret-api-key\|not-a-real-key\|allowed-by-explicit-override\|sk-\.\.\.'
        return 0
    endif
    " Shell / environment variable references ($VAR).
    if a:value =~# '^\$'
        return 0
    endif
    " Variable/function references: dotted member access (cfg.password,
    " settings.API_KEY), subscript/env lookups (os.environ["X"]), and function
    " calls (get_password_from_vault(), secrets.token_hex(32)).
    if a:value =~# '\.' || a:value =~# '\[' || a:value =~# '\c^[a-z_][a-z0-9_]*(\s*'
        return 0
    endif
    " A bare identifier that looks like a variable/constant name (snake_case or
    " ALL_CAPS) is a reference, not a literal secret. Genuine literals almost
    " always contain mixed case/digits/symbols or a leading non-letter.
    if a:value =~# '^[A-Za-z_][A-Za-z0-9_]*$'
        if a:value =~# '_' || a:value =~# '^[A-Z][A-Z0-9]*$'
            return 0
        endif
    endif
    return 1
endfunction

function! wplus#ai#security#reject_sensitive(text) abort
    if wplus#ai#security#is_sensitive(a:text)
        call wplus#util#warn_msg('ai', 'request blocked: sensitive file or credential-like content detected')
        return 1
    endif
    return 0
endfunction
