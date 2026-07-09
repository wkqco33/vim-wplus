" wplus/surround.vim — bracket/quote manipulation (replaces vim-surround)
" Mappings:
"   ys{motion}{char}  — surround motion with char
"   yss{char}         — surround current line
"   cs{old}{char}     — change surrounding
"   ds{char}          — delete surrounding
"   S{char}  (visual) — surround selection

if exists('g:autoloaded_wplus_surround') | finish | endif
let g:autoloaded_wplus_surround = 1

" Pair table: trigger char → [open, close]
let s:pairs = {
    \ '(':  ['( ', ' )'],  ')':  ['(',  ')'],
    \ '[':  ['[ ', ' ]'],  ']':  ['[',  ']'],
    \ '{':  ['{ ', ' }'],  '}':  ['{',  '}'],
    \ '<':  ['<',  '>'],   '>':  ['<',  '>'],
    \ '"':  ['"',  '"'],
    \ "'":  ["'",  "'"],
    \ '`':  ['`',  '`'],
    \ 't':  ['',   ''],
    \ }

" ── helpers ───────────────────────────────────────────────────────────────

function! s:get_pair(char) abort
    return get(s:pairs, a:char, [a:char, a:char])
endfunction

function! s:find_surrounding(char) abort
    " Returns [open_line, open_col, close_line, close_col] (1-indexed) or []
    let [open, close] = s:get_pair(a:char)
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
    " Asymmetric pairs: use searchpairpos()
    let open_pos  = searchpairpos(escape(open, '\/'), '', escape(close, '\/'), 'bnW')
    let close_pos = searchpairpos(escape(open, '\/'), '', escape(close, '\/'), 'nW')
    if open_pos == [0, 0] || close_pos == [0, 0] | return [] | endif
    return [open_pos[0], open_pos[1], close_pos[0], close_pos[1]]
endfunction

function! s:delete_surround(char) abort
    let [open, close] = s:get_pair(a:char)
    let pos = s:find_surrounding(open ==# close ? open : open[0])
    if empty(pos) | return | endif
    let [ol, oc, cl, cc] = pos
    " Delete close first (so positions don't shift)
    let cline = getline(cl)
    call setline(cl, cline[: cc - 2] . cline[cc :])
    let oline = getline(ol)
    call setline(ol, oline[: oc - 2] . oline[oc :])
endfunction

function! s:change_surround(old, new) abort
    let [open, close] = s:get_pair(a:old)
    let [nopen, nclose] = s:get_pair(a:new)
    let pos = s:find_surrounding(open ==# close ? open : open[0])
    if empty(pos) | return | endif
    let [ol, oc, cl, cc] = pos
    " Replace close first
    let cline = getline(cl)
    call setline(cl, cline[:cc - 2] . nclose . cline[cc + len(close) - 1:])
    let oline = getline(ol)
    call setline(ol, oline[:oc - 2] . nopen . oline[oc + len(open) - 1:])
endfunction

function! s:surround_range(sl, sc, el, ec, char) abort
    " Insert close then open so line numbers don't shift when on same line.
    let [open, close] = s:get_pair(a:char)
    let eline = getline(a:el)
    call setline(a:el, eline[: a:ec - 1] . close . eline[a:ec :])
    let sline = getline(a:sl)
    call setline(a:sl, sline[: a:sc - 2] . open . sline[a:sc - 1:])
endfunction

" ── operator (for ys) ─────────────────────────────────────────────────────

let s:pending_char = ''

function! wplus#surround#operator(type) abort
    let char = s:pending_char
    let s:pending_char = ''
    if a:type ==# 'line'
        " surround whole line (trim trailing newline)
        let lnum = line('.')
        let line = getline(lnum)
        let [open, close] = s:get_pair(char)
        call setline(lnum, open . trim(line) . close)
    else
        let [sl, sc] = [line("'["), col("'[")]
        let [el, ec] = [line("']"), col("']")]
        call s:surround_range(sl, sc, el, ec, char)
    endif
    silent! call wplus#repeat#set("\<Plug>WplusSurroundYss" . char, v:count1)
endfunction

function! wplus#surround#ys_await() abort
    let s:pending_char = nr2char(getchar())
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
    nnoremap <expr> ys  wplus#surround#ys_await()
    " yss{char} — surround line
    nnoremap <silent> yss :set operatorfunc=wplus#surround#operator<CR>g@_
    " ds{char}
    nnoremap <silent> ds  :call wplus#surround#ds()<CR>
    " cs{old}{new}
    nnoremap <silent> cs  :call wplus#surround#cs()<CR>
    " S{char} visual
    xnoremap <silent> S   :<C-u>call wplus#surround#visual_await()<CR>
endfunction
