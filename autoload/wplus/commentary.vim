" wplus/commentary.vim — comment toggle (replaces vim-commentary)
" Mappings: gcc (line), gc{motion}, gc (visual)

if exists('g:autoloaded_wplus_commentary') | finish | endif
let g:autoloaded_wplus_commentary = 1

" ── helpers ───────────────────────────────────────────────────────────────

function! s:get_cs() abort
    " Returns [left, right] comment strings for current filetype.
    " Falls back to '#' if &commentstring is empty.
    let l:cs = &commentstring
    if empty(l:cs) | let l:cs = '# %s' | endif
    let l:idx = stridx(l:cs, '%s')
    if l:idx < 0
        return [trim(l:cs), '']
    endif
    let l:left  = l:idx > 0 ? trim(strpart(l:cs, 0, l:idx)) : ''
    let l:right = l:idx + 2 < strlen(l:cs) ? trim(strpart(l:cs, l:idx + 2)) : ''
    return [l:left, l:right]
endfunction

function! s:is_commented(line, left, right) abort
    let l:stripped = trim(a:line)
    if !empty(a:left) && !empty(a:right)
        return l:stripped =~# ('^' . escape(a:left, '\/.*$^~[]') . '.*' . escape(a:right, '\/.*$^~[]') . '$')
    elseif !empty(a:right)
        return l:stripped =~# (escape(a:right, '\/.*$^~[]') . '$')
    endif
    return l:stripped =~# ('^' . escape(a:left, '\/.*$^~[]'))
endfunction

function! s:comment_line(lnum, left, right) abort
    let l:line   = getline(a:lnum)
    let l:indent = matchstr(l:line, '^\s*')
    let l:body   = strpart(l:line, strlen(l:indent))
    if empty(a:left) && !empty(a:right)
        call setline(a:lnum, l:indent . l:body . ' ' . a:right)
    elseif empty(a:right)
        call setline(a:lnum, l:indent . a:left . ' ' . l:body)
    else
        call setline(a:lnum, l:indent . a:left . ' ' . l:body . ' ' . a:right)
    endif
endfunction

function! s:uncomment_line(lnum, left, right) abort
    let l:result = getline(a:lnum)
    " Remove left comment token
    if !empty(a:left)
        let l:pat_l = '^\(\s*\)' . escape(a:left, '\/.*$^~[]') . '\s\?'
        let l:result = substitute(l:result, l:pat_l, '\1', '')
    endif
    " Remove right comment token
    if !empty(a:right)
        let l:pat_r = '\s\?' . escape(a:right, '\/.*$^~[]') . '\s*$'
        let l:result = substitute(l:result, l:pat_r, '', '')
    endif
    call setline(a:lnum, l:result)
endfunction

function! wplus#commentary#toggle_range(first, last) abort
    if !&modifiable | return | endif
    let [l:left, l:right] = s:get_cs()
    " Determine action: uncomment only if ALL non-blank lines are commented
    let all_commented = 1
    for lnum in range(a:first, a:last)
        let line = getline(lnum)
        if !empty(trim(line)) && !s:is_commented(line, left, right)
            let all_commented = 0
            break
        endif
    endfor
    for lnum in range(a:first, a:last)
        if empty(trim(getline(lnum))) | continue | endif
        if all_commented
            call s:uncomment_line(lnum, left, right)
        else
            call s:comment_line(lnum, left, right)
        endif
    endfor
endfunction

" ── operator function ─────────────────────────────────────────────────────

function! wplus#commentary#operator(type) abort
    if a:type ==# 'line' || a:type ==# 'V'
        call wplus#commentary#toggle_range(line("'["), line("']"))
    elseif a:type ==# 'char' || a:type ==# 'v'
        " For simplicity treat char/v as full lines
        call wplus#commentary#toggle_range(line("'["), line("']"))
    endif
    silent! call wplus#repeat#set("\<Plug>WplusCommentaryLine", v:count1)
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#commentary#toggle_line() abort
    let l:first = line('.')
    let l:last  = min([line('$'), l:first + v:count1 - 1])
    call wplus#commentary#toggle_range(l:first, l:last)
    silent! call wplus#repeat#set("\<Plug>WplusCommentaryLine", v:count1)
endfunction

function! wplus#commentary#setup() abort
    " gcc — toggle current line (supports [count]gcc)
    nnoremap <silent> gcc :<C-u>call wplus#commentary#toggle_line()<CR>
    " gc{motion}
    nnoremap <silent> gc  :set operatorfunc=wplus#commentary#operator<CR>g@
    " gc / gcc in visual
    xnoremap <silent> gc  :<C-u>call wplus#commentary#toggle_range(line("'<"), line("'>"))<CR>
    xnoremap <silent> gcc :<C-u>call wplus#commentary#toggle_range(line("'<"), line("'>"))<CR>
    " Plug mappings for repeat
    nnoremap <silent> <Plug>WplusCommentaryLine :<C-u>call wplus#commentary#toggle_line()<CR>
endfunction
