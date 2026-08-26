" test/test_format.vim — Unit tests for smart formatter

function! Test_format_fallback_to_indent() abort
    call wplus#format#setup()
    enew!
    setlocal buftype= noswapfile
    setlocal modifiable
    setlocal filetype=unknownft
    setlocal autoindent
    
    call setline(1, ['if true', '  x = 1', 'end'])
    call wplus#format#run()
    
    " modifiable buffer with unknown ft should successfully run vim indent without crashing
    call assert_equal(3, line('$'))
    bwipeout!
endfunction
