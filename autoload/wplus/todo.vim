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
    command! WtodoFind       call wplus#todo#find()
    command! WtodoQuickfix   call wplus#todo#quickfix()
    nnoremap <silent> <leader>ft :WtodoFind<CR>
    nnoremap <silent> <leader>tq :WtodoQuickfix<CR>
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
    " Integration with finder.vim
    let l:items = s:get_todos()
    if empty(l:items)
        call wplus#util#warn_msg('todo', 'no TODOs found')
        return
    endif

    call wplus#finder#open(l:items, function('s:jump_to_todo'), 'Find TODOs')
endfunction

function! wplus#todo#quickfix() abort
    " Fill quickfix list with TODOs
    let l:items = s:get_todos()
    if empty(l:items)
        call wplus#util#warn_msg('todo', 'no TODOs found')
        return
    endif
    
    let l:qflist = []
    for l:item in l:items
        let l:match = matchlist(l:item, '^\(.*\):\(\d\+\):\(\d\+\):\(.*\)')
        if len(l:match) >= 5
            call add(l:qflist, {
                \ 'filename': l:match[1],
                \ 'lnum': str2nr(l:match[2]),
                \ 'col': str2nr(l:match[3]),
                \ 'text': trim(l:match[4]),
                \ 'type': 'I'
                \ })
        endif
    endfor
    
    call setqflist(l:qflist)
    botright copen
    call wplus#util#info_msg('todo', 'found ' . len(l:qflist) . ' TODO(s)')
endfunction

function! s:get_todos() abort
    " Try ripgrep first, fallback to git grep, then plain grep
    if executable('rg')
        let l:cmd = 'rg --vimgrep --smart-case "\b(TODO|FIXME|XXX|NOTE|BUG|HACK|WARN)\b"'
        let l:items = systemlist(l:cmd)
    elseif executable('git') && isdirectory('.git')
        let l:cmd = 'git grep -n "\b(TODO|FIXME|XXX|NOTE|BUG|HACK|WARN)\b"'
        let l:items = systemlist(l:cmd)
    else
        let l:items = systemlist('grep -rn "TODO\|FIXME\|XXX\|NOTE\|BUG\|HACK\|WARN" .')
    endif
    return filter(l:items, '!empty(v:val)')
endfunction

function! s:jump_to_todo(item) abort
    let l:match = matchlist(a:item, '^\(.*\):\(\d\+\):\(\d\+\):')
    if len(l:match) >= 4
        execute 'edit +' . l:match[2] . ' ' . fnameescape(l:match[1])
    endif
endfunction

