" wplus/textobj.vim — Indent & Argument text objects
"
" Indent text objects:
"   ii  — inner indent (same level, no blank lines at edges)
"   ai  — around indent (include one line above, useful for Python/YAML)
"
" Argument text objects:
"   ia  — inner argument (without surrounding comma/space)
"   aa  — around argument (with trailing comma or leading comma)

function! wplus#textobj#setup() abort
    " Indent text objects
    onoremap <silent> ii :<C-u>call wplus#textobj#indent(0)<CR>
    onoremap <silent> ai :<C-u>call wplus#textobj#indent(1)<CR>
    xnoremap <silent> ii :<C-u>call wplus#textobj#indent(0)<CR>
    xnoremap <silent> ai :<C-u>call wplus#textobj#indent(1)<CR>

    " Argument text objects
    onoremap <silent> ia :<C-u>call wplus#textobj#argument(0)<CR>
    onoremap <silent> aa :<C-u>call wplus#textobj#argument(1)<CR>
    xnoremap <silent> ia :<C-u>call wplus#textobj#argument(0)<CR>
    xnoremap <silent> aa :<C-u>call wplus#textobj#argument(1)<CR>
endfunction

" ── indent text object ────────────────────────────────────────────────────

function! wplus#textobj#indent(around) abort
    let l:curlnum  = line('.')
    let l:curindent = indent(l:curlnum)

    " Find top boundary
    let l:top = l:curlnum
    while l:top > 1
        let l:prev = l:top - 1
        if getline(l:prev) =~# '^\s*$'
            break
        endif
        if indent(l:prev) < l:curindent
            break
        endif
        let l:top = l:prev
    endwhile

    " Find bottom boundary
    let l:bot = l:curlnum
    let l:last = line('$')
    while l:bot < l:last
        let l:next = l:bot + 1
        if getline(l:next) =~# '^\s*$'
            break
        endif
        if indent(l:next) < l:curindent
            break
        endif
        let l:bot = l:next
    endwhile

    " around: include the line above (e.g. def/class header)
    if a:around && l:top > 1
        let l:top -= 1
    endif

    call cursor(l:top, 1)
    normal! V
    call cursor(l:bot, 1)
endfunction

" ── argument text object ─────────────────────────────────────────────────

function! wplus#textobj#argument(around) abort
    let l:line  = getline('.')
    let l:col   = col('.') - 1

    " Find enclosing paren/bracket
    let l:open  = s:find_open(l:line, l:col)
    if l:open < 0
        return
    endif
    let l:close = s:find_close(l:line, l:open)
    if l:close < 0
        return
    endif

    " Find argument boundaries within parens
    let l:inner = l:line[l:open + 1 : l:close - 1]
    let l:offset = l:open + 1

    let [l:astart, l:aend] = s:arg_range(l:inner, l:col - l:offset)

    if l:astart < 0
        return
    endif

    let l:astart += l:offset
    let l:aend   += l:offset

    if a:around
        " Include trailing comma+space or leading comma+space
        if l:line[l:aend + 1] ==# ','
            let l:aend += 1
            if l:line[l:aend + 1] ==# ' '
                let l:aend += 1
            endif
        elseif l:line[l:astart - 1] ==# ' ' && l:line[l:astart - 2] ==# ','
            let l:astart -= 2
        endif
    else
        " Strip surrounding spaces
        while l:astart <= l:aend && l:line[l:astart] ==# ' '
            let l:astart += 1
        endwhile
        while l:aend >= l:astart && l:line[l:aend] ==# ' '
            let l:aend -= 1
        endwhile
    endif

    call cursor(line('.'), l:astart + 1)
    normal! v
    call cursor(line('.'), l:aend + 1)
endfunction

function! s:find_open(line, col) abort
    let l:i = a:col
    let l:depth = 0
    while l:i >= 0
        let l:c = a:line[l:i]
        if l:c ==# ')' || l:c ==# ']'
            let l:depth += 1
        elseif (l:c ==# '(' || l:c ==# '[') && l:depth == 0
            return l:i
        elseif l:c ==# '(' || l:c ==# '['
            let l:depth -= 1
        endif
        let l:i -= 1
    endwhile
    return -1
endfunction

function! s:find_close(line, open) abort
    let l:open_ch  = a:line[a:open]
    let l:close_ch = l:open_ch ==# '(' ? ')' : ']'
    let l:depth = 0
    let l:i = a:open + 1
    while l:i < len(a:line)
        let l:c = a:line[l:i]
        if l:c ==# l:open_ch
            let l:depth += 1
        elseif l:c ==# l:close_ch && l:depth == 0
            return l:i
        elseif l:c ==# l:close_ch
            let l:depth -= 1
        endif
        let l:i += 1
    endwhile
    return -1
endfunction

function! s:arg_range(inner, pos) abort
    let l:len   = len(a:inner)
    let l:depth = 0
    let l:start = 0

    let l:i = 0
    while l:i < l:len
        let l:c = a:inner[l:i]
        if l:c ==# '(' || l:c ==# '[' || l:c ==# '{'
            let l:depth += 1
        elseif l:c ==# ')' || l:c ==# ']' || l:c ==# '}'
            let l:depth -= 1
        elseif l:c ==# ',' && l:depth == 0
            if a:pos >= l:start && a:pos <= l:i - 1
                return [l:start, l:i - 1]
            endif
            let l:start = l:i + 1
        endif
        let l:i += 1
    endwhile

    " Last argument
    if a:pos >= l:start
        return [l:start, l:len - 1]
    endif
    return [-1, -1]
endfunction
