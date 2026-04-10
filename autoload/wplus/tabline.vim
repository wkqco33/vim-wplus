" wplus/tabline.vim — custom tabline showing buffer list (replaces airline tabline)
" Shows all listed buffers; active buffer is highlighted.

if exists('g:autoloaded_wplus_tabline') | finish | endif
let g:autoloaded_wplus_tabline = 1

function! s:init_highlights() abort
    hi WplusTabSel     cterm=bold ctermfg=0  ctermbg=214 gui=bold guifg=#282828 guibg=#fabd2f
    hi WplusTabNormal  ctermfg=243 ctermbg=237 guifg=#928374 guibg=#3c3836
    hi WplusTabFill    ctermfg=243 ctermbg=237 guifg=#928374 guibg=#3c3836
    hi WplusTabModSel  cterm=bold ctermfg=0  ctermbg=167 gui=bold guifg=#282828 guibg=#fb4934
    hi WplusTabModNorm ctermfg=167 ctermbg=237 guifg=#fb4934 guibg=#3c3836
endfunction

function! wplus#tabline#render() abort
    let current = bufnr('%')
    let bufs    = filter(range(1, bufnr('$')), 'buflisted(v:val)')
    let out     = ''
    for bufnum in bufs
        let name = fnamemodify(bufname(bufnum), ':t')
        if empty(name) | let name = '[No Name]' | endif
        let modified = getbufvar(bufnum, '&modified')
        if bufnum == current
            let hl = modified ? 'WplusTabModSel' : 'WplusTabSel'
        else
            let hl = modified ? 'WplusTabModNorm' : 'WplusTabNormal'
        endif
        let out .= '%#' . hl . '#'
        let out .= ' %' . bufnum . '@wplus#tabline#click@ '
        let out .= name
        if modified | let out .= ' ●' | endif
        let out .= ' '
    endfor
    let out .= '%#WplusTabFill#%T'  " fill rest with background
    return out
endfunction

" Click handler for mouse support
function! wplus#tabline#click(bufnum, ...) abort
    execute 'buffer ' . a:bufnum
endfunction

function! wplus#tabline#setup() abort
    call s:init_highlights()
    set showtabline=2
    set tabline=%!wplus#tabline#render()
    augroup wplus_tabline
        autocmd!
        autocmd BufAdd,BufDelete,BufEnter,BufWipeout * set tabline=%!wplus#tabline#render()
        autocmd ColorScheme * call s:init_highlights()
    augroup END
endfunction
