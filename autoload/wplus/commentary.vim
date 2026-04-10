" wplus/commentary.vim — comment toggle (replaces vim-commentary)
" Mappings: gcc (line), gc{motion}, gc (visual)

if exists('g:autoloaded_wplus_commentary') | finish | endif
let g:autoloaded_wplus_commentary = 1

" ── helpers ───────────────────────────────────────────────────────────────

function! s:get_cs() abort
    " Returns [left, right] comment strings for current filetype.
    " Falls back to '#' if &commentstring is empty.
    let cs = &commentstring
    if empty(cs) | let cs = '# %s' | endif
    let idx = stridx(cs, '%s')
    let left  = trim(cs[:idx - 1])
    let right = idx + 2 <= len(cs) - 1 ? trim(cs[idx + 2:]) : ''
    return [left, right]
endfunction

function! s:is_commented(line, left, right) abort
    let stripped = trim(a:line)
    if !empty(a:right)
        return stripped =~# ('^' . escape(a:left, '\/.*$^~[]') . '.*' . escape(a:right, '\/.*$^~[]') . '$')
    endif
    return stripped =~# ('^' . escape(a:left, '\/.*$^~[]'))
endfunction

function! s:comment_line(lnum, left, right) abort
    let line = getline(a:lnum)
    let indent = matchstr(line, '^\s*')
    let body   = line[len(indent):]
    if empty(a:right)
        call setline(a:lnum, indent . a:left . ' ' . body)
    else
        call setline(a:lnum, indent . a:left . ' ' . body . ' ' . a:right)
    endif
endfunction

function! s:uncomment_line(lnum, left, right) abort
    let line = getline(a:lnum)
    " Remove left comment token
    let pat_l = '^\(\s*\)' . escape(a:left, '\/.*$^~[]') . '\s\?'
    let result = substitute(line, pat_l, '\1', '')
    " Remove right comment token
    if !empty(a:right)
        let pat_r = '\s\?' . escape(a:right, '\/.*$^~[]') . '\s*$'
        let result = substitute(result, pat_r, '', '')
    endif
    call setline(a:lnum, result)
endfunction

function! s:toggle_range(first, last) abort
    let [left, right] = s:get_cs()
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
        call s:toggle_range(line("'["), line("']"))
    elseif a:type ==# 'char' || a:type ==# 'v'
        " For simplicity treat char/v as full lines
        call s:toggle_range(line("'["), line("']"))
    endif
    silent! call wplus#repeat#set("\<Plug>WplusCommentaryLine", v:count1)
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#commentary#toggle_line() abort
    call s:toggle_range(line('.'), line('.'))
    silent! call wplus#repeat#set("\<Plug>WplusCommentaryLine", v:count1)
endfunction

function! wplus#commentary#setup() abort
    " gcc — toggle current line
    nnoremap <silent> gcc :call wplus#commentary#toggle_line()<CR>
    " gc{motion}
    nnoremap <silent> gc  :set operatorfunc=wplus#commentary#operator<CR>g@
    " gc in visual
    xnoremap <silent> gc  :<C-u>call s:toggle_range(line("'<"), line("'>"))<CR>
    " Plug mappings for repeat
    nnoremap <silent> <Plug>WplusCommentaryLine :call wplus#commentary#toggle_line()<CR>
endfunction
