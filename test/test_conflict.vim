" test/test_conflict.vim — Test Git merge conflict parsing and resolving (including diff3)

function! Test_conflict_resolve_standard() abort
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile
    call setline(1, [
        \ 'before',
        \ '<<<<<<< HEAD',
        \ 'our change',
        \ '=======',
        \ 'their change',
        \ '>>>>>>> feature',
        \ 'after',
        \ ])

    call wplus#conflict#resolve_ours()
    call assert_equal(['before', 'our change', 'after'], getline(1, '$'), 'Standard conflict should resolve to ours')

    bwipeout!
endfunction

function! Test_conflict_resolve_diff3_ours() abort
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile
    call setline(1, [
        \ 'before',
        \ '<<<<<<< HEAD',
        \ 'our change',
        \ '||||||| base',
        \ 'original base code',
        \ '=======',
        \ 'their change',
        \ '>>>>>>> feature',
        \ 'after',
        \ ])

    " Move cursor inside conflict and resolve ours
    call cursor(3, 1)
    call wplus#conflict#resolve_ours()
    call assert_equal(['before', 'our change', 'after'], getline(1, '$'), 'diff3 conflict should resolve to ours without base residue')

    bwipeout!
endfunction

function! Test_conflict_resolve_diff3_theirs() abort
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile
    call setline(1, [
        \ 'before',
        \ '<<<<<<< HEAD',
        \ 'our change',
        \ '||||||| base',
        \ 'original base code',
        \ '=======',
        \ 'their change',
        \ '>>>>>>> feature',
        \ 'after',
        \ ])

    call cursor(3, 1)
    call wplus#conflict#resolve_theirs()
    call assert_equal(['before', 'their change', 'after'], getline(1, '$'), 'diff3 conflict should resolve to theirs cleanly')

    bwipeout!
endfunction

function! Test_conflict_targets_cursor_block() abort
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile
    call setline(1, [
        \ '<<<<<<< HEAD',
        \ 'block1 ours',
        \ '=======',
        \ 'block1 theirs',
        \ '>>>>>>> branch1',
        \ 'middle',
        \ '<<<<<<< HEAD',
        \ 'block2 ours',
        \ '=======',
        \ 'block2 theirs',
        \ '>>>>>>> branch2',
        \ ])

    " Move cursor to the second conflict block (line 8)
    call cursor(8, 1)
    call wplus#conflict#resolve_theirs()

    " Block 2 should be resolved to theirs, but Block 1 should still be unresolved
    call assert_equal('<<<<<<< HEAD', getline(1))
    call assert_equal('block2 theirs', getline(7))

    bwipeout!
endfunction
