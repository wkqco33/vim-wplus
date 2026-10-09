" test/test_lsp_multi_root.vim — LSP server instances are isolated by project root

function! Test_lsp_keeps_one_server_per_open_project_root() abort
    call wplus#lsp#setup()
    let l:old_servers = deepcopy(g:wplus_lsp_servers)
    let l:tmp = tempname()
    let l:root_a = l:tmp . '/project-a'
    let l:root_b = l:tmp . '/project-b'
    call mkdir(l:root_a . '/.git', 'p')
    call mkdir(l:root_b . '/.git', 'p')
    let l:file_a = l:root_a . '/a.py'
    let l:file_b = l:root_b . '/b.py'
    call writefile(['print("a")'], l:file_a)
    call writefile(['print("b")'], l:file_b)

    try
        let g:wplus_lsp_servers = {'python': ['cat']}
        execute 'edit' fnameescape(l:file_a)
        setfiletype python
        let l:key_a = wplus#lsp#_test_current_server_key()

        execute 'edit' fnameescape(l:file_b)
        setfiletype python
        let l:key_b = wplus#lsp#_test_current_server_key()

        call assert_notequal(l:key_a, l:key_b, 'Different project roots need distinct server identities')
        call assert_equal(2, wplus#lsp#_test_server_count(), 'Both project servers should remain active')

        execute 'edit' fnameescape(l:file_a)
        setfiletype python
        call assert_equal(l:key_a, wplus#lsp#_test_current_server_key(), 'Returning to a project should reactivate its server')
        call assert_equal(2, wplus#lsp#_test_server_count(), 'Switching roots must not terminate the other project server')
    finally
        call wplus#lsp#stop_all()
        let g:wplus_lsp_servers = l:old_servers
        call delete(l:tmp, 'rf')
    endtry
endfunction
