" test/test_keys.vim — runtime keymap/command/module reference (:WplusKeys).
"
" The reference must be built from what Vim actually registered (maplist() /
" getscriptinfo()), not from a hand-maintained table, so the docs cannot drift
" away from the running configuration again.

" Resolved at source time: inside a function <sfile> points at the caller.
let s:repo = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')

function! s:by_lhs(entries, lhs) abort
    return filter(copy(a:entries), 'v:val.lhs ==# a:lhs')
endfunction

function! s:by_name(entries, name) abort
    return filter(copy(a:entries), 'v:val.name ==# a:name')
endfunction

function! Test_keys_lists_registered_mappings() abort
    let s:entries = wplus#keys#entries('keys')
    call assert_true(len(s:entries) > 50,
        \ 'runtime mapping list looks too small: ' . len(s:entries))

    " Every entry must carry what the UI shows: mode, lhs, rhs, owning module.
    for s:entry in s:entries
        call assert_true(!empty(s:entry.mode), 'missing mode: ' . string(s:entry))
        call assert_true(!empty(s:entry.lhs), 'missing lhs: ' . string(s:entry))
        call assert_true(!empty(s:entry.module), 'missing module: ' . string(s:entry))
        call assert_true(!empty(s:entry.text), 'missing display text: ' . string(s:entry))
    endfor

    " <Plug>/<SNR> internals are implementation details, not user-facing keys.
    for s:entry in s:entries
        call assert_notmatch('^<Plug>\|^<SNR>\|^\x80', s:entry.lhs,
            \ 'internal mapping leaked into the reference: ' . s:entry.lhs)
    endfor

    " The leader must be normalized so the list is readable and greppable.
    let s:ld = s:by_lhs(s:entries, '<leader>ld')
    call assert_equal(1, len(s:ld), '<leader>ld should be listed once (normal mode)')
    call assert_equal('lsp', s:ld[0].module)
    call assert_match('WlspDefinition', s:ld[0].rhs)
    for s:entry in s:entries
        call assert_notmatch('^<Space>', s:entry.lhs,
            \ 'leader prefix must be normalized to <leader>: ' . s:entry.lhs)
    endfor
endfunction

function! Test_keys_lists_commands_with_reverse_index() abort
    let s:entries = wplus#keys#entries('commands')
    call assert_true(len(s:entries) > 50,
        \ 'runtime command list looks too small: ' . len(s:entries))

    let s:hover = s:by_name(s:entries, 'WlspHover')
    call assert_equal(1, len(s:hover), 'WlspHover should be listed')
    call assert_equal('lsp', s:hover[0].module)
    call assert_true(index(s:hover[0].keys, '<leader>lh') >= 0,
        \ 'command should know which key invokes it: ' . string(s:hover[0].keys))

    let s:bdelete = s:by_name(s:entries, 'Bdelete')
    call assert_equal(1, len(s:bdelete), 'Bdelete should be listed')
    call assert_equal('bufdelete', s:bdelete[0].module)

    " Commands outside wplus must not be attributed to it.
    call assert_equal([], s:by_name(s:entries, 'Explore'))
    call assert_equal([], s:by_name(s:entries, 'DoMatchParen'))
endfunction

function! Test_keys_lists_module_state() abort
    let s:entries = wplus#keys#entries('modules')
    call assert_true(len(s:entries) >= 30,
        \ 'every module should be listed: ' . len(s:entries))

    let s:lsp = s:by_name(s:entries, 'lsp')
    call assert_equal(1, len(s:lsp), 'lsp module should be listed')
    call assert_equal(1, s:lsp[0].enabled, 'lsp is enabled by default')
    call assert_true(s:lsp[0].keys > 0, 'lsp owns keymaps')
    call assert_true(index(s:lsp[0].modes, 'n') >= 0, 'lsp has normal-mode maps')

    " A disabled module reports enabled=0; the key counts stay truthful about
    " what is still registered (disabling after startup does not unmap anything).
    let s:saved = get(g:, 'wplus_fold_enabled', 1)
    let g:wplus_fold_enabled = 0
    let s:fold = s:by_name(wplus#keys#entries('modules'), 'fold')
    call assert_equal(0, s:fold[0].enabled, 'disabled module must report enabled=0')
    let g:wplus_fold_enabled = s:saved

    " Command-only modules must show 0 keys without looking unloaded.
    let s:session = s:by_name(wplus#keys#entries('modules'), 'session')
    call assert_equal(0, s:session[0].keys, 'session owns no keymaps')
    call assert_true(s:session[0].commands >= 3, 'session should own its commands')
endfunction

function! Test_keys_render_filters() abort
    let s:lines = wplus#keys#render('keys', 'lsp')
    call assert_true(len(s:lines) > 0, 'filter should keep lsp entries')
    for s:line in s:lines
        call assert_match('\clsp', s:line, 'unrelated line survived the filter: ' . s:line)
    endfor

    let s:all = wplus#keys#render('keys', '')
    call assert_true(len(s:all) > 50, 'empty filter must show everything')

    let s:cmd_lines = wplus#keys#render('commands', 'WlspHover')
    call assert_true(len(s:cmd_lines) >= 1, 'command filter should match WlspHover')
    call assert_match('WlspHover', s:cmd_lines[0])

    let s:mod_lines = wplus#keys#render('modules', '')
    call assert_true(len(s:mod_lines) >= 30, 'module view should list every module')
    call assert_match('\[on', s:mod_lines[0], 'module lines must show enabled state')

    " An impossible query must render an explicit empty state, not a blank popup.
    let s:none = wplus#keys#render('keys', 'zzzznotakey')
    call assert_equal(1, len(s:none))
    call assert_match('no match', s:none[0])
endfunction

function! Test_keys_ui_and_commands() abort
    for s:cmd in ['WplusKeys', 'WplusCommands', 'WplusModules']
        call assert_equal(2, exists(':' . s:cmd), ':' . s:cmd . ' should be defined')
    endfor

    " The browser is reachable without typing a command.
    call assert_match('WplusKeys', maparg(g:mapleader . '?', 'n'))

    " Rendering into a buffer is the no-popup fallback; it must never raise.
    call wplus#keys#open('keys', 'lsp')
    let s:buf = bufnr('__WplusKeys__')
    if exists('*popup_create') && !empty(popup_list())
        " Popup path: nothing to assert beyond "it opened".
        call assert_true(bufexists(s:buf) || !empty(popup_list()))
        call popup_clear()
    else
        call assert_true(bufexists(s:buf), 'buffer fallback should create __WplusKeys__')
        call assert_true(len(getbufline(s:buf, 1, '$')) > 1, 'fallback buffer must have content')
        execute 'silent! bwipeout!' s:buf
    endif
endfunction

function! Test_keys_docs_cover_every_leader_mapping() abort
    " Single source of truth: the shipped help file must document every
    " <leader> mapping that is actually registered with default settings.
    let s:help_path = s:repo . '/doc/wplus.txt'
    call assert_true(filereadable(s:help_path), 'help file missing: ' . s:help_path)
    let s:help = join(readfile(s:help_path), "\n")
    let s:missing = []
    for s:entry in wplus#keys#entries('keys')
        if s:entry.lhs !~# '^<leader>'
            continue
        endif
        if s:help !~# '\V' . escape(s:entry.lhs, '\') . '\m'
            if index(s:missing, s:entry.lhs) < 0
                call add(s:missing, s:entry.lhs)
            endif
        endif
    endfor
    call assert_equal([], s:missing,
        \ 'undocumented <leader> mappings: ' . join(s:missing, ', '))

    call assert_true(s:help =~# '\*wplus-keymaps\*',
        \ 'help file must provide the *wplus-keymaps* tag')
endfunction

function! Test_keys_target_never_executes_mappings() abort
    " <CR> must reveal the backing command, not run a side-effecting mapping.
    let s:ld = s:by_lhs(wplus#keys#entries('keys'), '<leader>ld')
    call assert_equal({'type': 'command', 'value': 'WlspDefinition'},
        \ wplus#keys#target(s:ld[0]))

    let s:cmd = s:by_name(wplus#keys#entries('commands'), 'WlspHover')
    call assert_equal({'type': 'command', 'value': 'WlspHover'},
        \ wplus#keys#target(s:cmd[0]))

    " A mapping with no command behind it opens the module help instead.
    let s:gc = filter(wplus#keys#entries('keys'), 'v:val.lhs ==# "gc" && v:val.mode ==# "n"')
    call assert_equal({'type': 'help', 'value': 'wplus-commentary'},
        \ wplus#keys#target(s:gc[0]))

    call assert_equal({}, wplus#keys#target({}))
endfunction
