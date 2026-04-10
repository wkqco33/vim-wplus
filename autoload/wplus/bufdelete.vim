" wplus/bufdelete.vim — close buffer without closing window
"
" :Bdelete  — delete current buffer, keep window (switch to alt/prev buffer)
" :Bwipeout — wipeout current buffer, keep window
" <leader>bd mapping

function! wplus#bufdelete#setup() abort
    command! -bang Bdelete  call wplus#bufdelete#delete(<bang>0, 0)
    command! -bang Bwipeout call wplus#bufdelete#delete(<bang>0, 1)
    nnoremap <silent> <leader>bd :Bdelete<CR>
    nnoremap <silent> <leader>bD :Bwipeout<CR>
endfunction

function! wplus#bufdelete#delete(force, wipeout) abort
    let l:curbuf = bufnr('%')

    if !a:force && getbufvar(l:curbuf, '&modified')
        echohl WarningMsg
        echomsg '[wplus] buffer has unsaved changes (use ! to force, or :w first)'
        echohl None
        return
    endif

    " Find a suitable buffer to switch to in each window that shows curbuf
    let l:target = s:pick_altbuf(l:curbuf)

    " Switch every window showing this buffer to the target
    let l:cur_win = winnr()
    for l:win in range(1, winnr('$'))
        if winbufnr(l:win) == l:curbuf
            execute l:win . 'wincmd w'
            if l:target == -1
                " No other buffer — open empty buffer
                enew
            else
                execute 'buffer ' . l:target
            endif
        endif
    endfor
    execute l:cur_win . 'wincmd w'

    " Now delete/wipeout the original buffer
    let l:cmd = a:wipeout ? 'bwipeout' : 'bdelete'
    if a:force
        let l:cmd .= '!'
    endif
    silent! execute l:cmd . ' ' . l:curbuf
endfunction

function! s:pick_altbuf(curbuf) abort
    " Prefer the alternate buffer (#)
    let l:alt = bufnr('#')
    if l:alt != -1 && l:alt != a:curbuf && buflisted(l:alt)
        return l:alt
    endif

    " Otherwise pick the previous listed buffer
    for l:buf in reverse(range(1, bufnr('$')))
        if l:buf != a:curbuf && buflisted(l:buf) && bufexists(l:buf)
            return l:buf
        endif
    endfor
    return -1
endfunction
