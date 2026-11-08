" wplus/surround.vim — bracket/quote manipulation (replaces vim-surround)
" Mappings:
"   ys{motion}{char}  — surround motion with char
"   yss{char}         — surround current line
"   cs{old}{char}     — change surrounding
"   ds{char}          — delete surrounding
"   S{char}  (visual) — surround selection

if exists('g:autoloaded_wplus_surround') | finish | endif
let g:autoloaded_wplus_surround = 1

" Pair table: trigger char → [open, close] as *inserted*.
"
" The opening-bracket triggers insert padding ( ys( → "( x )" ) while the
" closing-bracket triggers do not ( ys) → "(x)" ). That padding must never reach
" the matching code -- use s:bare_pair() there. 't' (HTML tag) used to map to
" ['',''], which made yst/cst/dst silently do nothing; an absent entry at least
" falls through to the [char, char] default.
let s:pairs = {
    \ '(':  ['( ', ' )'],  ')':  ['(',  ')'],
    \ '[':  ['[ ', ' ]'],  ']':  ['[',  ']'],
    \ '{':  ['{ ', ' }'],  '}':  ['{',  '}'],
    \ '<':  ['<',  '>'],   '>':  ['<',  '>'],
    \ '"':  ['"',  '"'],
    \ "'":  ["'",  "'"],
    \ '`':  ['`',  '`'],
    \ }

" ── helpers ───────────────────────────────────────────────────────────────

function! s:get_pair(char) abort
    return get(s:pairs, a:char, [a:char, a:char])
endfunction

" The delimiters to *match* against buffer text: single characters, with the
" cosmetic padding from s:pairs stripped.
"
" Matching used to run against the padded forms, so searchpairpos() looked for
" the two-character sequence "( " and missed every "foo(bar)", while
" s:change_surround() advanced by len(' )') == 2 and ate one character too many.
function! s:bare_pair(char) abort
    let [l:open, l:close] = s:get_pair(a:char)
    return [trim(l:open), trim(l:close)]
endfunction

function! s:find_surrounding(char) abort
    " Returns [open_line, open_col, close_line, close_col] (1-indexed) or []
    let [open, close] = s:bare_pair(a:char)
    " For symmetric chars (quotes, backtick) search forward from cursor
    if open ==# close
        let line = getline('.')
        let col  = col('.')  " 1-indexed
        " search backwards for open
        let start = -1
        let i = col - 2  " 0-indexed
        while i >= 0
            if line[i] ==# open
                let start = i
                break
            endif
            let i -= 1
        endwhile
        if start == -1 | return [] | endif
        " search forwards for close
        let i = col - 1
        while i < len(line)
            if line[i] ==# close
                return [line('.'), start + 1, line('.'), i + 1]
            endif
            let i += 1
        endwhile
        return []
    endif
    " Asymmetric pairs: use searchpairpos().
    " \V (very nomagic) so bracket delimiters are matched literally -- escaping
    " only \ and / left '[' to open a regex character class, which made ds]/cs]
    " and friends silently find nothing.
    let l:o = '\V' . escape(open, '\')
    let l:c = '\V' . escape(close, '\')
    let open_pos  = searchpairpos(l:o, '', l:c, 'bnW')
    let close_pos = searchpairpos(l:o, '', l:c, 'nW')
    if open_pos == [0, 0] || close_pos == [0, 0] | return [] | endif
    return [open_pos[0], open_pos[1], close_pos[0], close_pos[1]]
endfunction

function! s:char_byte_len(str, byte_idx) abort
    if a:byte_idx < 0 || a:byte_idx >= strlen(a:str)
        return 0
    endif
    return max([1, strlen(matchstr(a:str, '.', a:byte_idx))])
endfunction

function! s:delete_surround(char) abort
    let [l:open, l:close] = s:bare_pair(a:char)
    let l:pos = s:find_surrounding(l:open ==# l:close ? l:open : l:open)
    if empty(l:pos) | return | endif
    let [l:ol, l:oc, l:cl, l:cc] = l:pos
    " Delete close first (so positions don't shift)
    let l:cline = getline(l:cl)
    let l:clen = s:char_byte_len(l:cline, l:cc - 1)
    call setline(l:cl, strpart(l:cline, 0, l:cc - 1) . strpart(l:cline, l:cc - 1 + l:clen))
    let l:oline = getline(l:ol)
    let l:olen = s:char_byte_len(l:oline, l:oc - 1)
    call setline(l:ol, strpart(l:oline, 0, l:oc - 1) . strpart(l:oline, l:oc - 1 + l:olen))
endfunction

function! s:change_surround(old, new) abort
    let [l:open, l:close] = s:bare_pair(a:old)
    let [l:nopen, l:nclose] = s:get_pair(a:new)
    let l:pos = s:find_surrounding(l:open ==# l:close ? l:open : l:open)
    if empty(l:pos) | return | endif
    let [l:ol, l:oc, l:cl, l:cc] = l:pos
    " Replace close first so the open position stays valid.
    let l:cline = getline(l:cl)
    let l:clen = s:char_byte_len(l:cline, l:cc - 1)
    call setline(l:cl, strpart(l:cline, 0, l:cc - 1) . l:nclose . strpart(l:cline, l:cc - 1 + l:clen))
    let l:oline = getline(l:ol)
    let l:olen = s:char_byte_len(l:oline, l:oc - 1)
    call setline(l:ol, strpart(l:oline, 0, l:oc - 1) . l:nopen . strpart(l:oline, l:oc - 1 + l:olen))
endfunction

function! s:surround_range(sl, sc, el, ec, char) abort
    " Insert close then open so line numbers don't shift when on same line.
    let [l:open, l:close] = s:get_pair(a:char)
    let l:eline = getline(a:el)
    let l:elen = s:char_byte_len(l:eline, a:ec - 1)
    let l:end_after = a:ec - 1 + l:elen
    call setline(a:el, strpart(l:eline, 0, l:end_after) . l:close . strpart(l:eline, l:end_after))
    let l:sline = getline(a:sl)
    call setline(a:sl, strpart(l:sline, 0, a:sc - 1) . l:open . strpart(l:sline, a:sc - 1))
endfunction

" ── operator (for ys) ─────────────────────────────────────────────────────

let s:pending_char = ''

function! s:surround_line(lnum, char) abort
    let l:line = getline(a:lnum)
    let l:indent = matchstr(l:line, '^\s*')
    let [l:open, l:close] = s:get_pair(a:char)
    call setline(a:lnum, l:indent . l:open . trim(l:line) . l:close)
endfunction

function! wplus#surround#operator(type) abort
    let l:char = s:pending_char
    let s:pending_char = ''
    if empty(l:char)
        let l:char = nr2char(getchar())
    endif
    if empty(l:char) | return | endif
    if a:type ==# 'line'
        call s:surround_line(line('.'), l:char)
    else
        let [l:sl, l:sc] = [line("'["), col("'[")]
        let [l:el, l:ec] = [line("']"), col("']")]
        call s:surround_range(l:sl, l:sc, l:el, l:ec, l:char)
    endif
    silent! call wplus#repeat#set("\<Plug>WplusSurroundYss" . l:char, v:count1)
endfunction

function! wplus#surround#yss() abort
    let l:char = nr2char(getchar())
    if empty(l:char) | return | endif
    call s:surround_line(line('.'), l:char)
    silent! call wplus#repeat#set("\<Plug>WplusSurroundYss" . l:char, v:count1)
endfunction

function! wplus#surround#ys_await() abort
    set operatorfunc=wplus#surround#operator
    return 'g@'
endfunction

" ── visual surround (S) ───────────────────────────────────────────────────

function! wplus#surround#visual(char) abort
    let [sl, sc] = [line("'<"), col("'<")]
    let [el, ec] = [line("'>"), col("'>")]
    call s:surround_range(sl, sc, el, ec, a:char)
endfunction

function! wplus#surround#visual_await() abort
    let char = nr2char(getchar())
    call wplus#surround#visual(char)
endfunction

" ── delete/change surround ────────────────────────────────────────────────

function! wplus#surround#ds() abort
    let char = nr2char(getchar())
    call s:delete_surround(char)
    silent! call wplus#repeat#set("\<Plug>WplusSurroundDs" . char, v:count1)
endfunction

function! wplus#surround#cs() abort
    let old  = nr2char(getchar())
    let new  = nr2char(getchar())
    call s:change_surround(old, new)
    silent! call wplus#repeat#set("\<Plug>WplusSurroundCs" . old . new, v:count1)
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#surround#setup() abort
    " ys{motion}{char}
    nnoremap <silent> ys  :set operatorfunc=wplus#surround#operator<CR>g@
    " yss{char} — surround line
    nnoremap <silent> yss :<C-u>call wplus#surround#yss()<CR>
    " ds{char}
    nnoremap <silent> ds  :call wplus#surround#ds()<CR>
    " cs{old}{new}
    nnoremap <silent> cs  :call wplus#surround#cs()<CR>
    " S{char} visual
    xnoremap <silent> S   :<C-u>call wplus#surround#visual_await()<CR>
endfunction
