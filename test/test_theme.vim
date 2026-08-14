" test/test_theme.vim — Test theme and highlight group definitions

let s:groups = [
    \ 'WplusAISuggest',
    \ 'WplusBlameText',
    \ 'WplusConflictMarker',
    \ 'WplusExplorerRoot',
    \ 'WplusExplorerDir',
    \ 'WplusExplorerDirOpen',
    \ 'WplusGGAdd',
    \ 'WplusGGChange',
    \ 'WplusGGDelete',
    \ 'WplusIlluminate',
    \ 'WplusIndentGuide',
    \ 'WplusDiagError',
    \ 'WplusDiagWarn',
    \ 'WplusDiagInfo',
    \ 'WplusDiagHint',
    \ 'WplusMarkSign',
    \ 'WplusMultiCursor',
    \ 'WplusOutlineHeader',
    \ 'WplusOutlineKind',
    \ 'WplusRegBorder',
    \ 'WplusSlNormal',
    \ 'WplusSlInsert',
    \ 'WplusSlVisual',
    \ 'WplusSlReplace',
    \ 'WplusSlCommand',
    \ 'WplusSlMid',
    \ 'WplusSlRight',
    \ 'WplusSlNC',
    \ 'WplusSlErr',
    \ 'WplusSlWarn',
    \ 'WplusTabSel',
    \ 'WplusTabNormal',
    \ 'WplusTabFill',
    \ 'WplusTabModSel',
    \ 'WplusTabModNorm',
    \ 'WplusTodo',
    \ 'WplusFixme',
    \ 'WplusNote',
    \ 'WplusYankHL',
    \ ]

function! Test_theme_groups_exist_after_colorscheme() abort
    call wplus#theme#setup()
    
    " Switch colorscheme to trigger ColorScheme event
    silent! colorscheme blue
    
    for l:g in s:groups
        call assert_true(hlexists(l:g), 'Group missing: ' . l:g)
        let l:id = hlID(l:g)
        let l:trans_id = synIDtrans(l:id)
        let l:fg = synIDattr(l:trans_id, 'fg')
        let l:bg = synIDattr(l:trans_id, 'bg')
        let l:link = synIDattr(l:id, 'linkto')
        let l:name = synIDattr(l:trans_id, 'name')
        call assert_true(l:fg !=# '' || l:bg !=# '' || l:link !=# '' || l:name !=# '',
            \ 'Group has no color or link attribute: ' . l:g)
    endfor
endfunction

function! Test_theme_user_override_preserved() abort
    set termguicolors
    call wplus#theme#setup()
    highlight WplusGGAdd guifg=#ff0000
    call wplus#theme#apply()
    let l:fg = synIDattr(synIDtrans(hlID('WplusGGAdd')), 'fg')
    call assert_equal('#ff0000', l:fg)
endfunction
