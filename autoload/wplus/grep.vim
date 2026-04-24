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
    else
        let &grepprg = 'grep -RIn $* .'
        let &grepformat = '%f:%l:%m'
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

function! wplus#grep#search(args) abort
    call s:configure_grep()
    let grep_cmd = &grepprg
    if empty(grep_cmd) | let grep_cmd = 'grep -n $* /dev/null' | endif

    " Add to history
    call s:add_to_history(a:args)

    " Run grep and open quickfix
    execute 'silent grep! ' . a:args
    botright copen
    " If no matches, close quickfix
    if empty(getqflist())
        cclose
        call wplus#util#warn_msg('grep', 'no matches found for: ' . a:args)
    else
        call wplus#util#info_msg('grep', 'found ' . len(getqflist()) . ' match(es)')
        redraw!
    endif
endfunction

function! wplus#grep#search_visual() abort
    let l:text = s:get_visual_text()
    if empty(l:text) | return | endif
    call wplus#grep#search(shellescape(s:escape_regex(l:text)))
endfunction

function! wplus#grep#search_regex() abort
    let l:pattern = input('Regex pattern: ', get(s:search_history, -1, ''))
    if empty(l:pattern) | return | endif
    call wplus#grep#search(l:pattern)
endfunction

function! wplus#grep#search_word() abort
    let l:word = expand('<cword>')
    if empty(l:word) | return | endif
    call wplus#grep#search(shellescape(l:word))
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

