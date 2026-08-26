" test/test_finder.vim — Unit tests for wplus fuzzy finder

function! Test_finder_fuzzy_filtering() abort
    call wplus#finder#open(['apple', 'banana', 'apricot', 'cherry'], 'edit', 'TestFinder')
    
    let l:winid = popup_findinfo() " check popup window exists
    
    " Test filter handling C-j and C-k
    call wplus#finder#filter(0, 'a')
    call wplus#finder#filter(0, 'p')
    " Now query is 'ap', matches should be 'apple' and 'apricot'
    
    " Navigate down with C-j
    call wplus#finder#filter(0, "\<C-j>")
    
    " Close popup with Esc
    call wplus#finder#filter(0, "\<Esc>")
endfunction
