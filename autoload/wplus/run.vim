" wplus/run.vim — Filetype-aware code runner / build system
" <leader>rr runs the current file; <leader>rb runs the build command.
" Configure per-filetype with g:wplus_run_commands / g:wplus_build_commands.

if exists('g:autoloaded_wplus_run') | finish | endif
let g:autoloaded_wplus_run = 1

" Default run commands per filetype.  %s is replaced with the file path.
" Override or extend in your vimrc with g:wplus_run_commands.
let s:default_run = {
    \ 'python':     'python3 %s',
    \ 'javascript': 'node %s',
    \ 'typescript': 'ts-node %s',
    \ 'lua':        'lua %s',
    \ 'ruby':       'ruby %s',
    \ 'sh':         'bash %s',
    \ 'bash':       'bash %s',
    \ 'zsh':        'zsh %s',
    \ 'perl':       'perl %s',
    \ 'php':        'php %s',
    \ 'r':          'Rscript %s',
    \ 'go':         'go run %s',
    \ 'rust':       'rustc %s && ./%r',
    \ 'c':          'cc %s -o /tmp/wplus_run_out && /tmp/wplus_run_out',
    \ 'cpp':        'c++ %s -o /tmp/wplus_run_out && /tmp/wplus_run_out',
    \ }

" Default build commands per marker file (project-root based).
let s:default_build = {
    \ 'Makefile':      'make',
    \ 'package.json':  'npm run build',
    \ 'Cargo.toml':    'cargo build',
    \ 'go.mod':        'go build ./...',
    \ 'build.gradle':  './gradlew build',
    \ 'pom.xml':       'mvn package -q',
    \ 'CMakeLists.txt': 'cmake --build build',
    \ }

let g:wplus_run_commands   = get(g:, 'wplus_run_commands', {})
let g:wplus_build_commands = get(g:, 'wplus_build_commands', {})
let g:wplus_run_use_terminal = get(g:, 'wplus_run_use_terminal', 1)

" ── helpers ───────────────────────────────────────────────────────────────

function! s:expand_cmd(tpl, file) abort
    let l:stem = fnamemodify(a:file, ':t:r')   " filename without extension
    let l:cmd = substitute(a:tpl, '%s', shellescape(a:file), 'g')
    let l:cmd = substitute(l:cmd, '%r', shellescape(l:stem), 'g')
    return l:cmd
endfunction

function! s:run_in_terminal(cmd) abort
    if !exists('*wplus#terminal#toggle')
        call wplus#util#error_msg('run', 'terminal module not loaded')
        return
    endif
    " Open terminal, send the command
    let l:term_buf = s:ensure_terminal()
    if l:term_buf == -1 | return | endif
    call s:send_to_term(l:term_buf, a:cmd)
endfunction

function! s:ensure_terminal() abort
    " Reuse existing terminal buffer or create a new one
    for l:b in range(1, bufnr('$'))
        if getbufvar(l:b, '&buftype') ==# 'terminal' && bufloaded(l:b)
            let l:win = bufwinid(l:b)
            if l:win == -1
                execute 'botright 12split'
                execute 'buffer ' . l:b
            else
                call win_gotoid(l:win)
            endif
            return l:b
        endif
    endfor
    " Create new terminal
    execute 'botright 12split'
    if has('nvim')
        terminal
    else
        terminal ++curwin ++close
    endif
    return bufnr('%')
endfunction

function! s:send_to_term(bufnr, cmd) abort
    let l:win = bufwinid(a:bufnr)
    if l:win == -1 | return | endif
    call win_gotoid(l:win)
    if has('nvim')
        call chansend(getbufvar(a:bufnr, 'terminal_job_id', -1), a:cmd . "\n")
    else
        call term_sendkeys(a:bufnr, a:cmd . "\r")
    endif
    startinsert
endfunction

function! s:run_in_quickfix(cmd) abort
    " Use :make-style async execution via job
    let l:lines = []
    call setqflist([], 'r', {'title': '[wplus-run] ' . a:cmd})
    copen
    let l:job = job_start(['sh', '-c', a:cmd], {
        \ 'out_cb':   {_, l -> s:qf_add(l)},
        \ 'err_cb':   {_, l -> s:qf_add(l)},
        \ 'close_cb': {_ -> s:qf_done(a:cmd)},
        \ })
endfunction

function! s:qf_add(line) abort
    " 'a' appends. This used to getqflist() -> add() -> setqflist(..., 'r'),
    " rebuilding the entire list for every single line of output: O(n^2) over a
    " chatty build.
    call setqflist([{'text': a:line, 'valid': 0}], 'a')
    " Scroll to bottom
    let l:qfwin = getqflist({'winid': 1}).winid
    if l:qfwin > 0
        call win_execute(l:qfwin, 'normal! G')
    endif
endfunction

function! s:qf_done(cmd) abort
    call wplus#util#info_msg('run', 'finished: ' . a:cmd)
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#run#run() abort
    " Write first if modified
    if &modified | silent write | endif

    let l:ft = &filetype
    let l:file = expand('%:p')
    if empty(l:file)
        call wplus#util#warn_msg('run', 'no file to run')
        return
    endif

    " User override > defaults
    let l:cmds = extend(copy(s:default_run), g:wplus_run_commands)
    if !has_key(l:cmds, l:ft)
        call wplus#util#warn_msg('run', 'no run command for filetype: ' . l:ft
                    \ . '. Set g:wplus_run_commands["' . l:ft . '"] = "your_cmd %s"')
        return
    endif

    let l:cmd = s:expand_cmd(l:cmds[l:ft], l:file)
    call wplus#util#info_msg('run', l:cmd)

    if g:wplus_run_use_terminal
        call s:run_in_terminal(l:cmd)
    else
        call s:run_in_quickfix(l:cmd)
    endif
endfunction

function! wplus#run#build() abort
    if &modified | silent write | endif

    let l:root = wplus#root#find_root()
    if empty(l:root) | let l:root = getcwd() | endif

    let l:build_cmds = extend(copy(s:default_build), g:wplus_build_commands)
    for [l:marker, l:cmd] in items(l:build_cmds)
        if filereadable(l:root . '/' . l:marker) || isdirectory(l:root . '/' . l:marker)
            let l:full_cmd = 'cd ' . shellescape(l:root) . ' && ' . l:cmd
            call wplus#util#info_msg('run', 'build: ' . l:cmd)
            if g:wplus_run_use_terminal
                call s:run_in_terminal(l:full_cmd)
            else
                call s:run_in_quickfix(l:full_cmd)
            endif
            return
        endif
    endfor

    call wplus#util#warn_msg('run', 'no build system detected in ' . l:root)
endfunction

function! wplus#run#test() abort
    if &modified | silent write | endif

    let l:root = wplus#root#find_root()
    if empty(l:root) | let l:root = getcwd() | endif

    let l:test_map = {
        \ 'package.json':  'npm test',
        \ 'Cargo.toml':    'cargo test',
        \ 'go.mod':        'go test ./...',
        \ 'Makefile':      'make test',
        \ 'pytest.ini':    'pytest',
        \ 'setup.py':      'python -m pytest',
        \ 'pyproject.toml': 'python -m pytest',
        \ }
    for [l:marker, l:cmd] in items(l:test_map)
        if filereadable(l:root . '/' . l:marker) || isdirectory(l:root . '/' . l:marker)
            let l:full_cmd = 'cd ' . shellescape(l:root) . ' && ' . l:cmd
            call wplus#util#info_msg('run', 'test: ' . l:cmd)
            if g:wplus_run_use_terminal
                call s:run_in_terminal(l:full_cmd)
            else
                call s:run_in_quickfix(l:full_cmd)
            endif
            return
        endif
    endfor

    call wplus#util#warn_msg('run', 'no test system detected in ' . l:root)
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#run#setup() abort
    command! Wrun   call wplus#run#run()
    command! Wbuild call wplus#run#build()
    command! Wtest  call wplus#run#test()

    nnoremap <silent> <leader>rr :Wrun<CR>
    nnoremap <silent> <leader>rb :Wbuild<CR>
    nnoremap <silent> <leader>rt :Wtest<CR>
endfunction
