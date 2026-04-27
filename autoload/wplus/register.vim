" wplus/register.vim — Register preview popup (replaces vim-peekaboo)
" Press " or @ in normal mode to see register contents before using them.

if exists('g:autoloaded_wplus_register') | finish | endif
let g:autoloaded_wplus_register = 1

let s:popup_id = -1

" ── helpers ───────────────────────────────────────────────────────────────

function! s:truncate(str, width) abort
    let l:s = substitute(a:str, '\n', '↵ ', 'g')
    let l:s = substitute(l:s, '\t', '→', 'g')
    return len(l:s) > a:width ? l:s[: a:width - 2] . '…' : l:s
endfunction

function! s:build_lines() abort
    let l:names = ['"', '+', '*', '/', ':', '.', '-']
    let l:names += map(range(char2nr('a'), char2nr('z')), 'nr2char(v:val)')
    let l:names += map(range(char2nr('0'), char2nr('9')), 'nr2char(v:val)')

    let l:lines = []
    for l:r in l:names
        let l:val = getreg(l:r)
        if empty(l:val) | continue | endif
        call add(l:lines, printf('  %s  %s', l:r, s:truncate(l:val, 60)))
    endfor
    return empty(l:lines) ? ['  (all registers empty)'] : l:lines
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#register#show(mode) abort
    let l:lines = s:build_lines()
    let s:popup_id = popup_create(l:lines, {
        \ 'title':    ' Registers ',
        \ 'line':     'cursor+1',
        \ 'col':      1,
        \ 'minwidth': 40,
        \ 'maxwidth': 72,
        \ 'maxheight': &lines / 2,
        \ 'border':   [1, 1, 1, 1],
        \ 'borderhighlight': ['WplusRegBorder'],
        \ 'wrap':     0,
        \ 'zindex':   60,
        \ })

    try
        let l:ch = getchar()
    catch
        call popup_close(s:popup_id)
        let s:popup_id = -1
        return ''
    endtry

    call popup_close(s:popup_id)
    let s:popup_id = -1

    let l:key = type(l:ch) == v:t_number ? nr2char(l:ch) : l:ch
    if l:key == "\<Esc>" || l:key == "\<C-c>"
        return ''
    endif

    " Pass through the original prefix + register key
    call feedkeys(a:mode . l:key, 'n')
    return ''
endfunction

" ── highlights ────────────────────────────────────────────────────────────

function! s:init_highlights() abort
    hi default WplusRegBorder ctermfg=239 guifg=#504945
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#register#setup() abort
    call s:init_highlights()
    nnoremap <silent> " :<C-u>call wplus#register#show('"')<CR>
    nnoremap <silent> @ :<C-u>call wplus#register#show('@')<CR>
    augroup wplus_register
        autocmd!
        autocmd ColorScheme * call s:init_highlights()
    augroup END
endfunction
