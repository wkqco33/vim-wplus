" wplus/grep.vim — fast grep integration with history and advanced search

if exists('g:autoloaded_wplus_grep') | finish | endif
let g:autoloaded_wplus_grep = 1

let s:search_history = [] " Search history list

function! s:configure_grep() abort
    if executable('rg')
        let &grepprg = 'rg --vimgrep --smart-case'
        let &grepformat = '%f:%l:%c:%m'
    elseif executable('git') && isdirectory('.git')
        let &grepprg = 'git grep -n --column'
        let &grepformat = '%f:%l:%c:%m'
    elseif executable('grep')
        let &grepprg = 'grep -RIn $* .'
        let &grepformat = '%f:%l:%m'
    elseif has('win32')
        " findstr ships with every Windows install, unlike grep/rg.
        let &grepprg = 'findstr /S /N /P $* *'
        let &grepformat = '%f:%l:%m'
    else
        call wplus#util#warn_msg('grep', 'no grep backend found — install ripgrep (rg) for :grep support')
    endif
endfunction

function! s:escape_regex(text) abort
    return substitute(a:text, '[\\.^$*+?(){}|\[\]]', '\\&', 'g')
endfunction

function! s:get_visual_text() abort
    let [l:line_start, l:col_start] = getpos("'<")[1:2]
    let [l:line_end, l:col_end] = getpos("'>")[1:2]
    let l:lines = getline(l:line_start, l:line_end)
    if empty(l:lines)
        return ''
    endif

    let l:lines[-1] = l:lines[-1][: l:col_end - (&selection ==# 'inclusive' ? 1 : 2)]
    let l:lines[0] = l:lines[0][l:col_start - 1 :]
    return trim(substitute(join(l:lines, "\n"), '\_s\+', ' ', 'g'))
endfunction

function! s:add_to_history(query) abort
    " Add to history, avoid duplicates
    if !empty(a:query) && (empty(s:search_history) || s:search_history[-1] !=# a:query)
        call add(s:search_history, a:query)
        " Limit history size
        if len(s:search_history) > 100
            call remove(s:search_history, 0)
        endif
    endif
endfunction

let s:grep_job = v:null

function! wplus#grep#search_async(args) abort
    call s:configure_grep()
    if s:grep_job != v:null
        silent! call job_stop(s:grep_job)
        let s:grep_job = v:null
    endif
    call setqflist([], 'r')
    call s:add_to_history(a:args)
    call wplus#util#info_msg('grep', 'Searching for: ' . a:args . '...')
    
    let l:cmd = []
    if executable('rg')
        let l:cmd = ['rg', '--vimgrep', '--smart-case', '--', a:args]
    elseif executable('git') && !empty(wplus#util#find_git_root(getcwd()))
        let l:cmd = ['git', 'grep', '-n', '--column', a:args]
    elseif executable('grep')
        let l:cmd = ['grep', '-RIn', a:args, '.']
    elseif has('win32')
        let l:cmd = ['findstr', '/S', '/N', '/P', a:args, '*']
    else
        call wplus#util#warn_msg('grep', 'no grep backend found — install ripgrep (rg) for search support')
        return
    endif
    
    let s:grep_job = job_start(l:cmd, {
        \ 'out_cb': {ch, msg -> caddexpr(msg)},
        \ 'close_cb': {ch -> s:on_grep_complete()},
        \ })
endfunction

function! s:on_grep_complete() abort
    let s:grep_job = v:null
    let l:qf = getqflist()
    if empty(l:qf)
        cclose
        call wplus#util#warn_msg('grep', 'No matches found')
    else
        botright copen
        call wplus#util#info_msg('grep', 'Found ' . len(l:qf) . ' match(es)')
    endif
endfunction

function! wplus#grep#search(args) abort
    call wplus#grep#search_async(a:args)
endfunction

function! wplus#grep#search_visual() abort
    let l:text = s:get_visual_text()
    if empty(l:text) | return | endif
    " No shellescape(): the pattern is passed as a job_start() list element, so
    " it reaches the backend as a single argv entry with no shell in between.
    " Escaping here made the quotes part of the search pattern itself.
    call wplus#grep#search(s:escape_regex(l:text))
endfunction

function! wplus#grep#search_regex() abort
    let l:pattern = input('Regex pattern: ', get(s:search_history, -1, ''))
    if empty(l:pattern) | return | endif
    call wplus#grep#search(l:pattern)
endfunction

function! wplus#grep#search_word() abort
    let l:word = expand('<cword>')
    if empty(l:word) | return | endif
    " See search_visual(): argv list form needs no shell quoting.
    call wplus#grep#search(l:word)
endfunction

function! wplus#grep#setup() abort
    call s:configure_grep()

    " Commands
    command! -nargs=+ -complete=file Wgrep      call wplus#grep#search(<q-args>)
    command! -nargs=0                  WgrepRx   call wplus#grep#search_regex()
    command! -nargs=0                  WgrepWord call wplus#grep#search_word()

    " Mappings
    nnoremap <silent> <leader>fg :WgrepWord<CR>
    nnoremap <silent> <leader>fG :WgrepRx<CR>
    xnoremap <silent> <leader>fg :<C-u>call wplus#grep#search_visual()<CR>
endfunction

