" wplus/indent.vim — indent guide lines (replaces indentLine)
" Uses 'conceal' to overlay a guide character at each indent level.

if exists('g:autoloaded_wplus_indent') | finish | endif
let g:autoloaded_wplus_indent = 1

let g:wplus_indent_char          = get(g:, 'wplus_indent_char',          '▏')
let g:wplus_indent_ft_exclude    = get(g:, 'wplus_indent_ft_exclude',
            \ ['json', 'markdown', 'help', 'startify', 'NERDTree', 'tagbar', 'undotree'])

" ── conceal-based guide ───────────────────────────────────────────────────
" We replace leading spaces at each tab stop with the guide character via
" syntax match + conceal.

function! wplus#indent#enable() abort
    if index(g:wplus_indent_ft_exclude, &filetype) >= 0 | return | endif

    let sw = shiftwidth()
    " Build a pattern that matches a guide-column space.
    " e.g. shiftwidth=4: match a space at columns 1,5,9,... (1-indexed)
    " We use \%1v, \%5v, … up to 80 columns.
    silent! syntax clear WplusIndentGuide
    let cols = []
    let col = sw  " first guide is at column sw+1 (0-indexed: sw)
    while col <= 80
        call add(cols, printf('\%%%dv ', col + 1))
        let col += sw
    endwhile
    let pattern = '\(' . join(cols, '\|') . '\)'
    execute 'syntax match WplusIndentGuide /' . pattern . '/ containedin=ALL conceal cchar=' . g:wplus_indent_char
    highlight default WplusIndentGuide ctermfg=238 guifg=#504945
    setlocal conceallevel=2
    setlocal concealcursor=niv
endfunction

function! wplus#indent#disable() abort
    silent! syntax clear WplusIndentGuide
endfunction

function! wplus#indent#setup() abort
    augroup wplus_indent
        autocmd!
        autocmd FileType *            call wplus#indent#enable()
        autocmd BufWinEnter *         call wplus#indent#enable()
        autocmd OptionSet shiftwidth  call wplus#indent#enable()
    augroup END
endfunction
