" test_keymaps.vim — mapping ownership, prefix shadowing, native-key hijacks.
"
" A plain "duplicate LHS" scan cannot catch the ]h/[h collision: :nmap output
" shows only the winner. Ownership is asserted explicitly instead.

" ── native keys must stay native ─────────────────────────────────────────
" Phase 0 baseline: RED for '.' (repeat.vim:12), <C-a> and <C-x>
" (multicursor.vim:236-237).

let s:hijacked = wplus#health#hijacked_native_keys()
call assert_equal([], s:hijacked,
    \ 'native keys must not be globally remapped: ' . string(s:hijacked))

" ── contested keys must belong to the canonical owner ────────────────────
" Phase 0 baseline: RED. Both gitgutter.vim:350-351 and diffview.vim:130-131
" define ]h/[h; diffview loads later and wins, and its implementation reads
" gitgutter's sign group, so the winner depends on the loser being enabled.

let s:misowned = wplus#health#misowned_maps()
for s:bad in s:misowned
    call assert_report(printf('%s should map to %s but maps to %s',
        \ s:bad.lhs, s:bad.want, string(s:bad.got)))
endfor

" ── no complete mapping may be a strict prefix of another ────────────────
" Typing the short one costs a full 'timeoutlen' wait every time.
" Phase 0 baseline: RED for <leader>b, <leader>p, <leader>m, ys, gc and
" (until Phase 1 deletes whichkey) <leader> itself.

let s:shadowed = wplus#health#shadowed_maps('n')
for s:entry in s:shadowed
    call assert_report(printf('%s is a complete mapping but also a prefix of %d others: %s',
        \ s:entry.short, len(s:entry.shadows),
        \ join(s:entry.shadows[0:5], ' ') . (len(s:entry.shadows) > 6 ? ' ...' : '')))
endfor

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
    \ ]

for s:cmd in s:commands
    call assert_true(exists(':' . s:cmd) == 2,
        \ 'command :' . s:cmd . ' should be defined')
endfor
