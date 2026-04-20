" wplus/todo.vim — TODO/FIXME highlighting and search

if exists('g:autoloaded_wplus_todo') | finish | endif
let g:autoloaded_wplus_todo = 1

function! wplus#todo#setup() abort
    " 1. Define highlights
    highlight default WplusTodo  guibg=#fabd2f guifg=#282828 gui=bold ctermbg=214 ctermfg=235
    highlight default WplusFixme guibg=#fb4934 guifg=#282828 gui=bold ctermbg=167 ctermfg=235
    highlight default WplusNote  guibg=#83a598 guifg=#282828 gui=bold ctermbg=109 ctermfg=235

    " 2. Match patterns (works in any filetype)
    augroup WplusTodoHL
        autocmd!
        autocmd Syntax,BufWinEnter * call s:match_todos()
    augroup END

    " 3. Commands and mappings
    command! WtodoFind call wplus#todo#find()
    nnoremap <silent> <leader>ft :WtodoFind<CR>
endfunction

function! s:clear_matches() abort
    for l:id in get(w:, 'wplus_todo_match_ids', [])
        silent! call matchdelete(l:id)
    endfor
    let w:wplus_todo_match_ids = []
endfunction

function! s:match_todos() abort
    call s:clear_matches()
    let w:wplus_todo_match_ids = [
        \ matchadd('WplusTodo',  '\v\b(TODO|XXX)\b'),
        \ matchadd('WplusFixme', '\v\b(FIXME|BUG|ERROR)\b'),
        \ matchadd('WplusNote',  '\v\b(NOTE|INFO|HACK)\b'),
        \ ]
endfunction

function! wplus#todo#find() abort
    " Integration with ripgrep and finder.vim
    if !executable('rg')
        echohl ErrorMsg | echo "Ripgrep (rg) is required for todo search" | echohl None
        return
    endif

    let l:cmd = 'rg --vimgrep --smart-case "\b(TODO|FIXME|XXX|NOTE|BUG|HACK)\b"'
    let l:items = systemlist(l:cmd)
    
    if empty(l:items)
        echo "No TODOs found!"
        return
    endif

    call wplus#finder#open(l:items, function('s:jump_to_todo'), 'Find TODOs')
endfunction

function! s:jump_to_todo(item) abort
    let l:match = matchlist(a:item, '^\(.*\):\(\d\+\):\(\d\+\):')
    if len(l:match) >= 4
        execute 'edit +' . l:match[2] . ' ' . fnameescape(l:match[1])
    endif
endfunction
