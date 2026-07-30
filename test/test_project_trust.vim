" test/test_project_trust.vim — Test project.vim security trust prompt

function! Test_project_trust_prompt_skips_by_default() abort
    let l:tmpdir = tempname()
    call mkdir(l:tmpdir, 'p')
    let l:cfg = l:tmpdir . '/.wplus.vim'
    let l:dummy_file = l:tmpdir . '/test.txt'
    call writefile(['let g:wplus_test_pwned = 1'], l:cfg)
    call writefile(['hello'], l:dummy_file)

    let g:wplus_project_trust_file = l:tmpdir . '/trust.json'
    let g:wplus_test_trust_choice = 's'  " Skip

    if exists('g:wplus_test_pwned') | unlet g:wplus_test_pwned | endif

    call wplus#project#setup()
    execute 'edit' fnameescape(l:dummy_file)

    call assert_false(exists('g:wplus_test_pwned'), '.wplus.vim should not execute when skipped')

    " Cleanup
    call delete(l:cfg)
    call delete(l:dummy_file)
    call delete(l:tmpdir, 'rf')
endfunction

function! Test_project_trust_once() abort
    let l:tmpdir = tempname()
    call mkdir(l:tmpdir, 'p')
    let l:cfg = l:tmpdir . '/.wplus.vim'
    let l:dummy_file = l:tmpdir . '/test.txt'
    call writefile(['let g:wplus_test_pwned_once = 1'], l:cfg)
    call writefile(['hello'], l:dummy_file)

    let g:wplus_project_trust_file = l:tmpdir . '/trust.json'
    let g:wplus_test_trust_choice = 't'  " Trust once

    if exists('g:wplus_test_pwned_once') | unlet g:wplus_test_pwned_once | endif

    call wplus#project#setup()
    execute 'edit' fnameescape(l:dummy_file)

    call assert_true(get(g:, 'wplus_test_pwned_once', 0) == 1, '.wplus.vim should execute when trusted once')
    call assert_false(filereadable(g:wplus_project_trust_file), 'Trust once should not persist hash to file')

    " Cleanup
    call delete(l:cfg)
    call delete(l:dummy_file)
    call delete(l:tmpdir, 'rf')
endfunction

function! Test_project_trust_always() abort
    let l:tmpdir = tempname()
    call mkdir(l:tmpdir, 'p')
    let l:cfg = l:tmpdir . '/.wplus.vim'
    let l:dummy_file = l:tmpdir . '/test.txt'
    call writefile(['let g:wplus_test_pwned_always = 1'], l:cfg)
    call writefile(['hello'], l:dummy_file)

    let g:wplus_project_trust_file = l:tmpdir . '/trust.json'
    let g:wplus_test_trust_choice = 'T'  " Trust always

    if exists('g:wplus_test_pwned_always') | unlet g:wplus_test_pwned_always | endif

    call wplus#project#setup()
    execute 'edit' fnameescape(l:dummy_file)

    call assert_true(get(g:, 'wplus_test_pwned_always', 0) == 1, '.wplus.vim should execute when trusted always')
    call assert_true(filereadable(g:wplus_project_trust_file), 'Trust always should create trust store file')

    " Cleanup
    call delete(l:cfg)
    call delete(l:dummy_file)
    call delete(g:wplus_project_trust_file)
    call delete(l:tmpdir, 'rf')
endfunction
