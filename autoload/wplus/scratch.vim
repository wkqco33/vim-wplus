" wplus/scratch.vim — Persistent scratch buffer
" Toggles a scratch window backed by ~/.vim/scratch.txt (or per-project).
" Content is auto-saved on hide and auto-loaded on show.

if exists('g:autoloaded_wplus_scratch') | finish | endif
let g:autoloaded_wplus_scratch = 1

let g:wplus_scratch_file    = get(g:, 'wplus_scratch_file', expand('~/.vim/scratch.txt'))
let g:wplus_scratch_height  = get(g:, 'wplus_scratch_height', 15)
let g:wplus_scratch_position = get(g:, 'wplus_scratch_position', 'botright')
let g:wplus_scratch_ft      = get(g:, 'wplus_scratch_ft', 'markdown')

let s:scratch_bufnr = -1

" ── helpers ───────────────────────────────────────────────────────────────

function! s:is_open() abort
    return s:scratch_bufnr != -1
                \ && bufexists(s:scratch_bufnr)
                \ && bufwinid(s:scratch_bufnr) != -1
endfunction

function! s:save() abort
    if s:scratch_bufnr == -1 || !bufloaded(s:scratch_bufnr) | return | endif
    let l:lines = getbufline(s:scratch_bufnr, 1, '$')
    let l:dir = fnamemodify(g:wplus_scratch_file, ':h')
    if !isdirectory(l:dir) | call mkdir(l:dir, 'p') | endif
    call writefile(l:lines, g:wplus_scratch_file)
endfunction

function! s:load_into_buf() abort
    if filereadable(g:wplus_scratch_file)
        let l:lines = readfile(g:wplus_scratch_file)
        call deletebufline(s:scratch_bufnr, 1, '$')
        call setbufline(s:scratch_bufnr, 1, l:lines)
    endif
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#scratch#toggle() abort
    if s:is_open()
        call s:save()
        let l:winid = bufwinid(s:scratch_bufnr)
        if winnr('$') > 1
            call win_execute(l:winid, 'close')
        endif
        return
    endif

    " Create or reuse scratch buffer
    if s:scratch_bufnr == -1 || !bufexists(s:scratch_bufnr)
        execute g:wplus_scratch_position . ' ' . g:wplus_scratch_height . 'split'
        enew
        let s:scratch_bufnr = bufnr('%')
        setlocal buftype=nofile
        setlocal bufhidden=hide
        setlocal noswapfile
        setlocal nobuflisted
        execute 'setlocal filetype=' . g:wplus_scratch_ft
        setlocal statusline=\ 📝\ Scratch\ (%{&modified?'*':''}%{expand(g:wplus_scratch_file)})
        call s:load_into_buf()
        " Auto-save on leave
        augroup WplusScratchBuf
            autocmd! * <buffer>
            autocmd BufLeave <buffer> call s:save()
        augroup END
    else
        " Reopen existing buffer
        execute g:wplus_scratch_position . ' ' . g:wplus_scratch_height . 'split'
        execute 'buffer ' . s:scratch_bufnr
    endif
    normal! G
endfunction

function! wplus#scratch#open_vertical() abort
    if s:is_open()
        call wplus#scratch#toggle()
        return
    endif
    if s:scratch_bufnr == -1 || !bufexists(s:scratch_bufnr)
        vsplit
        enew
        let s:scratch_bufnr = bufnr('%')
        setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
        execute 'setlocal filetype=' . g:wplus_scratch_ft
        call s:load_into_buf()
        augroup WplusScratchBuf
            autocmd! * <buffer>
            autocmd BufLeave <buffer> call s:save()
        augroup END
    else
        vsplit
        execute 'buffer ' . s:scratch_bufnr
    endif
    normal! G
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#scratch#setup() abort
    command! WscratchToggle   call wplus#scratch#toggle()
    command! WscratchVertical call wplus#scratch#open_vertical()

    nnoremap <silent> <leader>sc :WscratchToggle<CR>
    nnoremap <silent> <leader>sv :WscratchVertical<CR>

    " Save on Vim exit
    augroup WplusScratch
        autocmd!
        autocmd VimLeavePre * call s:save()
    augroup END
endfunction
