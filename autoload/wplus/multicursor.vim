" wplus/multicursor.vim — Multi-cursor: select occurrences and apply edits
" Mappings:
"   <C-n>  — add next occurrence of word under cursor
"   <C-x>  — skip current occurrence, select next
"   <C-a>  — select all occurrences in buffer
"   c      — change all selected occurrences (prompt for replacement)
"   d      — delete all selected occurrences
"   <Esc>  — exit multi-cursor mode

if exists('g:autoloaded_wplus_multicursor') | finish | endif
let g:autoloaded_wplus_multicursor = 1

" ── state ─────────────────────────────────────────────────────────────────

let s:cursors = []   " list of {lnum, col, len, match_id}
let s:active  = 0
let s:word    = ''

" ── highlights ────────────────────────────────────────────────────────────

function! s:init_highlights() abort
    hi default WplusMultiCursor cterm=reverse gui=reverse
endfunction

" ── helpers ───────────────────────────────────────────────────────────────

function! s:add_cursor(lnum, col, len) abort
    let l:pat = '\%' . a:lnum . 'l\%>' . (a:col - 1) . 'c\%<' . (a:col + a:len) . 'c'
    let l:mid = matchadd('WplusMultiCursor', l:pat, 20)
    call add(s:cursors, {'lnum': a:lnum, 'col': a:col, 'len': a:len, 'match_id': l:mid})
endfunction

function! s:clear_all() abort
    for l:c in s:cursors
        silent! call matchdelete(l:c.match_id)
    endfor
    let s:cursors = []
    let s:active  = 0
    let s:word    = ''
    call s:unmap_edit_keys()
    call wplus#illuminate#set_paused(0)
    echo ''
endfunction

function! s:cursor_exists(lnum, col) abort
    for l:c in s:cursors
        if l:c.lnum == a:lnum && l:c.col == a:col
            return 1
        endif
    endfor
    return 0
endfunction

function! s:map_edit_keys() abort
    nnoremap <buffer> <silent> c     :<C-u>call wplus#multicursor#change()<CR>
    nnoremap <buffer> <silent> d     :<C-u>call wplus#multicursor#delete()<CR>
    nnoremap <buffer> <silent> <Esc> :<C-u>call wplus#multicursor#clear()<CR>
endfunction

function! s:unmap_edit_keys() abort
    silent! nunmap <buffer> c
    silent! nunmap <buffer> d
    silent! nunmap <buffer> <Esc>
endfunction

" Move cursor to (lnum, col+1) and search forward for s:word.
" Wraps around once if not found. Moves cursor to the match.
" Returns [lnum, col] or [0,0] if not found anywhere.
function! s:find_next_after(lnum, col) abort
    let l:pat = '\<' . escape(s:word, '\/.*$^~[]') . '\>'
    call cursor(a:lnum, a:col)
    let l:pos = searchpos(l:pat, 'W')
    if l:pos == [0, 0]
        call cursor(1, 1)
        let l:pos = searchpos(l:pat, 'cW')
    endif
    return l:pos
endfunction

function! s:show_status() abort
    echo '[wplus] ' . len(s:cursors) . ' cursors  c=change  d=delete  <C-n>=next  <C-x>=skip  <Esc>=cancel'
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#multicursor#add_next() abort
    let l:word = expand('<cword>')
    if empty(l:word) | return | endif

    if !s:active
        let s:word   = l:word
        let s:active = 1

        " Locate exact start column of word under cursor
        let l:lnum = line('.')
        let l:line = getline(l:lnum)
        let l:col0 = col('.') - 1
        while l:col0 > 0 && l:line[l:col0 - 1] =~# '\w'
            let l:col0 -= 1
        endwhile
        call s:add_cursor(l:lnum, l:col0 + 1, len(l:word))
        call s:map_edit_keys()
        call wplus#illuminate#set_paused(1)
        call s:show_status()
        return
    endif

    if s:word !=# l:word
        call s:clear_all()
        return
    endif

    let l:last = s:cursors[-1]
    let l:pos  = s:find_next_after(l:last.lnum, l:last.col + 1)

    if l:pos == [0, 0]
        echo '[wplus] No more occurrences'
        return
    endif

    if s:cursor_exists(l:pos[0], l:pos[1])
        echo '[wplus] All ' . len(s:cursors) . ' occurrences selected'
        return
    endif

    call s:add_cursor(l:pos[0], l:pos[1], len(s:word))
    call s:show_status()
endfunction

function! wplus#multicursor#skip() abort
    if !s:active || empty(s:cursors) | return | endif

    let l:last = remove(s:cursors, -1)
    silent! call matchdelete(l:last.match_id)

    if empty(s:cursors)
        call s:clear_all()
        return
    endif

    " Add next occurrence after the skipped position
    let l:pos = s:find_next_after(l:last.lnum, l:last.col + 1)
    if l:pos != [0, 0] && !s:cursor_exists(l:pos[0], l:pos[1])
        call s:add_cursor(l:pos[0], l:pos[1], len(s:word))
    endif

    call s:show_status()
endfunction

function! wplus#multicursor#select_all() abort
    let l:word = expand('<cword>')
    if empty(l:word) | return | endif

    call s:clear_all()
    let s:word   = l:word
    let s:active = 1
    call s:map_edit_keys()
    call wplus#illuminate#set_paused(1)

    let l:pat     = '\<' . escape(l:word, '\/.*$^~[]') . '\>'
    let l:savepos = getpos('.')

    call cursor(1, 1)
    let l:pos = searchpos(l:pat, 'cW')
    while l:pos != [0, 0]
        call s:add_cursor(l:pos[0], l:pos[1], len(l:word))
        call cursor(l:pos[0], l:pos[1] + len(l:word))
        let l:pos = searchpos(l:pat, 'W')
    endwhile

    if empty(s:cursors)
        call s:clear_all()
        call setpos('.', l:savepos)
        echo '[wplus] No occurrences found'
        return
    endif

    call cursor(s:cursors[0].lnum, s:cursors[0].col)
    call s:show_status()
endfunction

function! wplus#multicursor#change() abort
    if !s:active || empty(s:cursors) | return | endif

    try
        let l:new = input('Replace "' . s:word . '" → ')
    catch /^Vim:Interrupt$/
        redraw | echo ''
        return
    endtry
    redraw

    " Sort bottom-right first so column offsets stay stable during edits
    let l:sorted = sort(copy(s:cursors), {a, b ->
        \ a.lnum == b.lnum ? b.col - a.col : b.lnum - a.lnum})
    for l:c in l:sorted
        let l:line   = getline(l:c.lnum)
        let l:before = l:c.col > 1 ? l:line[: l:c.col - 2] : ''
        let l:after  = l:line[l:c.col + l:c.len - 1 :]
        call setline(l:c.lnum, l:before . l:new . l:after)
    endfor

    let l:count = len(s:cursors)
    call s:clear_all()
    echo '[wplus] Replaced ' . l:count . ' occurrence(s)'
endfunction

function! wplus#multicursor#delete() abort
    if !s:active || empty(s:cursors) | return | endif

    let l:sorted = sort(copy(s:cursors), {a, b ->
        \ a.lnum == b.lnum ? b.col - a.col : b.lnum - a.lnum})
    for l:c in l:sorted
        let l:line   = getline(l:c.lnum)
        let l:before = l:c.col > 1 ? l:line[: l:c.col - 2] : ''
        let l:after  = l:line[l:c.col + l:c.len - 1 :]
        call setline(l:c.lnum, l:before . l:after)
    endfor

    let l:count = len(s:cursors)
    call s:clear_all()
    echo '[wplus] Deleted ' . l:count . ' occurrence(s)'
endfunction

function! wplus#multicursor#clear() abort
    if !s:active | return | endif
    call s:clear_all()
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#multicursor#setup() abort
    call s:init_highlights()

    command! WmulticursorAddNext   call wplus#multicursor#add_next()
    command! WmulticursorSkip      call wplus#multicursor#skip()
    command! WmulticursorSelectAll call wplus#multicursor#select_all()

    " skip and select-all used to sit on <C-x> and <C-a>, which are Vim's
    " decrement/increment-number commands. Taking those globally is not a
    " trade worth making for a module that is only active on demand, so they
    " live under the <leader>v ("visual multi") prefix instead.
    nnoremap <silent> <C-n>       :<C-u>call wplus#multicursor#add_next()<CR>
    nnoremap <silent> <leader>vx  :<C-u>call wplus#multicursor#skip()<CR>
    nnoremap <silent> <leader>va  :<C-u>call wplus#multicursor#select_all()<CR>

    augroup wplus_multicursor
        autocmd!
        autocmd BufLeave    * call wplus#multicursor#clear()
        autocmd ColorScheme * call s:init_highlights()
    augroup END
endfunction
