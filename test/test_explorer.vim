" test/test_explorer.vim — Unit tests for wplus file explorer

function! Test_explorer_normalize_and_item_at() abort
    call wplus#explorer#setup()
    
    " Test toggle opens explorer buffer
    call wplus#explorer#toggle()
    let l:buf = bufnr('^WplusExplorer$')
    call assert_true(l:buf != -1, 'Explorer buffer should be created on toggle')
    call assert_equal('wplus-explorer', getbufvar(l:buf, '&filetype'), 'Filetype should be wplus-explorer')
    
    " Close explorer
    call wplus#explorer#toggle()
    call assert_equal(-1, bufwinid(l:buf), 'Explorer window should be closed on second toggle')
endfunction

function! Test_explorer_ignore_files() abort
    let g:wplus_explorer_ignore = ['test_ignore_file.txt']
    call wplus#explorer#setup()
    
    " Create temp test directory
    let l:tmpdir = tempname()
    call mkdir(l:tmpdir, 'p')
    call writefile(['hello'], l:tmpdir . '/visible.txt')
    call writefile(['secret'], l:tmpdir . '/test_ignore_file.txt')
    
    let l:save_cwd = getcwd()
    execute 'cd' fnameescape(l:tmpdir)
    
    call wplus#explorer#toggle()
    let l:lines = getline(1, '$')
    
    let l:has_visible = 0
    let l:has_ignored = 0
    for l:line in l:lines
        if l:line =~# 'visible\.txt' | let l:has_visible = 1 | endif
        if l:line =~# 'test_ignore_file\.txt' | let l:has_ignored = 1 | endif
    endfor
    
    call assert_true(l:has_visible, 'visible.txt should be in the tree')
    call assert_false(l:has_ignored, 'Ignored file should not be rendered in the tree')
    
    call wplus#explorer#toggle()
    execute 'cd' fnameescape(l:save_cwd)
    call delete(l:tmpdir, 'rf')
    let g:wplus_explorer_ignore = []
endfunction
