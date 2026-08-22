" wplus/health.vim — diagnostics for the wplus setup

if exists('g:autoloaded_wplus_health') | finish | endif
let g:autoloaded_wplus_health = 1

let s:native_keys = ['.', "\<C-a>", "\<C-x>"]

let s:owners = {
    \ ']h': 'gitgutter#next_hunk',
    \ '[h': 'gitgutter#prev_hunk',
    \ }

let s:allowed_prefixes = ['gc', 'ys', 'ds', 'cs']

let s:known_options = [
    \ 'wplus_theme', 'wplus_theme_enabled', 'wplus_commentary_enabled', 'wplus_pairs_enabled',
    \ 'wplus_altfile_enabled', 'wplus_indent_enabled', 'wplus_indent_char', 'wplus_statusline_enabled',
    \ 'wplus_tabline_enabled', 'wplus_gitgutter_enabled', 'wplus_blame_enabled', 'wplus_blame_delay',
    \ 'wplus_blame_prefix', 'wplus_blame_template', 'wplus_illuminate_enabled', 'wplus_illuminate_delay',
    \ 'wplus_surround_enabled', 'wplus_format_enabled', 'wplus_yankhighlight_enabled', 'wplus_yank_duration',
    \ 'wplus_textobj_enabled', 'wplus_bufdelete_enabled', 'wplus_quickfix_enabled', 'wplus_grep_enabled',
    \ 'wplus_root_enabled', 'wplus_terminal_enabled', 'wplus_lsp_enabled', 'wplus_lsp_log_enabled',
    \ 'wplus_lsp_signcolumn', 'wplus_lsp_cache_ttl', 'wplus_lsp_sig_delay', 'wplus_lsp_change_delay',
    \ 'wplus_lsp_diag_delay', 'wplus_lsp_request_timeout', 'wplus_lsp_inlay_hints', 'wplus_finder_enabled',
    \ 'wplus_explorer_enabled', 'wplus_explorer_max_entries', 'wplus_explorer_max_depth', 'wplus_session_enabled',
    \ 'wplus_todo_enabled', 'wplus_conflict_enabled', 'wplus_ai_enabled', 'wplus_ai_provider',
    \ 'wplus_ai_model', 'wplus_ai_completion_model', 'wplus_ai_api_key', 'wplus_ai_temperature', 'wplus_ai_max_tokens',
    \ 'wplus_ai_azure_resource', 'wplus_ai_azure_deployment', 'wplus_ai_azure_api_version',
    \ 'wplus_ai_ollama_host', 'wplus_ai_ollama_think', 'wplus_ai_ollama_keep_alive', 'wplus_ai_ollama_fim',
    \ 'wplus_ai_ollama_options', 'wplus_ai_suggest_enabled', 'wplus_ai_suggest_delay',
    \ 'wplus_ai_suggest_context_lines', 'wplus_ai_suggest_suffix_lines', 'wplus_ai_suggest_max_tokens',
    \ 'wplus_ai_suggest_max_lines', 'wplus_ai_suggest_temperature', 'wplus_ai_suggest_debug',
    \ 'wplus_ai_tab_complete', 'wplus_ai_commit_max_tokens', 'wplus_ai_commit_prompt',
    \ 'wplus_ai_timeout', 'wplus_ai_suggest_timeout', 'wplus_ai_response_max_bytes', 'wplus_ai_request_max_bytes',
    \ 'wplus_ai_block_sensitive_context', 'wplus_ai_allow_sensitive_context',
    \ 'wplus_ai_sensitive_files', 'wplus_ai_openai_endpoint', 'wplus_multicursor_enabled', 'wplus_register_enabled',
    \ 'wplus_outline_enabled', 'wplus_diffview_enabled', 'wplus_harpoon_enabled', 'wplus_harpoon_max_slots',
    \ 'wplus_marks_enabled', 'wplus_scratch_enabled', 'wplus_scratch_height', 'wplus_run_enabled',
    \ 'wplus_project_enabled', 'wplus_project_trust_all', 'wplus_history_enabled', 'wplus_history_max',
    \ 'wplus_fold_enabled', 'wplus_fold_method', 'wplus_fold_level', 'wplus_fold_column',
    \ 'wplus_ai_commit_diff_max_bytes', 'wplus_blame_date_format', 'wplus_blame_enabled_flag',
    \ 'wplus_build_commands', 'wplus_finder_fuzzy_limit', 'wplus_finder_height_ratio',
    \ 'wplus_finder_width_ratio', 'wplus_fold_ft_exclude', 'wplus_fold_min_lines',
    \ 'wplus_gitgutter_sign_add', 'wplus_gitgutter_sign_change', 'wplus_gitgutter_sign_delete',
    \ 'wplus_health_enabled', 'wplus_history_project_only', 'wplus_illuminate_ft_block',
    \ 'wplus_indent_ft_exclude', 'wplus_marks_sign_prefix', 'wplus_project_config',
    \ 'wplus_project_verbose', 'wplus_run_commands', 'wplus_run_use_terminal',
    \ 'wplus_scratch_file', 'wplus_scratch_ft', 'wplus_scratch_position',
    \ 'wplus_session_autoload', 'wplus_session_autosave', 'wplus_session_max_files',
    \ 'wplus_theme_auto', 'wplus_todo_grep_backend', 'wplus_todo_keywords',
    \ 'wplus_load_errors',
    \ 'wplus_conflict_auto_highlight', 'wplus_explorer_width', 'wplus_explorer_ignore',
    \ 'wplus_format_on_save', 'wplus_format_preserve_undo',
    \ 'wplus_gitgutter_disable_on_large_files', 'wplus_gitgutter_file_size_limit',
    \ 'wplus_grep_backend', 'wplus_grep_ignore_vcs', 'wplus_grep_max_results',
    \ 'wplus_lsp_debug', 'wplus_lsp_definition_split', 'wplus_lsp_servers',
    \ 'wplus_lsp_auto_complete', 'wplus_lsp_complete_delay', 'wplus_lsp_complete_min_chars',
    \ 'wplus_vscode_keymaps',
    \ 'wplus_terminal_height', 'wplus_terminal_position',
    \ ]

function! wplus#health#native_keys() abort
    return copy(s:native_keys)
endfunction

function! wplus#health#owners() abort
    return copy(s:owners)
endfunction

function! s:collect(mode) abort
    let l:out = []
    if exists('*maplist')
        for l:m in maplist()
            if l:m.mode !~# a:mode || get(l:m, 'buffer', 0)
                continue
            endif
            call add(l:out, {
                \ 'lhs': get(l:m, 'lhsraw', l:m.lhs),
                \ 'display': l:m.lhs,
                \ 'rhs': get(l:m, 'rhs', ''),
                \ })
        endfor
        return l:out
    endif

    let l:lines = split(execute(a:mode ==# 'n' ? 'nmap' : a:mode . 'map'), "\n")
    for l:line in l:lines
        let l:parts = matchlist(l:line, '^\S*\s\+\(\S\+\)\s\+[*&@ ]*\(.*\)$')
        if empty(l:parts) | continue | endif
        call add(l:out, {
            \ 'lhs': l:parts[1],
            \ 'display': l:parts[1],
            \ 'rhs': l:parts[2],
            \ })
    endfor
    return l:out
endfunction

function! s:is_internal(entry) abort
    for l:s in [a:entry.lhs, a:entry.display]
        if l:s =~# "^\<Plug>" || l:s =~# "^\<SNR>"
            return 1
        endif
        if l:s =~# '^<Plug>' || l:s =~# '^<SNR>'
            return 1
        endif
    endfor
    return 0
endfunction

function! wplus#health#shadowed_maps(...) abort
    let l:mode = a:0 > 0 ? a:1 : 'n'
    let l:maps = filter(s:collect(l:mode), '!s:is_internal(v:val)')
    let l:by_short = {}

    for l:a in l:maps
        if empty(l:a.lhs) | continue | endif
        if index(s:allowed_prefixes, l:a.lhs) >= 0 | continue | endif
        for l:b in l:maps
            if l:a.lhs ==# l:b.lhs | continue | endif
            if len(l:b.lhs) <= len(l:a.lhs) | continue | endif
            if strpart(l:b.lhs, 0, len(l:a.lhs)) ==# l:a.lhs
                if !has_key(l:by_short, l:a.display)
                    let l:by_short[l:a.display] = []
                endif
                call add(l:by_short[l:a.display], l:b.display)
            endif
        endfor
    endfor

    let l:found = []
    for [l:short, l:shadows] in items(l:by_short)
        call add(l:found, {
            \ 'short': l:short,
            \ 'shadows': sort(l:shadows),
            \ 'mode': l:mode,
            \ })
    endfor

    return sort(l:found, {a, b -> len(b.shadows) - len(a.shadows)})
endfunction

function! wplus#health#hijacked_native_keys() abort
    let l:bad = []
    for l:key in s:native_keys
        if !empty(maparg(l:key, 'n'))
            call add(l:bad, l:key)
        endif
    endfor
    return l:bad
endfunction

function! wplus#health#misowned_maps() abort
    let l:bad = []
    for [l:lhs, l:want] in items(s:owners)
        let l:rhs = maparg(l:lhs, 'n')
        if l:rhs !~# l:want
            call add(l:bad, {'lhs': l:lhs, 'want': l:want, 'got': l:rhs})
        endif
    endfor
    return l:bad
endfunction

function! wplus#health#unknown_options() abort
    let l:unknown = []
    for [l:key, l:val] in items(g:)
        if l:key =~# '^wplus_' && index(s:known_options, l:key) == -1
            call add(l:unknown, l:key)
        endif
    endfor
    return sort(l:unknown)
endfunction

function! wplus#health#check() abort
    let l:lines = []
    call add(l:lines, '==============================================================================')
    call add(l:lines, '  vim-wplus Health Check Report')
    call add(l:lines, '==============================================================================')
    call add(l:lines, '')

    " 1. Vim Build & Features
    call add(l:lines, '1. Vim Environment & Features')
    call add(l:lines, '   Vim Version: ' . (exists('v:versionlong') ? v:versionlong : v:version))
    let l:feats = ['job', 'channel', 'popupwin', 'signs', 'textprop']
    for l:f in l:feats
        let l:has_f = has(l:f)
        call add(l:lines, printf('   %-12s [%s]', '+' . l:f, l:has_f ? 'OK' : 'FAIL'))
    endfor
    call add(l:lines, '')

    " 2. Modules & Load Errors
    call add(l:lines, '2. Modules & Startup Hygiene')
    let l:errs = get(g:, 'wplus_load_errors', [])
    if empty(l:errs)
        call add(l:lines, '   [OK] All modules loaded cleanly without errors.')
    else
        call add(l:lines, printf('   [FAIL] %d module load error(s) recorded:', len(l:errs)))
        for l:err in l:errs
            call add(l:lines, '     - ' . l:err)
        endfor
    endif
    call add(l:lines, '')

    " 3. External Binaries
    call add(l:lines, '3. External Tools & Binaries')
    let l:tools = ['git', 'ctags', 'rg', 'ag', 'curl', 'python3', 'gopls', 'clangd', 'pyright-langserver', 'rust-analyzer', 'dart']
    for l:t in l:tools
        let l:path = exepath(l:t)
        if !empty(l:path)
            call add(l:lines, printf('   %-20s [OK] %s', l:t, l:path))
        else
            call add(l:lines, printf('   %-20s [NOT FOUND]', l:t))
        endif
    endfor
    call add(l:lines, '')

    " 4. LSP Status
    call add(l:lines, '4. LSP Server Status')
    if exists('g:autoloaded_wplus_lsp')
        call add(l:lines, '   LSP module loaded.')
    else
        call add(l:lines, '   LSP module not loaded.')
    endif
    call add(l:lines, '')

    " 5. AI Provider Configuration
    call add(l:lines, '5. AI Provider Configuration')
    let l:provider = get(g:, 'wplus_ai_provider', 'openai')
    let l:model    = get(g:, 'wplus_ai_model', '(default)')
    let l:key      = get(g:, 'wplus_ai_api_key', '')
    call add(l:lines, '   Provider:  ' . l:provider)
    call add(l:lines, '   Model:     ' . l:model)
    if l:provider ==# 'ollama'
        call add(l:lines, '   Host:      ' . get(g:, 'wplus_ai_ollama_host', 'http://localhost:11434'))
        call add(l:lines, '   API Key:   [NOT REQUIRED for Ollama]')
    else
        call add(l:lines, '   API Key:   ' . (!empty(l:key) ? '[OK] Configured' : '[WARNING] Missing API Key'))
    endif
    call add(l:lines, '')

    " 6. Keymap Conflicts
    call add(l:lines, '6. Keymap Conflicts & Shadows')
    let l:hijacked = wplus#health#hijacked_native_keys()
    if empty(l:hijacked)
        call add(l:lines, '   [OK] No native keys hijacked.')
    else
        call add(l:lines, '   [FAIL] Hijacked native keys: ' . join(l:hijacked, ', '))
    endif

    let l:shadowed = wplus#health#shadowed_maps('n')
    if empty(l:shadowed)
        call add(l:lines, '   [OK] No shadowed Normal-mode mappings.')
    else
        call add(l:lines, printf('   [FAIL] %d shadowed mapping(s):', len(l:shadowed)))
        for l:item in l:shadowed
            call add(l:lines, printf('     - %s shadows %s', l:item.short, join(l:item.shadows, ', ')))
        endfor
    endif
    call add(l:lines, '')

    " 7. Global Options Validation
    call add(l:lines, '7. Unrecognized Global Options')
    let l:unknown = wplus#health#unknown_options()
    if empty(l:unknown)
        call add(l:lines, '   [OK] All g:wplus_* options are recognized.')
    else
        call add(l:lines, printf('   [WARNING] %d unrecognized g:wplus_* option(s):', len(l:unknown)))
        for l:u in l:unknown
            call add(l:lines, '     - g:' . l:u)
        endfor
    endif
    call add(l:lines, '')

    " Display in window
    let l:existing = bufnr('__WplusHealth__')
    if l:existing != -1 && bufexists(l:existing)
        execute 'buffer' l:existing
    else
        enew
        silent! execute 'file __WplusHealth__'
    endif
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nomodifiable
    setlocal modifiable
    silent %delete _
    call setline(1, l:lines)
    setlocal nomodifiable
    syntax clear
    syntax match WplusHealthHeader /^===.*===$/
    syntax match WplusHealthSection /^[0-9]\+\..*$/
    syntax match WplusHealthOk /\[OK\]/
    syntax match WplusHealthFail /\[FAIL\]/
    syntax match WplusHealthWarn /\[WARNING\]/
    hi default link WplusHealthHeader Title
    hi default link WplusHealthSection Statement
    hi default link WplusHealthOk DiffAdd
    hi default link WplusHealthFail ErrorMsg
    hi default link WplusHealthWarn WarningMsg
    nnoremap <buffer> <silent> q :close<CR>
endfunction

function! wplus#health#setup() abort
    command! WplusHealth call wplus#health#check()
endfunction
