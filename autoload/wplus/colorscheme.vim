" wplus/colorscheme.vim — Auto-detect and adjust colors based on background

if exists('g:autoloaded_wplus_colorscheme') | finish | endif
let g:autoloaded_wplus_colorscheme = 1

let g:wplus_colorscheme_auto = get(g:, 'wplus_colorscheme_auto', get(g:, 'wplus_colorscheme_auto_detect', 1))

function! wplus#colorscheme#setup() abort
    if !g:wplus_colorscheme_auto | return | endif
    
    augroup WplusColorScheme
        autocmd!
        autocmd ColorScheme * call s:on_colorscheme_changed()
        autocmd VimEnter * call s:on_colorscheme_changed()
    augroup END
    
    call s:on_colorscheme_changed()
endfunction

function! s:on_colorscheme_changed() abort
    let l:is_dark = s:detect_dark_background()
    call s:adjust_colors(l:is_dark)
endfunction

function! s:detect_dark_background() abort
    " Check &background setting first
    if &background ==# 'dark'
        return 1
    elseif &background ==# 'light'
        return 0
    endif
    
    " Try to detect from colorscheme name
    let l:colorscheme = get(g:, 'colors_name', '')
    if l:colorscheme =~# '\v(dark|black|night|gruvbox.*dark|nord|dracula|monokai|solarized-dark|tokyonight.*night)'
        return 1
    elseif l:colorscheme =~# '\v(light|day|ayu.*light|solarized-light|github.*light)'
        return 0
    endif
    
    " Fallback to terminal background
    return &background ==# 'dark'
endfunction

function! s:adjust_colors(is_dark) abort
    if a:is_dark
        call s:apply_dark_palette()
    else
        call s:apply_light_palette()
    endif
endfunction

function! s:apply_dark_palette() abort
    " Dark background: light text, muted highlights
    " wplus base colors
    highlight WplusStatusline      cterm=NONE ctermfg=250 ctermbg=235 gui=NONE guifg=#bdbdbd guibg=#262626
    highlight WplusStatuslineNC    cterm=NONE ctermfg=243 ctermbg=235 gui=NONE guifg=#767676 guibg=#262626
    
    " Git gutter colors
    highlight WplusGGAdd           ctermfg=142 guifg=#a3be8c
    highlight WplusGGChange        ctermfg=214 guifg=#ebcb8b
    highlight WplusGGDelete        ctermfg=167 guifg=#bf616a
    
    " LSP diagnostics
    highlight WplusDiagError       guifg=#fb4934 ctermfg=167
    highlight WplusDiagWarn        guifg=#fabd2f ctermfg=214
    highlight WplusDiagInfo        guifg=#83a598 ctermfg=109
    highlight WplusDiagHint        guifg=#928374 ctermfg=243
    
    " Yank highlight
    highlight WplusYankHL          guibg=#3a3a3a guifg=#ffffff
    
    " Blame text
    highlight WplusBlameText       guifg=#7c6f64 gui=italic ctermfg=243
endfunction

function! s:apply_light_palette() abort
    " Light background: dark text, stronger highlights
    highlight WplusStatusline      cterm=NONE ctermfg=235 ctermbg=253 gui=NONE guifg=#282828 guibg=#eeeeee
    highlight WplusStatuslineNC    cterm=NONE ctermfg=243 ctermbg=253 gui=NONE guifg=#767676 guibg=#eeeeee
    
    " Git gutter colors (brighter for light bg)
    highlight WplusGGAdd           ctermfg=28 guifg=#3d7e2f
    highlight WplusGGChange        ctermfg=166 guifg=#d79921
    highlight WplusGGDelete        ctermfg=160 guifg=#c6412b
    
    " LSP diagnostics
    highlight WplusDiagError       guifg=#cc241d ctermfg=160
    highlight WplusDiagWarn        guifg=#b57614 ctermfg=166
    highlight WplusDiagInfo        guifg=#076678 ctermfg=24
    highlight WplusDiagHint        guifg=#7c6f64 ctermfg=59
    
    " Yank highlight
    highlight WplusYankHL          guibg=#ffffcc guifg=#000000
    
    " Blame text
    highlight WplusBlameText       guifg=#a89984 gui=italic ctermfg=243
endfunction
