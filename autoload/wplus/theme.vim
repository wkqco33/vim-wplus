" wplus/theme.vim — Unified theme and highlight management

if exists('g:autoloaded_wplus_theme') | finish | endif
let g:autoloaded_wplus_theme = 1

let g:wplus_theme_auto = get(g:, 'wplus_theme_auto', get(g:, 'wplus_colorscheme_auto', get(g:, 'wplus_colorscheme_auto_detect', 1)))

" Module-registered group definitions: { group_name: spec_dict_or_string }
let s:registered_groups = {}

function! wplus#theme#setup() abort
    if !g:wplus_theme_auto | return | endif

    augroup WplusTheme
        autocmd!
        autocmd ColorScheme,VimEnter * call wplus#theme#apply()
    augroup END

    call wplus#theme#apply()
endfunction

function! wplus#theme#register(groups) abort
    call extend(s:registered_groups, a:groups)
    call wplus#theme#apply()
endfunction

function! s:is_dark() abort
    return &background !=# 'light'
endfunction

function! wplus#theme#apply() abort
    let l:dark = s:is_dark()
    
    let l:p = l:dark ? {
        \ 'added':      'guifg=#a3be8c ctermfg=142',
        \ 'changed':    'guifg=#ebcb8b ctermfg=214',
        \ 'removed':    'guifg=#bf616a ctermfg=167',
        \ 'error':      'guifg=#fb4934 ctermfg=167',
        \ 'warn':       'guifg=#fabd2f ctermfg=214',
        \ 'info':       'guifg=#83a598 ctermfg=109',
        \ 'hint':       'guifg=#928374 ctermfg=243',
        \ 'subtle':     'guifg=#504945 ctermfg=238',
        \ 'accent':     'guifg=#fabd2f ctermfg=214',
        \ 'magenta':    'guifg=#d3869b ctermfg=175',
        \ 'fg_normal':  'guifg=#ebdbb2 ctermfg=223',
        \ 'fg_muted':   'guifg=#a89984 ctermfg=246',
        \ 'bg_dark':    'guifg=#282828 ctermfg=235',
        \ 'bg_mid':     'guibg=#3c3836 ctermbg=237',
        \ 'sel_bg':     'guibg=#504945 ctermbg=238',
        \ 'yank_bg':    'guibg=#3a3a3a ctermbg=237',
        \ 'yank_fg':    'guifg=#ffffff ctermfg=15',
        \ } : {
        \ 'added':      'guifg=#3d7e2f ctermfg=28',
        \ 'changed':    'guifg=#d79921 ctermfg=166',
        \ 'removed':    'guifg=#c6412b ctermfg=160',
        \ 'error':      'guifg=#cc241d ctermfg=160',
        \ 'warn':       'guifg=#b57614 ctermfg=166',
        \ 'info':       'guifg=#076678 ctermfg=24',
        \ 'hint':       'guifg=#7c6f64 ctermfg=59',
        \ 'subtle':     'guifg=#d5c4a1 ctermfg=250',
        \ 'accent':     'guifg=#b57614 ctermfg=166',
        \ 'magenta':    'guifg=#8f3f71 ctermfg=96',
        \ 'fg_normal':  'guifg=#3c3836 ctermfg=237',
        \ 'fg_muted':   'guifg=#7c6f64 ctermfg=243',
        \ 'bg_dark':    'guifg=#fbf1c7 ctermfg=229',
        \ 'bg_mid':     'guibg=#ebdbb2 ctermbg=223',
        \ 'sel_bg':     'guibg=#ebdbb2 ctermbg=223',
        \ 'yank_bg':    'guibg=#ffffcc ctermbg=229',
        \ 'yank_fg':    'guifg=#000000 ctermfg=0',
        \ }

    let l:defaults = {
        \ 'WplusAISuggest': l:p.hint,
        \ 'WplusBlameText': l:p.hint . ' gui=italic',
        \ 'WplusConflictMarker': l:p.error . ' gui=bold',
        \ 'WplusExplorerRoot': 'link Title',
        \ 'WplusExplorerDir': 'link Directory',
        \ 'WplusExplorerDirOpen': 'link Directory',
        \ 'WplusGGAdd': l:p.added,
        \ 'WplusGGChange': l:p.changed,
        \ 'WplusGGDelete': l:p.removed,
        \ 'WplusIlluminate': 'cterm=underline gui=underline ' . l:p.sel_bg,
        \ 'WplusIndentGuide': l:p.subtle,
        \ 'WplusDiagError': l:p.error,
        \ 'WplusDiagWarn': l:p.warn,
        \ 'WplusDiagInfo': l:p.info,
        \ 'WplusDiagHint': l:p.hint,
        \ 'WplusMarkSign': l:p.warn . ' gui=bold',
        \ 'WplusMultiCursor': 'cterm=reverse gui=reverse guifg=#282828 guibg=#ebdbb2 ctermfg=235 ctermbg=223',
        \ 'WplusOutlineHeader': 'link Title',
        \ 'WplusOutlineKind': 'link Keyword',
        \ 'WplusRegBorder': l:p.subtle,
        \ 'WplusSlNormal': 'gui=bold cterm=bold guifg=#282828 ctermfg=0 guibg=#fabd2f ctermbg=214',
        \ 'WplusSlInsert': 'gui=bold cterm=bold guifg=#282828 ctermfg=0 guibg=#83a598 ctermbg=109',
        \ 'WplusSlVisual': 'gui=bold cterm=bold guifg=#282828 ctermfg=0 guibg=#d3869b ctermbg=175',
        \ 'WplusSlReplace': 'gui=bold cterm=bold guifg=#282828 ctermfg=0 guibg=#fb4934 ctermbg=167',
        \ 'WplusSlCommand': 'gui=bold cterm=bold guifg=#282828 ctermfg=0 guibg=#b8bb26 ctermbg=142',
        \ 'WplusSlMid': l:p.fg_normal . ' ' . l:p.bg_mid,
        \ 'WplusSlRight': l:p.fg_muted . ' ' . l:p.bg_mid,
        \ 'WplusSlNC': l:p.hint . ' ' . l:p.bg_mid,
        \ 'WplusSlErr': l:p.error . ' ' . l:p.bg_mid,
        \ 'WplusSlWarn': l:p.warn . ' ' . l:p.bg_mid,
        \ 'WplusTabSel': 'gui=bold cterm=bold guifg=#282828 ctermfg=0 guibg=#fabd2f ctermbg=214',
        \ 'WplusTabNormal': l:p.hint . ' ' . l:p.bg_mid,
        \ 'WplusTabFill': l:p.hint . ' ' . l:p.bg_mid,
        \ 'WplusTabModSel': 'gui=bold cterm=bold guifg=#282828 ctermfg=0 guibg=#fb4934 ctermbg=167',
        \ 'WplusTabModNorm': l:p.error . ' ' . l:p.bg_mid,
        \ 'WplusTodo': 'gui=bold cterm=bold guibg=#fabd2f guifg=#282828 ctermbg=214 ctermfg=235',
        \ 'WplusFixme': 'gui=bold cterm=bold guibg=#fb4934 guifg=#282828 ctermbg=167 ctermfg=235',
        \ 'WplusNote': 'gui=bold cterm=bold guibg=#83a598 guifg=#282828 ctermbg=109 ctermfg=235',
        \ 'WplusYankHL': l:p.yank_bg . ' ' . l:p.yank_fg,
        \ }

    " Apply defaults
    for [l:group, l:spec] in items(l:defaults)
        if l:spec =~# '^link\s\+'
            let l:target = matchstr(l:spec, '^link\s\+\zs.*')
            execute 'highlight default link' l:group l:target
        else
            execute 'highlight default' l:group l:spec
        endif
    endfor

    " Apply module-registered overrides if any
    for [l:group, l:spec] in items(s:registered_groups)
        if l:spec =~# '^link\s\+'
            let l:target = matchstr(l:spec, '^link\s\+\zs.*')
            execute 'highlight default link' l:group l:target
        else
            execute 'highlight default' l:group l:spec
        endif
    endfor
endfunction
