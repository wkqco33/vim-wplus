" test/test_fold.vim — Test fold module and LSP folds integration

function! Test_fold_expr_handles_lsp_ranges() abort
    call wplus#fold#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python

    " Standard LSP foldingRange dictionary format (startLine, endLine)
    let b:wplus_fold_ranges = [
        \ {'startLine': 2, 'endLine': 6, 'kind': 'region'},
        \ ]

    call assert_equal('>1', wplus#fold#expr(3), 'startLine: 2 should mark line 3 as fold start >1')
    call assert_equal('=',  wplus#fold#expr(4), 'line 4 inside fold should be =')
    call assert_equal('<1', wplus#fold#expr(7), 'endLine: 6 should mark line 7 as fold end <1')
    call assert_equal('=',  wplus#fold#expr(8), 'line 8 outside fold should be =')

    " Legacy / alternative start/end format
    let b:wplus_fold_ranges = [
        \ {'start': 10, 'end': 14},
        \ ]
    call assert_equal('>1', wplus#fold#expr(11), 'start: 10 should mark line 11 as fold start >1')
    call assert_equal('<1', wplus#fold#expr(15), 'end: 14 should mark line 15 as fold end <1')

    bwipeout!
endfunction

function! Test_fold_listens_to_lsp_folds_update_event() abort
    call wplus#fold#setup()
    let g:wplus_fold_method = 'lsp'
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python

    let l:ranges = [{'startLine': 0, 'endLine': 5}]
    let b:wplus_lsp_fold_ranges = l:ranges
    doautocmd User WplusLspFoldsUpdate

    call assert_equal('expr', &l:foldmethod, 'Buffer foldmethod should switch to expr on LSP fold update')
    call assert_equal(l:ranges, get(b:, 'wplus_fold_ranges', []), 'Buffer should have updated fold ranges')

    let g:wplus_fold_method = 'indent'
    bwipeout!
endfunction

function! Test_fold_nested_levels() abort
    call wplus#fold#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=python

    let b:wplus_fold_ranges = [
        \ {'startLine': 0, 'endLine': 10},
        \ {'startLine': 2, 'endLine': 6},
        \ ]

    call assert_equal('>1', wplus#fold#expr(1), 'Outer fold should start at level >1')
    call assert_equal('=',  wplus#fold#expr(2), 'Between start lines should be =')
    call assert_equal('>2', wplus#fold#expr(3), 'Inner fold should start at level >2')
    call assert_equal('<2', wplus#fold#expr(7), 'Inner fold should end at level <2')
    call assert_equal('<1', wplus#fold#expr(11), 'Outer fold should end at level <1')

    bwipeout!
endfunction
