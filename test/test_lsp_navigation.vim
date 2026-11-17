" test/test_lsp_navigation.vim — Test typeDefinition/implementation gating

function! Test_lsp_default_mappings_preserve_native_keys() abort
    call wplus#lsp#setup()
    call assert_equal(0, g:wplus_lsp_native_keymaps,
        \ 'native LSP key overrides must be opt-in')

    for l:key in ['K', 'gd', 'gy', 'gr', ']d', '[d']
        call assert_equal('', maparg(l:key, 'n'),
            \ 'default LSP setup must preserve native mapping: ' . l:key)
    endfor
    call assert_match('WlspDefinition', maparg(g:mapleader . 'ld', 'n'))
    call assert_match('WlspHover', maparg(g:mapleader . 'lh', 'n'))
endfunction

function! Test_lsp_native_keymaps_are_explicit_opt_in() abort
    let g:wplus_lsp_native_keymaps = 1
    call wplus#lsp#setup()
    call assert_match('WlspDefinition', maparg('gd', 'n'))
    call assert_match('WlspSignatureHelp', maparg('<C-s>', 'i'))

    for l:key in ['K', 'gd', 'gy', 'gr', ']d', '[d']
        execute 'silent! nunmap' l:key
    endfor
    silent! iunmap <C-s>
    let g:wplus_lsp_native_keymaps = 0
    call wplus#lsp#setup()
endfunction

function! Test_lsp_navigation_capability_gating() abort
    call wplus#lsp#setup()
    call wplus#lsp#_test_set_caps('go', {
        \ 'typeDefinitionProvider': v:true,
        \ 'implementationProvider': v:false,
        \ })
    call assert_true(wplus#lsp#_test_supports('go', 'textDocument/typeDefinition'), 'typeDefinition should be supported')
    call assert_false(wplus#lsp#_test_supports('go', 'textDocument/implementation'), 'implementation should be unsupported')
endfunction

function! Test_lsp_navigation_goto_location_list() abort
    call wplus#lsp#setup()
    let l:tmpdir = tempname()
    call mkdir(l:tmpdir, 'p')
    let l:file = l:tmpdir . '/a.go'
    call writefile(['package main', 'var X = 1', 'var Y = 2'], l:file)
    execute 'edit ' . fnameescape(l:file)

    " A list of locations should jump to the first one.
    let l:result = [{
        \ 'uri': 'file://' . substitute(fnamemodify(l:file, ':p'), '\\', '/', 'g'),
        \ 'range': {'start': {'line': 1, 'character': 4}, 'end': {'line': 1, 'character': 5}},
        \ }]
    call wplus#lsp#_test_goto_location(l:result)
    call assert_equal(2, line('.'), 'Should jump to the first location line')
    call assert_equal(5, col('.'), 'Should jump to the first location col')

    call delete(l:file)
    call delete(l:tmpdir, 'rf')
endfunction
