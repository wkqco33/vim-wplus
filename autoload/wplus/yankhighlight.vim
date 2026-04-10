" wplus/yankhighlight.vim — flash highlight on yank (VSCode-style feedback)

let s:timer = -1
let s:match = -1

function! wplus#yankhighlight#setup() abort
    augroup wplus_yankhighlight
        autocmd!
        autocmd TextYankPost * call s:on_yank()
    augroup END
endfunction

function! s:on_yank() abort
    if s:timer != -1
        call timer_stop(s:timer)
        call s:clear()
    endif

    let l:event = v:event
    if l:event.operator !=# 'y'
        return
    endif

    let [l:startline, l:startcol] = [line("'["), col("'[")]
    let [l:endline,   l:endcol]   = [line("']"), col("']")]

    " Build pattern for the yanked region
    if l:event.visual || l:event.regtype ==# 'v'
        let l:pat = s:visual_pattern(l:startline, l:startcol, l:endline, l:endcol)
    elseif l:event.regtype ==# 'V' || l:startcol == 1 && l:endcol >= len(getline(l:endline))
        " line-wise
        let l:pat = '\%>' . (l:startline - 1) . 'l\%<' . (l:endline + 1) . 'l.*'
    else
        let l:pat = s:visual_pattern(l:startline, l:startcol, l:endline, l:endcol)
    endif

    let s:match = matchadd('WplusYankHL', l:pat, 100)
    let s:timer = timer_start(
        \ get(g:, 'wplus_yank_duration', 250),
        \ {_ -> s:clear()})
endfunction

function! s:visual_pattern(sl, sc, el, ec) abort
    if a:sl == a:el
        return '\%' . a:sl . 'l\%>' . (a:sc - 1) . 'c\%<' . (a:ec + 1) . 'c'
    endif
    let l:parts = ['\%' . a:sl . 'l\%>' . (a:sc - 1) . 'c']
    for l:lnum in range(a:sl + 1, a:el - 1)
        let l:parts += ['\%' . l:lnum . 'l']
    endfor
    let l:parts += ['\%' . a:el . 'l\%<' . (a:ec + 1) . 'c']
    return join(l:parts, '\|')
endfunction

function! s:clear() abort
    if s:match != -1
        silent! call matchdelete(s:match)
        let s:match = -1
    endif
    let s:timer = -1
endfunction

" Highlight group (links to Visual by default, customizable)
function! wplus#yankhighlight#init_hl() abort
    highlight default WplusYankHL ctermbg=214 ctermfg=0 guibg=#fabd2f guifg=#282828
endfunction

augroup wplus_yankhighlight_hl
    autocmd!
    autocmd ColorScheme * call wplus#yankhighlight#init_hl()
augroup END
call wplus#yankhighlight#init_hl()
