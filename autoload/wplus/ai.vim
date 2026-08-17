" wplus/ai.vim — AI assistant entry point and command coordinator

if exists('g:autoloaded_wplus_ai') | finish | endif
let g:autoloaded_wplus_ai = 1

" ── Configuration ─────────────────────────────────────────────────────────────

let g:wplus_ai_enabled = get(g:, 'wplus_ai_enabled', 1)
let g:wplus_ai_provider = get(g:, 'wplus_ai_provider', 'openai')
let g:wplus_ai_model = get(g:, 'wplus_ai_model', '')
let g:wplus_ai_api_key = get(g:, 'wplus_ai_api_key', '')
let g:wplus_ai_temperature = get(g:, 'wplus_ai_temperature', 0.7)
let g:wplus_ai_max_tokens = get(g:, 'wplus_ai_max_tokens', 2048)

let g:wplus_ai_azure_resource = get(g:, 'wplus_ai_azure_resource', '')
let g:wplus_ai_azure_deployment = get(g:, 'wplus_ai_azure_deployment', '')
let g:wplus_ai_azure_api_version = get(g:, 'wplus_ai_azure_api_version', '2024-02-15-preview')

let g:wplus_ai_ollama_host = get(g:, 'wplus_ai_ollama_host', 'http://localhost:11434')
let g:wplus_ai_ollama_keep_alive = get(g:, 'wplus_ai_ollama_keep_alive', '30m')
let g:wplus_ai_ollama_fim = get(g:, 'wplus_ai_ollama_fim', 1)
let g:wplus_ai_ollama_think = get(g:, 'wplus_ai_ollama_think', 0)
let g:wplus_ai_ollama_options = get(g:, 'wplus_ai_ollama_options', {})

let g:wplus_ai_suggest_enabled = get(g:, 'wplus_ai_suggest_enabled', 1)
let g:wplus_ai_suggest_delay = get(g:, 'wplus_ai_suggest_delay', 500)
let g:wplus_ai_suggest_context_lines = get(g:, 'wplus_ai_suggest_context_lines', 50)
let g:wplus_ai_suggest_suffix_lines = get(g:, 'wplus_ai_suggest_suffix_lines', 20)
let g:wplus_ai_suggest_max_tokens = get(g:, 'wplus_ai_suggest_max_tokens', 128)
let g:wplus_ai_suggest_max_lines = get(g:, 'wplus_ai_suggest_max_lines', 3)
let g:wplus_ai_suggest_temperature = get(g:, 'wplus_ai_suggest_temperature', 0.2)
let g:wplus_ai_suggest_debug = get(g:, 'wplus_ai_suggest_debug', 0)
let g:wplus_ai_tab_complete = get(g:, 'wplus_ai_tab_complete', 1)

let g:wplus_ai_commit_max_tokens = get(g:, 'wplus_ai_commit_max_tokens', 500)
let g:wplus_ai_commit_diff_max_bytes = get(g:, 'wplus_ai_commit_diff_max_bytes', 32768)
let g:wplus_ai_commit_prompt = get(g:, 'wplus_ai_commit_prompt', '')

let g:wplus_ai_timeout = get(g:, 'wplus_ai_timeout', 60)
let g:wplus_ai_suggest_timeout = get(g:, 'wplus_ai_suggest_timeout', 10)
let g:wplus_ai_response_max_bytes = get(g:, 'wplus_ai_response_max_bytes', 1048576)
let g:wplus_ai_request_max_bytes = get(g:, 'wplus_ai_request_max_bytes', 524288)
let g:wplus_ai_block_sensitive_context = get(g:, 'wplus_ai_block_sensitive_context', 1)
let g:wplus_ai_allow_sensitive_context = get(g:, 'wplus_ai_allow_sensitive_context', 0)
let g:wplus_ai_sensitive_files = get(g:, 'wplus_ai_sensitive_files', [
    \ '.env', '.env.*', '*.pem', '*.key', '*.p12', '*.pfx',
    \ '*credentials*', '*secrets*',
    \ ])

" ── Setup & Registration ──────────────────────────────────────────────────────

function! wplus#ai#setup() abort
    if !executable('curl')
        call wplus#util#error_msg('ai', 'curl is required but not found in PATH')
        return
    endif

    let l:prov = wplus#ai#provider#get(g:wplus_ai_provider)
    if empty(l:prov)
        return
    endif

    augroup WplusAIContext
        autocmd!
        autocmd BufEnter,FileType,BufWritePost * call wplus#ai#context#invalidate(bufnr('%'))
    augroup END

    call wplus#ai#suggest#setup()

    if l:prov.needs_key && empty(g:wplus_ai_api_key)
        if g:wplus_ai_provider ==# 'openai'
            call wplus#util#warn_msg('ai', 'OpenAI: Set g:wplus_ai_api_key, g:wplus_ai_model')
        elseif g:wplus_ai_provider ==# 'claude'
            call wplus#util#warn_msg('ai', 'Claude: Set g:wplus_ai_api_key, g:wplus_ai_model')
        elseif g:wplus_ai_provider ==# 'azure'
            call wplus#util#warn_msg('ai', 'Azure: Set g:wplus_ai_api_key, g:wplus_ai_azure_resource, g:wplus_ai_azure_deployment')
        endif
    endif

    command! -range WaiComment   call wplus#ai#comment('visual')
    command! -nargs=? WaiComplete call wplus#ai#complete(<q-args> != '' ? <q-args> : 5)
    command! -range WaiRefactor  call wplus#ai#refactor()
    command! WaiFixDiag          call wplus#ai#fix_diagnostic()
    command! WaiCommitMsg        call wplus#ai#commit_message()
    command! WaiToggleSuggest    call wplus#ai#toggle_suggest()
    command! WaiAcceptSuggest    call wplus#ai#accept_suggestion_insert()
    command! WaiDismissSuggest   call wplus#ai#dismiss_suggestion()
    command! WaiAcceptWord       call wplus#ai#accept_suggestion_insert_word()
    command! -range WaiReview    <line1>,<line2>call wplus#ai#review()
    command! -range WaiExplain   <line1>,<line2>call wplus#ai#explain()
    command! WaiCancel           call wplus#ai#cancel()

    inoremap <silent> <Plug>WaiDismissSuggest <C-r>=wplus#ai#dismiss_suggestion()<CR>
    inoremap <silent> <expr> <Plug>WaiAcceptSuggest wplus#ai#accept_suggestion()
    inoremap <silent> <expr> <Plug>WaiAcceptWord wplus#ai#accept_word_suggestion()
    inoremap <silent> <expr> <Plug>WaiSmartTab wplus#ai#smart_tab()

    if g:wplus_ai_tab_complete && empty(mapcheck('<Tab>', 'i'))
        imap <expr> <Tab> wplus#ai#smart_tab()
    endif
endfunction

" ── Interactive Commands ──────────────────────────────────────────────────────

function! wplus#ai#comment(range_type) abort
    let l:bufnr = bufnr('%')
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end,   l:col_end]   = getpos("'>")[1:2]

    if l:line_start == 0 || l:line_end == 0 || a:range_type ==# 'line'
        let l:line_start = line('.')
        let l:line_end   = line('.')
    endif

    let l:lines = getline(l:line_start, l:line_end)
    let l:code = join(l:lines, "\n")
    if empty(trim(l:code))
        call wplus#util#warn_msg('ai', 'no code selected')
        return
    endif

    let l:prompt = "Add concise and informative comments to this code. Return the code with comments added. Do not change code logic:\n\n" . l:code
    call wplus#ai#http#send_request(l:prompt, function('wplus#ai#ui#preview_replace_range', [l:bufnr, l:line_start, l:line_end]))
endfunction

function! wplus#ai#complete(context_lines) abort
    let l:bufnr = bufnr('%')
    let l:lnum = line('.')
    let l:lines = getline(max([1, l:lnum - a:context_lines + 1]), l:lnum)
    let l:context = join(l:lines, "\n")
    if empty(trim(l:context))
        call wplus#util#warn_msg('ai', 'buffer is empty')
        return
    endif

    let l:prompt = "Complete the next lines of code based on context:\n\n" . l:context
    call wplus#ai#http#send_request(l:prompt, function('wplus#ai#ui#preview_insert_after', [l:bufnr, l:lnum]))
endfunction

function! wplus#ai#refactor() abort
    let l:bufnr = bufnr('%')
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end,   l:col_end]   = getpos("'>")[1:2]

    if l:line_start == 0 || l:line_end == 0
        let l:line_start = line('.')
        let l:line_end   = line('.')
    endif

    let l:lines = getline(l:line_start, l:line_end)
    let l:code = join(l:lines, "\n")
    if empty(trim(l:code))
        call wplus#util#warn_msg('ai', 'no code selected')
        return
    endif

    let l:prompt = "Refactor this code to improve readability and performance while preserving behavior. Return only the refactored code without explanation or markdown blocks:\n\n" . l:code
    call wplus#ai#http#send_request(l:prompt, function('wplus#ai#ui#preview_replace_range', [l:bufnr, l:line_start, l:line_end]))
endfunction

function! wplus#ai#fix_diagnostic() abort
    let l:bufnr = bufnr('%')
    let l:lnum = line('.')
    let l:cur_line = getline(l:lnum)
    let l:diags = getbufvar(l:bufnr, 'wplus_lsp_diags', [])
    let l:diag_msg = ''
    for l:d in l:diags
        if get(l:d, 'lnum', 0) == l:lnum
            let l:diag_msg = get(l:d, 'text', '')
            break
        endif
    endfor
    if empty(l:diag_msg)
        call wplus#util#warn_msg('ai', 'no LSP diagnostic on current line')
        return
    endif

    let l:prefix = wplus#ai#context#get_prefix(l:lnum, 1, 20)
    let l:suffix = wplus#ai#context#get_suffix(l:lnum + 1, 1, 20)
    let l:prompt = "Explain the following LSP diagnostic on line " . l:lnum . " and provide the corrected line:\n\n" .
        \ "Diagnostic: " . l:diag_msg . "\n\n" .
        \ "Context before:\n" . l:prefix . "\n\n" .
        \ "Line with error:\n" . l:cur_line . "\n\n" .
        \ "Context after:\n" . l:suffix . "\n\n" .
        \ "Return ONLY the corrected line of code, without explanations or markdown."
    call wplus#ai#http#send_request(l:prompt, function('wplus#ai#ui#preview_replace_range', [l:bufnr, l:lnum, l:lnum]))
endfunction

function! wplus#ai#commit_message() abort
    let l:file = expand('%:p')
    let l:root = !empty(l:file) ? wplus#util#find_git_root(fnamemodify(l:file, ':h')) : ''
    if empty(l:root)
        let l:root = wplus#util#find_git_root(getcwd())
    endif
    if empty(l:root)
        call wplus#util#error_msg('ai', 'not a git repository')
        return
    endif
    if g:wplus_ai_provider !=# 'ollama' && empty(g:wplus_ai_api_key)
        call wplus#util#error_msg('ai', 'API key not configured (g:wplus_ai_api_key)')
        return
    endif
    if empty(g:wplus_ai_model)
        call wplus#util#error_msg('ai', 'model not configured (g:wplus_ai_model)')
        return
    endif

    let l:stat_lines = []
    call job_start(['git', '-C', l:root, 'diff', '--cached', '--stat'], {
        \ 'out_cb':   {_, l -> add(l:stat_lines, l)},
        \ 'close_cb': {_ -> s:on_commit_stat_done(l:root, l:stat_lines)},
        \ 'err_cb':   {_ch, _msg -> 0},
        \ })
    call wplus#util#info_msg('ai', 'reading staged changes...')
endfunction

function! s:on_commit_stat_done(root, stat_lines) abort
    let l:stat = trim(join(a:stat_lines, "\n"))
    if empty(l:stat)
        call wplus#util#warn_msg('ai', 'no staged changes (git add first)')
        return
    endif
    let l:diff_lines = []
    call job_start(['git', '-C', a:root, 'diff', '--cached'], {
        \ 'out_cb':   {_, l -> add(l:diff_lines, l)},
        \ 'close_cb': {_ -> s:on_commit_diff_collected(l:stat, l:diff_lines)},
        \ 'err_cb':   {_ch, _msg -> 0},
        \ })
endfunction

function! s:on_commit_diff_collected(stat, lines) abort
    let l:diff = join(a:lines, "\n")
    if empty(trim(l:diff))
        call wplus#util#warn_msg('ai', 'no staged changes (git add first)')
        return
    endif
    let l:max = g:wplus_ai_commit_diff_max_bytes
    if len(l:diff) > l:max
        call wplus#util#warn_msg('ai', 'diff too large (' . (len(l:diff)/1024) . 'KB), truncating to ' . (l:max/1024) . 'KB')
        let l:diff = l:diff[:l:max - 1]
        let l:last_nl = strridx(l:diff, "\n")
        if l:last_nl > 0
            let l:diff = l:diff[:l:last_nl]
        endif
    endif
    let l:prompt = wplus#ai#provider#build_commit_prompt(a:stat, l:diff)
    call wplus#ai#http#send_request(l:prompt, function('wplus#ai#ui#preview_commit'), g:wplus_ai_commit_max_tokens, 0.3)
endfunction

function! wplus#ai#review() range abort
    let l:bufnr = bufnr('%')
    let l:ft = &filetype
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end,   l:col_end]   = getpos("'>")[1:2]

    if l:line_start == 0 || l:line_end == 0 || l:line_start == l:line_end
        let l:line_start = 1
        let l:line_end = line('$')
    endif

    let l:lines = getline(l:line_start, l:line_end)
    let l:code = join(l:lines, "\n")
    if empty(trim(l:code))
        call wplus#util#warn_msg('ai', 'no code to review')
        return
    endif

    let l:prompt = "Review the following code for bugs, security issues, performance, and best practices. Format your response in markdown with clear sections:\n\n" . l:code
    call wplus#ai#http#send_request(l:prompt, function('wplus#ai#ui#show_review_result', [l:ft, 'AI Code Review']))
endfunction

function! wplus#ai#explain() range abort
    let l:bufnr = bufnr('%')
    let l:ft = &filetype
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end,   l:col_end]   = getpos("'>")[1:2]

    if l:line_start == 0 || l:line_end == 0 || l:line_start == l:line_end
        let l:line_start = 1
        let l:line_end = line('$')
    endif

    let l:lines = getline(l:line_start, l:line_end)
    let l:code = join(l:lines, "\n")
    if empty(trim(l:code))
        call wplus#util#warn_msg('ai', 'no code to explain')
        return
    endif

    let l:prompt = "Explain how the following code works step-by-step. Include key logic, edge cases, and time/space complexity if applicable. Format in markdown:\n\n" . l:code
    call wplus#ai#http#send_request(l:prompt, function('wplus#ai#ui#show_review_result', [l:ft, 'AI Code Explanation']))
endfunction

" ── Facade & Public API Delegations ───────────────────────────────────────────

function! wplus#ai#register_provider(name, dict) abort
    call wplus#ai#provider#register(a:name, a:dict)
endfunction

function! wplus#ai#smart_tab() abort
    return wplus#ai#suggest#smart_tab()
endfunction

function! wplus#ai#has_suggestion() abort
    return wplus#ai#suggest#has_suggestion()
endfunction

function! wplus#ai#accept_suggestion() abort
    return wplus#ai#suggest#accept()
endfunction

function! wplus#ai#accept_suggestion_insert() abort
    call wplus#ai#suggest#accept_insert()
endfunction

function! wplus#ai#accept_word_suggestion() abort
    return wplus#ai#suggest#accept_word()
endfunction

function! wplus#ai#accept_suggestion_insert_word() abort
    call wplus#ai#suggest#accept_insert_word()
endfunction

function! wplus#ai#dismiss_suggestion() abort
    call wplus#ai#suggest#dismiss()
endfunction

function! wplus#ai#toggle_suggest() abort
    call wplus#ai#suggest#toggle()
endfunction

function! wplus#ai#cancel() abort
    call wplus#ai#http#cancel_all()
    call wplus#ai#suggest#dismiss()
    call wplus#util#info_msg('ai', 'canceled all AI requests')
endfunction

function! wplus#ai#preview_filter(winid, key) abort
    return wplus#ai#ui#preview_filter(a:winid, a:key)
endfunction

" ── Test Bridges ──────────────────────────────────────────────────────────────

function! wplus#ai#_test_build_suggest_payload(prefix, suffix) abort
    return wplus#ai#provider#build_suggest_payload(a:prefix, a:suffix)
endfunction

function! wplus#ai#_test_get_api_endpoint(...) abort
    return call('wplus#ai#provider#get_endpoint', a:000)
endfunction

function! wplus#ai#_test_write_payload_stdin(job, payload) abort
    return wplus#ai#http#write_payload_stdin(a:job, a:payload)
endfunction

function! wplus#ai#_test_sanitize_text(text) abort
    return wplus#ai#security#sanitize_text(a:text)
endfunction

function! wplus#ai#_test_is_sensitive(text) abort
    return wplus#ai#security#is_sensitive(a:text)
endfunction

function! wplus#ai#_test_set_suggestion(content) abort
    call wplus#ai#suggest#set_test_content(a:content)
endfunction

function! wplus#ai#_test_clean_commit(content) abort
    return wplus#ai#security#clean_commit_message(a:content)
endfunction

function! wplus#ai#_test_build_commit_prompt(stat, diff) abort
    return wplus#ai#provider#build_commit_prompt(a:stat, a:diff)
endfunction
