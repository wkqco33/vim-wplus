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
        let l:parsed = s:parse_grep_line(l:item)
        if !empty(l:parsed)
            call add(l:qflist, {
                \ 'filename': l:parsed.file,
                \ 'lnum': l:parsed.lnum,
                \ 'col': l:parsed.col,
                \ 'text': trim(l:parsed.text),
                \ 'type': 'I'
                \ })
        endif
    endfor

    call setqflist(l:qflist)
    botright copen
    call wplus#util#info_msg('todo', 'found ' . len(l:qflist) . ' TODO(s)')
endfunction

" Parse one line of grep-like output into {file, lnum, col, text}.
" rg --vimgrep emits 'file:line:col:text'; git grep -n / grep -rn / findstr
" emit 'file:line:text' with no column, so try the column-aware pattern
" first and fall back when it doesn't match. Filename uses a greedy match so
" a Windows drive letter ('C:\...') isn't mistaken for the field separator.
function! s:parse_grep_line(line) abort
    let l:m = matchlist(a:line, '^\(.*\):\(\d\+\):\(\d\+\):\(.*\)$')
    if !empty(l:m)
        return {'file': l:m[1], 'lnum': str2nr(l:m[2]), 'col': str2nr(l:m[3]), 'text': l:m[4]}
    endif
    let l:m = matchlist(a:line, '^\(.*\):\(\d\+\):\(.*\)$')
    if !empty(l:m)
        return {'file': l:m[1], 'lnum': str2nr(l:m[2]), 'col': 1, 'text': l:m[3]}
    endif
    return {}
endfunction

function! s:get_todos() abort
    " Try ripgrep first, fallback to git grep, then plain grep/findstr
    if executable('rg')
        let l:cmd = 'rg --vimgrep --smart-case "\b(TODO|FIXME|XXX|NOTE|BUG|HACK|WARN)\b"'
        let l:items = systemlist(l:cmd)
    elseif executable('git') && !empty(wplus#util#find_git_root(getcwd()))
        " -E is required: git grep defaults to basic regex, so the alternation
        " below was read literally and this backend always returned 0 matches.
        " Argv list form also avoids a shell round-trip.
        let l:items = systemlist(['git', 'grep', '-n', '-E',
            \ '\b(TODO|FIXME|XXX|NOTE|BUG|HACK|WARN)\b'])
    elseif executable('grep')
        let l:items = systemlist('grep -rn "TODO\|FIXME\|XXX\|NOTE\|BUG\|HACK\|WARN" .')
    elseif has('win32')
        " findstr has no regex alternation; space-separated words are OR'd.
        let l:items = systemlist('findstr /S /N /I "TODO FIXME XXX NOTE BUG HACK WARN" *')
    else
        call wplus#util#warn_msg('todo', 'no grep backend found — install ripgrep (rg) for TODO search')
        let l:items = []
    endif
    return filter(l:items, '!empty(v:val)')
endfunction

function! s:jump_to_todo(item) abort
    let l:parsed = s:parse_grep_line(a:item)
    if !empty(l:parsed)
        execute 'edit +' . l:parsed.lnum . ' ' . fnameescape(l:parsed.file)
    endif
endfunction

