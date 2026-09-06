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

function! Test_diffview_find_target() abort
    let l:diff_lines = [
        \ 'diff --git a/foo.txt b/foo.txt',
        \ '--- a/foo.txt',
        \ '+++ b/foo.txt',
        \ '@@ -10,5 +20,6 @@',
        \ ' unchanged line 20',
        \ '+added line 21',
        \ '+second added 22',
        \ ' unchanged line 23',
        \ ]

    " Line index 6 in buffer (1-based: '+++ b/foo.txt' is line 3, '@@' is line 4, line 7 is '+second added 22')
    let l:target = wplus#diffview#_test_parse_diff_location(l:diff_lines, 7)
    call assert_equal('foo.txt', l:target.file)
    call assert_equal(22, l:target.lnum)
endfunction
