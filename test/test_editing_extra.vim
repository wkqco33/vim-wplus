" test/test_editing_extra.vim — Tests for commentary, textobj, altfile, blame, tabline, statusline, format

function! Test_commentary_edge_cases_and_count() abort
    call wplus#commentary#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile

    " 1. commentstring with %s at index 0 (no prefix before %s -> must not duplicate via [:-1])
    let &l:commentstring = '%s -- comment'
    call setline(1, ['hello', 'world', 'third'])
    call cursor(1, 1)
    call feedkeys('2gcc', 'x')
    call assert_equal(['hello -- comment', 'world -- comment', 'third'], getline(1, '$'),
        \ '2gcc with %s at index 0 should append right delimiter on 2 lines without duplicating %s')

    " 2. empty commentstring falls back to '# %s'
    silent %delete _
    let &l:commentstring = ''
    call setline(1, ['alpha'])
    call cursor(1, 1)
    call feedkeys('gcc', 'x')
    call assert_equal(['# alpha'], getline(1, '$'), 'empty commentstring should fall back to # comment')

    " 3. nomodifiable buffer must not throw E21
    setlocal nomodifiable
    call wplus#commentary#toggle_range(1, 1)
    setlocal modifiable

    bwipeout!
endfunction

function! Test_textobj_argument_edge_cases() abort
    call wplus#textobj#setup()
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile

    " 1. Empty argument list foo() must not delete parentheses on dia
    call setline(1, 'foo()')
    call cursor(1, 4)
    call feedkeys('dia', 'x')
    call assert_equal('foo()', getline(1), 'dia inside empty foo() must not delete parens')

    " 2. Last argument without space after comma: foo(a,b) -> daa on b should leave foo(a)
    call setline(1, 'foo(a,b)')
    call cursor(1, 7)
    call feedkeys('daa', 'x')
    call assert_equal('foo(a)', getline(1), 'daa on last arg in foo(a,b) must remove preceding comma')

    " 3. Last argument with multiple spaces after comma: foo(a,  b) -> daa on b should leave foo(a)
    call setline(1, 'foo(a,  b)')
    call cursor(1, 9)
    call feedkeys('daa', 'x')
    call assert_equal('foo(a)', getline(1), 'daa on last arg in foo(a,  b) must remove preceding comma and spaces')

    bwipeout!
endfunction

function! Test_altfile_multi_language_candidates() abort
    call wplus#altfile#setup()
    let l:dir = tempname()
    call mkdir(l:dir, 'p')

    " Go: foo.go <-> foo_test.go
    let l:go_src = l:dir . '/foo.go'
    let l:go_tst = l:dir . '/foo_test.go'
    call writefile(['package p'], l:go_src)
    call writefile(['package p'], l:go_tst)

    execute 'edit ' . fnameescape(l:go_src)
    call wplus#altfile#switch('')
    call assert_equal(fnamemodify(l:go_tst, ':p'), expand('%:p'), 'foo.go should switch to foo_test.go')
    call wplus#altfile#switch('')
    call assert_equal(fnamemodify(l:go_src, ':p'), expand('%:p'), 'foo_test.go should switch back to foo.go')

    bwipeout!
    call delete(l:dir, 'rf')
endfunction

function! Test_blame_format_template_with_hash_and_ampersand() abort
    call wplus#blame#setup()
    let g:wplus_blame_template = '<hash> <author> (<date>) - <summary>'
    let l:lines = [
        \ 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2 1 1 1',
        \ 'author Alice & Bob',
        \ 'author-time 1700000000',
        \ 'summary Fix R&D \0 issue',
        \ ]
    let l:formatted = wplus#blame#_test_format_blame(l:lines)
    call assert_true(l:formatted =~# '^\s*a1b2c3d ', 'Formatted blame must replace <hash> with 7-char sha')
    call assert_true(l:formatted =~# 'Alice & Bob', 'Formatted blame must not mangle & in author')
    call assert_true(l:formatted =~# 'Fix R&D \\0 issue', 'Formatted blame must not mangle & or \0 in summary')
    let g:wplus_blame_template = '  <author>, <date> • <summary>'
endfunction

function! Test_tabline_and_statusline_escape_percent() abort
    call wplus#tabline#setup()
    call wplus#statusline#setup()
    enew!
    silent execute 'file ' . fnameescape('100%_coverage.py')
    let l:tl = wplus#tabline#render()
    call assert_true(l:tl =~# '100%%_coverage\.py', 'Tabline must escape % in filenames as %%')
    bwipeout!
endfunction

function! Test_format_command_registered() abort
    call wplus#format#setup()
    call assert_equal(2, exists(':Wformat'), ':Wformat command should be registered')
endfunction
