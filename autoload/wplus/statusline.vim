" wplus/statusline.vim — custom statusline (replaces vim-airline)
" Shows: mode | git branch | filename flags | lsp diagnostics | filetype | pos

if exists('g:autoloaded_wplus_statusline') | finish | endif
let g:autoloaded_wplus_statusline = 1

" ── mode labels ───────────────────────────────────────────────────────────
let s:mode_map = {
    \ 'n':  'NORMAL',  'no': 'N·OP',   'nov': 'N·OP',
    \ 'v':  'VISUAL',  'V':  'V·LINE', "\<C-v>": 'V·BLOCK',
    \ 's':  'SELECT',  'S':  'S·LINE', "\<C-s>": 'S·BLOCK',
    \ 'i':  'INSERT',  'ic': 'INSERT', 'ix': 'INSERT',
    \ 'R':  'REPLACE', 'Rv': 'V·REPLACE',
    \ 'c':  'COMMAND', 'cv': 'EX',
    \ 't':  'TERMINAL',
    \ }

" ── highlight groups (initialised once at setup) ──────────────────────────
function! s:init_highlights() abort
    " Base colors pulled from gruvbox palette; gracefully degrade on 256-color
    hi WplusSlNormal  cterm=bold ctermfg=0  ctermbg=214 gui=bold guifg=#282828 guibg=#fabd2f
    hi WplusSlInsert  cterm=bold ctermfg=0  ctermbg=109 gui=bold guifg=#282828 guibg=#83a598
    hi WplusSlVisual  cterm=bold ctermfg=0  ctermbg=175 gui=bold guifg=#282828 guibg=#d3869b
    hi WplusSlReplace cterm=bold ctermfg=0  ctermbg=167 gui=bold guifg=#282828 guibg=#fb4934
    hi WplusSlCommand cterm=bold ctermfg=0  ctermbg=142 gui=bold guifg=#282828 guibg=#b8bb26
    hi WplusSlMid     ctermfg=223 ctermbg=239 guifg=#ebdbb2 guibg=#3c3836
    hi WplusSlRight   ctermfg=246 ctermbg=237 guifg=#a89984 guibg=#3c3836
    hi WplusSlNC      ctermfg=243 ctermbg=237 guifg=#928374 guibg=#3c3836
    hi WplusSlErr     ctermfg=167 ctermbg=239 guifg=#fb4934 guibg=#3c3836
    hi WplusSlWarn    ctermfg=214 ctermbg=239 guifg=#fabd2f guibg=#3c3836
endfunction

" ── helpers ───────────────────────────────────────────────────────────────

function! s:mode_hl() abort
    let m = mode()
    if     m ==# 'i' || m ==# 'ic' || m ==# 'ix' | return 'WplusSlInsert'
    elseif m =~# "^[vV\<C-v>]"                    | return 'WplusSlVisual'
    elseif m =~# '^[rR]'                           | return 'WplusSlReplace'
    elseif m ==# 'c'                               | return 'WplusSlCommand'
    endif
    return 'WplusSlNormal'
endfunction

function! s:mode_label() abort
    return get(s:mode_map, mode(), mode())
endfunction

function! s:git_branch() abort
    if &buftype !=# '' || empty(expand('%:p'))
        return ''
    endif
    " Uses b:wplus_git_branch cached by gitgutter (or direct HEAD read)
    if exists('b:wplus_git_branch') && !empty(b:wplus_git_branch)
        return ' ' . b:wplus_git_branch
    endif
    " Fast fallback: read .git/HEAD
    if !has_key(b:, 'wplus_git_root')
        let b:wplus_git_root = wplus#util#find_git_root(expand('%:p:h'))
    endif
    let root = b:wplus_git_root
    if empty(root) | return '' | endif
    let head = root . '/.git/HEAD'
    if !filereadable(head) | return '' | endif
    let lines = readfile(head)
    if empty(lines) | return '' | endif
    let line = lines[0]
    let branch = line =~# '^ref: ' ? substitute(line, 'ref: refs/heads/', '', '') : line[:6]
    let b:wplus_git_branch = branch
    return ' ' . branch
endfunction

function! s:diagnostics() abort
    let info = get(b:, 'wplus_lsp_diag_counts', {})
    if !empty(info)
        let errs  = get(info, 'error', 0)
        let warns = get(info, 'warning', 0)
        let out = ''
        if errs  > 0 | let out .= '%#WplusSlErr# E:' . errs . ' %#WplusSlMid#' | endif
        if warns > 0 | let out .= '%#WplusSlWarn# W:' . warns . ' %#WplusSlMid#' | endif
        return out
    endif
    " Try coc.nvim diagnostic counts
    if exists('*coc#status')
        let info = get(b:, 'coc_diagnostic_info', {})
        let errs  = get(info, 'error',   0)
        let warns = get(info, 'warning', 0)
        let out = ''
        if errs  > 0 | let out .= '%#WplusSlErr# ✗' . errs . ' %#WplusSlMid#' | endif
        if warns > 0 | let out .= '%#WplusSlWarn# ⚠' . warns . ' %#WplusSlMid#' | endif
        return out
    endif
    return ''
endfunction

function! s:fileflags() abort
    let flags = ''
    if &modified              | let flags .= '[+]'    | endif
    if !&modifiable           | let flags .= '[-]'    | endif
    if &readonly              | let flags .= '[RO]'   | endif
    if &paste                 | let flags .= '[PASTE]' | endif
    return flags
endfunction

" ── build functions (called via %{} in statusline) ────────────────────────

function! wplus#statusline#active() abort
    let hl  = s:mode_hl()
    let sl  = ''
    let sl .= '%#' . hl . '# ' . s:mode_label() . ' '
    let sl .= '%#WplusSlMid# '
    let branch = s:git_branch()
    if !empty(branch) | let sl .= branch . '  ' | endif
    let sl .= '%f '   " filename relative to cwd
    let sl .= s:fileflags()
    let sl .= '%='    " right-align from here
    let sl .= s:diagnostics()
    let sl .= '%#WplusSlRight# '
    let sl .= '%{&filetype!=""?&filetype:"no ft"}  '
    let sl .= '%{&fileencoding!=""?&fileencoding:&encoding}  '
    let sl .= '%l:%c  %p%% '
    return sl
endfunction

function! wplus#statusline#inactive() abort
    return '%#WplusSlNC# %f %='
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#statusline#setup() abort
    call s:init_highlights()
    set laststatus=2
    set statusline=%!wplus#statusline#active()
    augroup wplus_statusline
        autocmd!
        autocmd WinEnter,BufEnter * setlocal statusline=%!wplus#statusline#active()
        autocmd WinLeave           * setlocal statusline=%!wplus#statusline#inactive()
        autocmd User WplusGitGutterUpdate redrawstatus
        " Refresh highlights when colorscheme changes
        autocmd ColorScheme        * call s:init_highlights()
    augroup END
endfunction
