" wplus/grep.vim — fast grep integration

if exists('g:autoloaded_wplus_grep') | finish | endif
let g:autoloaded_wplus_grep = 1

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

function! wplus#grep#search(args) abort
    call s:configure_grep()
    let grep_cmd = &grepprg
    if empty(grep_cmd) | let grep_cmd = 'grep -n $* /dev/null' | endif

    " Run grep and open quickfix
    execute 'silent grep! ' . a:args
    botright copen
    " If no matches, close quickfix
    if empty(getqflist())
        cclose
        echohl WarningMsg | echo "No matches found for: " . a:args | echohl None
    else
        redraw!
    endif
endfunction

function! wplus#grep#search_visual() abort
    let l:text = s:get_visual_text()
    if empty(l:text) | return | endif
    call wplus#grep#search(shellescape(s:escape_regex(l:text)))
endfunction

function! wplus#grep#setup() abort
    call s:configure_grep()

    " Commands
    command! -nargs=+ -complete=file Wgrep call wplus#grep#search(<q-args>)

    " Mappings
    nnoremap <silent> <leader>fg :Wgrep <C-r><C-w><CR>
    xnoremap <silent> <leader>fg :<C-u>call wplus#grep#search_visual()<CR>
endfunction
