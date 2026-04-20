" wplus/grep.vim — fast grep integration

if exists('g:autoloaded_wplus_grep') | finish | endif
let g:autoloaded_wplus_grep = 1

function! wplus#grep#search(args) abort
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
    let [line_start, col_start] = getpos("'<")[1:2]
    let [line_end, col_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if empty(lines) | return | endif
    let lines[-1] = lines[-1][:col_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][col_start - 1:]
    let pattern = join(lines, "\n")
    call wplus#grep#search(shellescape(pattern))
endfunction

function! wplus#grep#setup() abort
    " Configure grepprg
    if executable('rg')
        let &grepprg = 'rg --vimgrep --smart-case'
        let &grepformat = '%f:%l:%c:%m'
    elseif executable('git') && isdirectory('.git')
        let &grepprg = 'git grep -n --column'
        let &grepformat = '%f:%l:%c:%m'
    endif

    " Commands
    command! -nargs=+ -complete=file Wgrep call wplus#grep#search(<q-args>)

    " Mappings
    nnoremap <silent> <leader>fg :Wgrep <C-r><C-w><CR>
    xnoremap <silent> <leader>fg :<C-u>call wplus#grep#search_visual()<CR>
endfunction
