" test_keymaps.vim — mapping ownership, prefix shadowing, native-key hijacks.
"
" A plain "duplicate LHS" scan cannot catch the ]h/[h collision: :nmap output
" shows only the winner. Ownership is asserted explicitly instead.

function! Test_keymaps_hygiene() abort
" ── native keys must stay native ─────────────────────────────────────────

let s:hijacked = wplus#health#hijacked_native_keys()
call assert_equal([], s:hijacked,
    \ 'native keys must not be globally remapped: ' . string(s:hijacked))
for s:key in ['.', '<C-a>', '<C-x>', '<C-n>', '<C-p>', '<C-s>', '<Tab>', '"', '@',
            \ 'K', 'S', 'gd', 'gr', ']d', '[d']
    call assert_true(index(wplus#health#native_keys(), s:key) >= 0,
        \ 'native key must be included in the hygiene check: ' . string(s:key))
endfor

" Feature mappings remain available under namespaced keys.
call assert_match('wplus#multicursor#add_next', maparg(g:mapleader . 'vn', 'n'))
call assert_match('wplus#register#show', maparg(g:mapleader . 'rp', 'n'))
call assert_match('wplus#register#show', maparg(g:mapleader . 'rP', 'n'))
call assert_match('wplus#commentary#toggle_line', maparg(g:mapleader . 'cc', 'n'))
call assert_match('wplus#surround#yss', maparg(g:mapleader . 'ys', 'n'))
call assert_match('wplus#surround#visual_await', maparg(g:mapleader . 'vs', 'x'))

" The checker must inspect Insert and Visual mappings, not only Normal mode.
inoremap <C-n> <Nop>
call assert_true(index(wplus#health#hijacked_native_keys(), 'i:<C-n>') >= 0,
    \ 'Insert-mode native key overrides must be reported')
iunmap <C-n>
xnoremap S <Nop>
call assert_true(index(wplus#health#hijacked_native_keys(), 'x:S') >= 0,
    \ 'Visual-mode native key overrides must be reported')
xunmap S

" ── contested keys must belong to the canonical owner ────────────────────

let s:misowned = wplus#health#misowned_maps()
for s:bad in s:misowned
    call assert_report(printf('%s should map to %s but maps to %s',
        \ s:bad.lhs, s:bad.want, string(s:bad.got)))
endfor

" ── no complete mapping may be a strict prefix of another ────────────────
" Typing the short one costs a full 'timeoutlen' wait every time.

for s:mode in ['n', 'x', 'i', 's', 'o', 'c', 't']
    let s:shadowed = wplus#health#shadowed_maps(s:mode)
    for s:entry in s:shadowed
        call assert_report(printf('%s-mode %s is a complete mapping but also a prefix of %d others: %s',
            \ s:mode, s:entry.short, len(s:entry.shadows),
            \ join(s:entry.shadows[0:5], ' ') . (len(s:entry.shadows) > 6 ? ' ...' : '')))
    endfor
endfor

" A synthetic Insert-mode prefix verifies that non-Normal scans are effective.
inoremap <F13> x
inoremap <F13><F14> y
let s:insert_shadows = wplus#health#shadowed_maps('i')
call assert_true(!empty(filter(s:insert_shadows, 'v:val.short ==# "<F13>"')),
    \ 'Insert-mode mapping prefixes must be detected')
iunmap <F13><F14>
iunmap <F13>

" ── commands the docs promise must exist ─────────────────────────────────
" Cheap generic guard against the :Wharoon / :WdiffviewFile class of drift.

let s:commands = [
    \ 'WexplorerToggle',
    \ 'WfindFiles',
    \ 'WfindBuffers',
    \ 'Wgrep',
    \ 'Bdelete',
    \ 'Bwipeout',
    \ 'WaiComment',
    \ 'WaiComplete',
    \ 'WaiRefactor',
    \ 'WharpoonAdd',
    \ 'WharpoonRemove',
    \ 'WharpoonList',
    \ 'WterminalToggle',
    \ ]

for s:cmd in s:commands
    call assert_true(exists(':' . s:cmd) == 2,
        \ 'command :' . s:cmd . ' should be defined')
endfor
endfunction
