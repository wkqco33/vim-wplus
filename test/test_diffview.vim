" test/test_diffview.vim — Unit tests for diffview module

function! Test_diffview_setup_and_empty_guard() abort
    call wplus#diffview#setup()
    enew!
    setlocal buftype=nofile noswapfile
    
    " Opening diff without valid file should warn and not crash
    call wplus#diffview#open()
    
    let l:diffbuf = bufnr('__WplusDiff__')
    call assert_equal(-1, l:diffbuf, 'Diff buffer should not open for empty unnamed file')
    
    bwipeout!
endfunction
