" wplus/health.vim — diagnostics for the wplus setup
" Phase 0 ships only the keymap-conflict scanner, which both test/test_keymaps.vim
" and (later) :WplusHealth consume so there is exactly one implementation of
" conflict detection in the codebase.

if exists('g:autoloaded_wplus_health') | finish | endif
let g:autoloaded_wplus_health = 1

" Keys whose native meaning must never be taken over by a global mapping.
" '.'     repeat last change
" <C-a>   increment number under cursor
" <C-x>   decrement number under cursor
let s:native_keys = ['.', "\<C-a>", "\<C-x>"]

" Canonical owner for keys that more than one module has historically claimed.
" Value is a substring expected in the mapping's rhs.
let s:owners = {
    \ ']h': 'gitgutter#next_hunk',
    \ '[h': 'gitgutter#prev_hunk',
    \ }

" Prefix pairs that are intentional and cost nothing in practice.
"
" An operator ('gc', 'ys') is always followed immediately by a motion, and Vim
" resolves the ambiguity on that next keystroke rather than waiting for
" 'timeoutlen' -- the timeout only applies if the user stops typing, which is
" meaningless mid-operator. The doubled form ('gcc', 'yss') meaning
" "apply to this line" is the established vim-commentary / vim-surround idiom.
"
" This is emphatically NOT true of a complete action like <leader>b: the user
" types it and stops, so Vim must wait out the full timeout every time.
let s:allowed_prefixes = ['gc', 'ys', 'ds', 'cs']

function! wplus#health#native_keys() abort
    return copy(s:native_keys)
endfunction

function! wplus#health#owners() abort
    return copy(s:owners)
endfunction

" Collect mappings for a mode as a list of {'lhs': raw-key-sequence, 'rhs': ...}.
" Uses maplist() when available (Vim 9.0+) and falls back to parsing :map output.
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

    " Fallback: scrape :map output. Only used on builds without maplist().
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

" A mapping is "internal" if it is never typed directly, so a prefix relation
" between two of them is harmless. Checked against both the raw key sequence and
" the displayed form, because <Plug>/<SNR> arrive as raw K_SPECIAL bytes from
" maplist() but as literal text from the :map-scraping fallback.
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

" Find complete mappings that are a strict prefix of another mapping.
" Typing the short one forces Vim to wait 'timeoutlen' for the longer one.
"
" Results are grouped by the offending short mapping -- one <leader> hijack
" shadows every leader mapping in the plugin, and reporting that as 40 separate
" findings buries everything else.
"
" Returns a list of {'short': display, 'shadows': [display, ...], 'mode': mode},
" ordered with the widest-reaching offender first.
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

" Keys from s:native_keys that currently have a global mapping.
function! wplus#health#hijacked_native_keys() abort
    let l:bad = []
    for l:key in s:native_keys
        if !empty(maparg(l:key, 'n'))
            call add(l:bad, l:key)
        endif
    endfor
    return l:bad
endfunction

" Keys in s:owners whose mapping does not point at the expected owner.
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
