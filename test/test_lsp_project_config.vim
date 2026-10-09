" test/test_lsp_project_config.vim — Test project-scoped LSP server resolution

function! Test_lsp_setup_does_not_duplicate_timeout_timer() abort
    call wplus#lsp#setup()
    let l:first = wplus#lsp#_test_timeout_timer_id()
    call wplus#lsp#setup()
    call assert_equal(l:first, wplus#lsp#_test_timeout_timer_id(),
        \ 'Repeated setup must reuse the request-timeout timer')
endfunction

function! Test_lsp_uri_round_trips_paths_with_reserved_characters() abort
    call wplus#lsp#setup()
    let l:path = '/tmp/wplus project/#file%20.vim'
    let l:uri = wplus#lsp#_test_get_uri(l:path)
    call assert_equal('file:///tmp/wplus%20project/%23file%2520.vim', l:uri)
    call assert_equal(l:path, wplus#lsp#_test_decode_uri_path(l:uri))

    let l:unicode_path = '/tmp/wplus-한.vim'
    let l:unicode_uri = wplus#lsp#_test_get_uri(l:unicode_path)
    call assert_equal(l:unicode_path, wplus#lsp#_test_decode_uri_path(l:unicode_uri))
endfunction

function! Test_lsp_project_config_simple_list() abort
    call wplus#lsp#setup()
    let g:wplus_lsp_servers = {'go': ['gopls']}
    call assert_equal(['gopls'], wplus#lsp#_test_resolve_server_config('go', '/proj'), 'A plain list should be returned as-is')
endfunction

function! Test_lsp_project_config_dict_cmd() abort
    call wplus#lsp#setup()
    let g:wplus_lsp_servers = {'go': {'cmd': ['gopls']}}
    call assert_equal(['gopls'], wplus#lsp#_test_resolve_server_config('go', '/proj'), 'A dict with cmd should return its cmd')
endfunction

function! Test_lsp_project_config_matching_root() abort
    call wplus#lsp#setup()
    let g:wplus_lsp_servers = {'go': {'cmd': ['gopls'], 'root': '/projA'}}
    call assert_equal(['gopls'], wplus#lsp#_test_resolve_server_config('go', '/projA'), 'A dict whose root matches should be used')
endfunction

function! Test_lsp_project_config_nonmatching_root() abort
    call wplus#lsp#setup()
    let g:wplus_lsp_servers = {'go': {'cmd': ['gopls'], 'root': '/projA'}}
    call assert_equal([], wplus#lsp#_test_resolve_server_config('go', '/projB'), 'A dict whose root does not match should be skipped')
endfunction

function! Test_lsp_project_config_list_of_dicts() abort
    call wplus#lsp#setup()
    let g:wplus_lsp_servers = {'go': [
        \ {'root': '/projA', 'cmd': ['gopls-a']},
        \ {'cmd': ['gopls-default']},
        \ ]}
    call assert_equal(['gopls-a'], wplus#lsp#_test_resolve_server_config('go', '/projA'), 'First matching root should win')
    call assert_equal(['gopls-default'], wplus#lsp#_test_resolve_server_config('go', '/projB'), 'Fallback dict without root should be used')
endfunction
