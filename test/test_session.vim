" test/test_session.vim — session files must not clobber the plugin load path.
"
" mksession writes every option into the session file, including 'runtimepath'
" and 'packpath'. Restoring that value replaces the *current* Vim's plugin
" path with whatever the saving Vim had, so plugin autoload functions that are
" still unloaded fail with E117:
"   [wplus-session] session load error: Vim(call):E117: Unknown function:
"   tagbar#RestoreSession
" The restore path therefore strips those two options.

function! s:repo() abort
    return fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
endfunction

function! s:tmpfile(lines) abort
    let l:file = tempname() . '.vim'
    call writefile(a:lines, l:file)
    return l:file
endfunction

function! Test_session_strip_load_paths() abort
    let s:lines = [
        \ 'let SessionLoad = 1',
        \ 'set runtimepath=~/plugins/a,~/.vim',
        \ 'setglobal runtimepath=/tmp/x',
        \ 'se rtp=/tmp/y',
        \ 'set packpath=/tmp/pack',
        \ 'set sessionoptions=blank,buffers,options',
        \ 'set path=/tmp/search',
        \ 'nnoremap <leader>x :echo "x"<CR>',
        \ ]
    let s:kept = wplus#session#_test_strip(s:lines)
    call assert_equal([
        \ 'let SessionLoad = 1',
        \ 'set sessionoptions=blank,buffers,options',
        \ 'set path=/tmp/search',
        \ 'nnoremap <leader>x :echo "x"<CR>',
        \ ], s:kept, 'only the plugin load path options may be stripped')
endfunction

function! Test_session_restore_keeps_plugin_path() abort
    let s:rtp_before = &runtimepath
    let s:packpath_before = &packpath
    let s:marker = 'g:wplus_session_test_marker'
    if exists(s:marker) | unlet g:wplus_session_test_marker | endif

    let s:file = s:tmpfile([
        \ 'set runtimepath=/nonexistent/wplus-test',
        \ 'set packpath=/nonexistent/pack',
        \ 'let g:wplus_session_test_marker = 1',
        \ ])
    let s:err = wplus#session#_test_restore(s:file)
    call delete(s:file)

    call assert_equal('', s:err, 'a session with stale paths must still restore')
    call assert_equal(s:rtp_before, &runtimepath,
        \ 'restoring a session must not replace the plugin path')
    call assert_equal(s:packpath_before, &packpath,
        \ 'restoring a session must not replace packpath')
    call assert_equal(1, get(g:, 'wplus_session_test_marker', 0),
        \ 'the rest of the session file must still run')
    unlet! g:wplus_session_test_marker
endfunction

function! Test_session_restore_reports_errors() abort
    let s:file = s:tmpfile(['call wplus#no_such_module#restore()'])
    let s:err = wplus#session#_test_restore(s:file)
    call delete(s:file)
    call assert_match('E117', s:err, 'an unresolvable call must be reported, not swallowed')

    call assert_equal('', wplus#session#_test_restore('/nonexistent/session.vim'),
        \ 'a missing session file is not an error')
endfunction

function! Test_session_sanitize_file() abort
    let s:file = s:tmpfile([
        \ 'let SessionLoad = 1',
        \ 'set runtimepath=~/plugins/a',
        \ 'set packpath=/tmp/pack',
        \ 'nnoremap <leader>y :echo 1<CR>',
        \ ])
    let s:stripped = wplus#session#_test_sanitize_file(s:file)
    let s:after = readfile(s:file)
    call delete(s:file)

    call assert_equal(2, s:stripped, 'both load-path options should be reported')
    call assert_equal(['let SessionLoad = 1', 'nnoremap <leader>y :echo 1<CR>'], s:after,
        \ 'sanitizing must keep every other line')
endfunction

function! Test_session_save_writes_clean_file() abort
    enew
    execute 'file' fnameescape(tempname() . '.txt')
    setlocal buftype= bufhidden= noswapfile
    call setline(1, ['hello'])

    " Save through the public command so the mksession + sanitize path runs.
    WsessionSave
    let s:files = glob(wplus#session#_test_session_dir() . '/*.vim', 0, 1)
    call assert_true(!empty(s:files), 'save should write a session file')
    let s:written = !empty(s:files) ? readfile(s:files[0]) : []
    call assert_true(!empty(s:written), 'session file must not be empty')
    for s:line in s:written
        call assert_notmatch('^\s*se\%[t]\%[global]\s\+\%(runtimepath\|rtp\|packpath\|pp\)\s*=',
            \ s:line, 'saved session must not pin the plugin load path: ' . s:line)
    endfor

    bwipeout!
endfunction
