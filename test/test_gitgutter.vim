" test/test_gitgutter.vim — Test gitgutter unified-diff parsers

function! Test_gitgutter_parse_diff_empty() abort
    call assert_equal([], wplus#gitgutter#_test_parse_diff([]), 'Empty diff should produce no hunks')
endfunction

function! Test_gitgutter_parse_diff_additions() abort
    let l:diff = [
        \ 'diff --git a/a.go b/a.go',
        \ 'index 0000000..1111111',
        \ '--- a/a.go',
        \ '+++ b/a.go',
        \ '@@ -1,0 +1,3 @@',
        \ '+line1',
        \ '+line2',
        \ '+line3',
        \ ]
    let l:result = wplus#gitgutter#_test_parse_diff(l:diff)
    call assert_equal([
        \ {'lnum': 1, 'type': 'WplusGGAdd'},
        \ {'lnum': 2, 'type': 'WplusGGAdd'},
        \ {'lnum': 3, 'type': 'WplusGGAdd'},
        \ ], l:result, 'Three added lines should yield three Add signs')
endfunction

function! Test_gitgutter_parse_diff_change() abort
    let l:diff = [
        \ 'diff --git a/a.go b/a.go',
        \ '--- a/a.go',
        \ '+++ b/a.go',
        \ '@@ -1,3 +1,3 @@',
        \ '-old',
        \ '+new',
        \ ]
    let l:result = wplus#gitgutter#_test_parse_diff(l:diff)
    call assert_equal([{'lnum': 1, 'type': 'WplusGGChange'}], l:result, 'Delete+Add at the same line should merge into a Change')
endfunction

function! Test_gitgutter_parse_diff_deletion() abort
    let l:diff = [
        \ 'diff --git a/a.go b/a.go',
        \ '--- a/a.go',
        \ '+++ b/a.go',
        \ '@@ -1,3 +1,2 @@',
        \ '-gone',
        \ ' keep',
        \ ]
    let l:result = wplus#gitgutter#_test_parse_diff(l:diff)
    call assert_equal([{'lnum': 1, 'type': 'WplusGGDelete'}], l:result, 'A deleted line should yield a Delete sign')
endfunction

function! Test_gitgutter_parse_hunks() abort
    let l:diff = [
        \ 'diff --git a/a.go b/a.go',
        \ '--- a/a.go',
        \ '+++ b/a.go',
        \ '@@ -1,3 +1,3 @@',
        \ '-old',
        \ '+new',
        \ '@@ -10,2 +11,2 @@',
        \ ' context',
        \ ]
    let l:hunks = wplus#gitgutter#_test_parse_hunks(l:diff)
    call assert_equal(2, len(l:hunks), 'Two hunks expected')
    call assert_equal(1, l:hunks[0].new_start, 'First hunk new_start should be 1')
    call assert_equal(3, l:hunks[0].new_count, 'First hunk new_count should be 3')
    call assert_equal(11, l:hunks[1].new_start, 'Second hunk new_start should be 11')
    call assert_equal(2, l:hunks[1].new_count, 'Second hunk new_count should be 2')
endfunction
