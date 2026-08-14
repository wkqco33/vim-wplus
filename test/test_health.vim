" test/test_health.vim — Test :WplusHealth and health module

function! Test_health_command_and_output() abort
    call wplus#health#setup()
    
    " Execute health check command
    WplusHealth
    
    let l:buf = bufnr('__WplusHealth__')
    call assert_true(l:buf != -1, '__WplusHealth__ buffer should be created')

    let l:lines = getbufline(l:buf, 1, '$')
    call assert_true(len(l:lines) > 20, 'Health check output should contain full report')
    
    " Assert presence of all 7 sections
    let l:text = join(l:lines, "\n")
    call assert_true(l:text =~# '1\. Vim Environment', 'Section 1 missing')
    call assert_true(l:text =~# '2\. Modules & Startup Hygiene', 'Section 2 missing')
    call assert_true(l:text =~# '3\. External Tools', 'Section 3 missing')
    call assert_true(l:text =~# '4\. LSP Server Status', 'Section 4 missing')
    call assert_true(l:text =~# '5\. AI Provider Configuration', 'Section 5 missing')
    call assert_true(l:text =~# '6\. Keymap Conflicts', 'Section 6 missing')
    call assert_true(l:text =~# '7\. Unrecognized Global Options', 'Section 7 missing')

    " Assert API key is never printed
    let g:wplus_ai_api_key = 'secret-api-key-12345'
    WplusHealth
    let l:lines2 = getbufline(l:buf, 1, '$')
    let l:text2 = join(l:lines2, "\n")
    call assert_false(l:text2 =~# 'secret-api-key-12345', 'API key must never be printed in health report')

    " Assert newly introduced unknown options are caught without depending on
    " unrelated options from other modules.
    let l:before_unknown = wplus#health#unknown_options()
    let g:wplus_unknown_test_option = 1
    let l:unknown = wplus#health#unknown_options()
    call assert_equal(['wplus_unknown_test_option'], filter(l:unknown, 'index(l:before_unknown, v:val) < 0'), 'Unknown option should be detected')
    unlet g:wplus_unknown_test_option

    " Leave the test runner with a valid window; :close cannot close the last
    " window in Vim's ex mode.
    enew
endfunction
