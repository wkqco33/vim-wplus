" wplus/keys.vim — Runtime keymap, command and module reference (:WplusKeys)
"
" The list is built from what Vim actually registered (maplist(), :command,
" getscriptinfo()) instead of a hand-maintained table, so the shipped help and
" the running configuration cannot drift apart.

if exists('g:autoloaded_wplus_keys') | finish | endif
let g:autoloaded_wplus_keys = 1

" Repo root: this file lives in <root>/autoload/wplus/keys.vim.
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h:h')
let s:module_dir = s:root . '/autoload/wplus/'
let s:core_script = s:root . '/plugin/wplus.vim'

let s:views = ['keys', 'commands', 'modules']

" ── script/module attribution ─────────────────────────────────────────────

" Map script id → wplus module name using getscriptinfo(). Cached: the set only
" changes when a new script is sourced, which cannot happen while the popup is
" open.
let s:sid_cache = {}

function! s:module_from_path(path) abort
    let l:path = a:path
    if empty(l:path) | return '' | endif
    if l:path ==# s:core_script
        return 'core'
    endif
    if strpart(l:path, 0, len(s:module_dir)) !=# s:module_dir
        return ''
    endif
    let l:rel = strpart(l:path, len(s:module_dir))
    if l:rel !~# '\.vim$' | return '' | endif
    " autoload/wplus/ai/provider.vim belongs to the ai module.
    return split(substitute(l:rel, '\.vim$', '', ''), '/')[0]
endfunction

function! s:module_of_sid(sid) abort
    " maplist() omits 'sid' for mappings that were not defined in a script, so
    " such an entry arrives here as 0. getscriptinfo({'sid': 0}) raises
    " E475 ('Invalid value for argument sid') on every Vim build, and a single
    " entry must not abort the whole reference build.
    if a:sid <= 0
        return ''
    endif
    if has_key(s:sid_cache, a:sid)
        return s:sid_cache[a:sid]
    endif
    let l:found = ''
    if exists('*getscriptinfo')
        for l:info in getscriptinfo({'sid': a:sid})
            let l:found = s:module_from_path(get(l:info, 'name', ''))
            if !empty(l:found) | break | endif
        endfor
    endif
    let s:sid_cache[a:sid] = l:found
    return l:found
endfunction

" Fallbacks keep the reference useful on Vims without getscriptinfo(): the
" autoload call in the rhs still names the owning module.
function! s:module_from_text(text) abort
    let l:m = matchstr(a:text, 'wplus#\zs\h\w*\ze#')
    return empty(l:m) ? '' : l:m
endfunction

" ── leader normalization ──────────────────────────────────────────────────

function! s:normalize_lhs(lhs) abort
    " maplist() renders special keys in <...> form, so a space leader arrives as
    " "<Space>ld" rather than " ld". Accept both spellings.
    let l:leader = get(g:, 'mapleader', '\')
    for l:lead in [l:leader, keytrans(l:leader)]
        if !empty(l:lead) && strpart(a:lhs, 0, len(l:lead)) ==# l:lead
            return '<leader>' . strpart(a:lhs, len(l:lead))
        endif
    endfor
    return a:lhs
endfunction

" maplist() reports mode ' ' for "normal, visual and operator-pending".
function! s:normalize_mode(mode) abort
    return a:mode ==# ' ' ? 'nvo' : a:mode
endfunction

function! s:truncate(text, width) abort
    let l:text = substitute(a:text, '\n', ' ', 'g')
    if strchars(l:text) <= a:width | return l:text | endif
    return strcharpart(l:text, 0, a:width - 1) . '…'
endfunction

" ── collection: keymaps ───────────────────────────────────────────────────

function! s:collect_keys() abort
    let l:out = []
    if !exists('*maplist')
        return l:out
    endif
    for l:m in maplist()
        let l:lhs = get(l:m, 'lhs', '')
        " <Plug>/<SNR> are wiring, not surfaces a user can type.
        if l:lhs =~# '^<Plug>' || l:lhs =~# '^<SNR>' | continue | endif
        let l:rhs = get(l:m, 'rhs', '')
        let l:module = s:module_of_sid(get(l:m, 'sid', 0))
        if empty(l:module)
            let l:module = s:module_from_text(l:rhs)
        endif
        if empty(l:module)
            " Not ours: another plugin or a user mapping.
            continue
        endif
        let l:mode = s:normalize_mode(get(l:m, 'mode', 'n'))
        let l:lhs = s:normalize_lhs(l:lhs)
        call add(l:out, {
            \ 'kind': 'key',
            \ 'mode': l:mode,
            \ 'lhs': l:lhs,
            \ 'rhs': l:rhs,
            \ 'module': l:module,
            \ 'buffer': get(l:m, 'buffer', 0),
            \ 'text': printf('%-4s %-20s %-34s [%s]',
            \     l:mode, l:lhs, s:truncate(l:rhs, 34), l:module),
            \ })
    endfor
    return sort(l:out, {a, b -> a.lhs ==# b.lhs ? (a.mode ==# b.mode ? 0 : a.mode ># b.mode ? 1 : -1) : a.lhs ># b.lhs ? 1 : -1})
endfunction

" ── collection: commands ──────────────────────────────────────────────────
"
" :command truncates the Definition column and some commands are implemented
" with script-local functions, so attribution uses the verbose "Last set from"
" script path. A full scan of user commands costs well under a millisecond.

function! s:command_module(name) abort
    let l:info = execute('verbose command ' . a:name)
    let l:path = matchstr(l:info, '\vLast set from \zs[^\n]+\ze line \d+')
    if !empty(l:path)
        let l:module = s:module_from_path(expand(fnamemodify(l:path, ':p')))
        if !empty(l:module) | return l:module | endif
    endif
    return s:module_from_text(l:info)
endfunction

function! s:collect_commands(keys) abort
    let l:invoked_by = {}
    for l:key in a:keys
        for l:cmd in s:commands_in_rhs(l:key.rhs)
            if !has_key(l:invoked_by, l:cmd)
                let l:invoked_by[l:cmd] = []
            endif
            if index(l:invoked_by[l:cmd], l:key.lhs) < 0
                call add(l:invoked_by[l:cmd], l:key.lhs)
            endif
        endfor
    endfor

    let l:out = []
    for l:line in split(execute('command'), "\n")
        " Column 1 holds the command flags, including '|' for bar-terminated ones.
        let l:name = matchstr(l:line, '^\s*[!b"|]*\s*\zs\u\w*')
        if empty(l:name) | continue | endif
        let l:module = s:command_module(l:name)
        if empty(l:module) | continue | endif
        let l:callers = sort(get(l:invoked_by, l:name, []))
        call add(l:out, {
            \ 'kind': 'command',
            \ 'name': l:name,
            \ 'module': l:module,
            \ 'keys': l:callers,
            \ 'text': printf(':%-26s %-22s [%s]',
            \     s:truncate(l:name, 26),
            \     s:truncate(empty(l:callers) ? '-' : join(l:callers, ' '), 22),
            \     l:module),
            \ })
    endfor
    return sort(l:out, {a, b -> a.name ># b.name ? 1 : a.name ==# b.name ? 0 : -1})
endfunction

" Command names invoked by a mapping rhs, e.g. ":WlspHover<CR>" → WlspHover.
function! s:commands_in_rhs(rhs) abort
    let l:out = []
    let l:rest = a:rhs
    while 1
        let l:m = matchstr(l:rest, ':\zs\u\w\+')
        if empty(l:m) | break | endif
        if index(l:out, l:m) < 0 | call add(l:out, l:m) | endif
        let l:rest = strpart(l:rest, stridx(l:rest, l:m) + len(l:m))
    endwhile
    return l:out
endfunction

" ── collection: modules ───────────────────────────────────────────────────

function! s:module_names() abort
    if exists('*wplus#module_names')
        return wplus#module_names()
    endif
    let l:names = []
    for l:file in glob(s:module_dir . '*.vim', 0, 1)
        let l:names = add(l:names, fnamemodify(l:file, ':t:r'))
    endfor
    return sort(l:names)
endfunction

function! s:collect_modules(keys, commands) abort
    let l:out = []
    for l:name in s:module_names()
        let l:modes = []
        let l:key_count = 0
        for l:key in a:keys
            if l:key.module !=# l:name | continue | endif
            let l:key_count += 1
            for l:ch in split(l:key.mode, '\zs')
                if index(l:modes, l:ch) < 0 | call add(l:modes, l:ch) | endif
            endfor
        endfor
        let l:cmd_count = len(filter(copy(a:commands), 'v:val.module ==# l:name'))
        let l:enabled = get(g:, 'wplus_' . l:name . '_enabled', 1) ? 1 : 0
        call add(l:out, {
            \ 'kind': 'module',
            \ 'name': l:name,
            \ 'enabled': l:enabled,
            \ 'keys': l:key_count,
            \ 'commands': l:cmd_count,
            \ 'modes': sort(l:modes),
            \ 'text': printf('[%s] %-14s %3d keys %3d cmds  %s',
            \     l:enabled ? 'on ' : 'off',
            \     l:name,
            \     l:key_count,
            \     l:cmd_count,
            \     empty(l:modes) ? '' : join(sort(l:modes), '')),
            \ })
    endfor
    return l:out
endfunction

" ── public API ────────────────────────────────────────────────────────────

" All runtime entries for a:kind ('keys' | 'commands' | 'modules').
function! wplus#keys#entries(kind) abort
    let l:keys = s:collect_keys()
    if a:kind ==# 'keys'
        return l:keys
    endif
    let l:commands = s:collect_commands(l:keys)
    if a:kind ==# 'commands'
        return l:commands
    endif
    return s:collect_modules(l:keys, l:commands)
endfunction

function! wplus#keys#views() abort
    return copy(s:views)
endfunction

" Case-insensitive substring filter over the rendered text. Deliberately not
" fuzzy: "lsp" must not match a line that never mentions lsp.
function! wplus#keys#filter(entries, query) abort
    if empty(a:query)
        return copy(a:entries)
    endif
    let l:needle = '\c\V' . escape(a:query, '\')
    return filter(copy(a:entries), 'v:val.text =~# l:needle')
endfunction

" Display lines for a:kind, optionally filtered by a:query.
function! wplus#keys#render(kind, query) abort
    let l:entries = wplus#keys#filter(wplus#keys#entries(a:kind), a:query)
    if empty(l:entries)
        return ['  no match for: ' . a:query]
    endif
    return map(l:entries, 'v:val.text')
endfunction

" What <CR> should do with a:entry. Kept pure so the behaviour is testable:
" never execute a side-effecting mapping, only reveal what is behind it.
function! wplus#keys#target(entry) abort
    if empty(a:entry)
        return {}
    endif
    if has_key(a:entry, 'name')
        return {'type': 'command', 'value': a:entry.name}
    endif
    let l:cmds = s:commands_in_rhs(get(a:entry, 'rhs', ''))
    if !empty(l:cmds)
        return {'type': 'command', 'value': l:cmds[0]}
    endif
    let l:module = get(a:entry, 'module', '')
    if !empty(l:module)
        return {'type': 'help', 'value': 'wplus-' . l:module}
    endif
    return {}
endfunction


" ── UI entry points ──────────────────────────────────────────────────────
"
" Rendering (popup, or a buffer when +popupwin is missing) lives in
" keys/ui.vim; the collection above stays free of UI state.
function! wplus#keys#open(...) abort
    let l:view = a:0 > 0 && !empty(a:1) ? a:1 : 'keys'
    let l:query = a:0 > 1 ? a:2 : ''
    call wplus#keys#ui#open(l:view, l:query)
endfunction

function! wplus#keys#close() abort
    call wplus#keys#ui#close()
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#keys#setup() abort
    " nargs=*: the filter is free text and may contain spaces.
    command! -nargs=* -bar WplusKeys     call wplus#keys#open('keys', <q-args>)
    command! -nargs=* -bar WplusCommands call wplus#keys#open('commands', <q-args>)
    command! -nargs=* -bar WplusModules  call wplus#keys#open('modules', <q-args>)
    nnoremap <silent> <leader>? :WplusKeys<CR>
endfunction

" ── test bridges (not part of the public API) ─────────────────────────────

function! wplus#keys#_test_module_of_sid(sid) abort
    return s:module_of_sid(a:sid)
endfunction
