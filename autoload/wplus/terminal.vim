" wplus/terminal.vim — terminal toggle integration

if exists('g:autoloaded_wplus_terminal') | finish | endif
let g:autoloaded_wplus_terminal = 1

let s:term_buf = -1

function! wplus#terminal#toggle() abort
    if s:term_buf != -1 && bufexists(s:term_buf)
        let l:winid = bufwinid(s:term_buf)
        if l:winid != -1
            " Terminal is visible, hide it
            if winnr('$') > 1
                execute l:winid . 'hide'
            else
                " Don't hide if it's the only window
                echo "Terminal is the only window"
            endif
        else
            " Terminal exists but is hidden, show it
            execute 'botright 10split'
            execute 'buffer' s:term_buf
            startinsert
        endif
    else
        " Create new terminal
        execute 'botright 10split'
        if has('nvim')
            terminal
        else
            terminal ++curwin ++close
        endif
        let s:term_buf = bufnr('%')
        setlocal nobuflisted
    endif
endfunction

function! wplus#terminal#setup() abort
    command! WplusTerminalToggle call wplus#terminal#toggle()
    
    " Mappings
    nnoremap <silent> <leader>tt :WplusTerminalToggle<CR>
    
    " Easy exit from terminal mode
    if has('nvim')
        tnoremap <Esc><Esc> <C-\><C-n>
    else
        tnoremap <Esc><Esc> <C-w>N
    endif
endfunction
