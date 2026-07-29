" wplus/marks.vim — Visual mark indicators in the sign column
" Shows marks a-z as signs; <leader>ml lists all marks in a finder popup.

if exists('g:autoloaded_wplus_marks') | finish | endif
let g:autoloaded_wplus_marks = 1

let g:wplus_marks_sign_prefix = get(g:, 'wplus_marks_sign_prefix', '')
let s:sign_group = 'wplus_marks'
let s:update_timer = -1

" ── sign definitions ──────────────────────────────────────────────────────

function! s:define_signs() abort
    highlight default WplusMarkSign ctermfg=214 guifg=#fabd2f gui=bold
    for l:c in split('abcdefghijklmnopqrstuvwxyz', '\zs')
        call sign_define('WplusMark_' . l:c, {
            \ 'text':   g:wplus_marks_sign_prefix . l:c,
            \ 'texthl': 'WplusMarkSign'
            \ })
    endfor
endfunction

" ── update logic ──────────────────────────────────────────────────────────

function! s:refresh_marks(bufnr) abort
    let l:bufnr = a:bufnr > 0 ? a:bufnr : bufnr('%')
    if !bufloaded(l:bufnr) | return | endif

    call sign_unplace(s:sign_group, {'buffer': l:bufnr})

    for l:c in split('abcdefghijklmnopqrstuvwxyz', '\zs')
        let l:pos = getpos("'" . l:c)
        " pos[0]==0 means mark not set; pos[1] is line (0 = unset for global)
        if l:pos[0] == 0 && l:pos[1] > 0 && l:pos[3] == 0
            " Local mark in current buffer
            call sign_place(0, s:sign_group, 'WplusMark_' . l:c, l:bufnr,
                        \ {'lnum': l:pos[1], 'priority': 5})
        elseif l:pos[0] == l:bufnr && l:pos[1] > 0
            " Mark set in this exact buffer
            call sign_place(0, s:sign_group, 'WplusMark_' . l:c, l:bufnr,
                        \ {'lnum': l:pos[1], 'priority': 5})
        endif
    endfor
endfunction

function! s:schedule_refresh() abort
    if s:update_timer != -1
        call timer_stop(s:update_timer)
    endif
    let s:update_timer = timer_start(150, {_ -> s:refresh_marks(bufnr('%'))})
endfunction

" ── list popup ────────────────────────────────────────────────────────────

function! wplus#marks#list() abort
    let l:items = []
    for l:c in split('abcdefghijklmnopqrstuvwxyz', '\zs')
        let l:pos = getpos("'" . l:c)
        if l:pos[1] > 0
            let l:bufnr = l:pos[0] == 0 ? bufnr('%') : l:pos[0]
            let l:file = bufname(l:bufnr)
            if empty(l:file) | let l:file = '[No Name]' | endif
            let l:display = printf('%s  %s:%d  %s',
                        \ l:c,
                        \ fnamemodify(l:file, ':~:.'),
                        \ l:pos[1],
                        \ trim(get(getbufline(l:bufnr, l:pos[1]), 0, '')))
            call add(l:items, l:display)
        endif
    endfor
    if empty(l:items)
        call wplus#util#info_msg('marks', 'no marks set')
        return
    endif
    call wplus#finder#open(l:items, function('s:jump_to_mark'), 'Marks')
endfunction

function! s:jump_to_mark(item) abort
    let l:c = matchstr(a:item, '^\S')
    if !empty(l:c)
        execute "normal! '" . l:c
    endif
endfunction

" Delete mark at cursor line.
function! wplus#marks#delete_at_cursor() abort
    let l:lnum = line('.')
    for l:c in split('abcdefghijklmnopqrstuvwxyz', '\zs')
        let l:pos = getpos("'" . l:c)
        if l:pos[1] == l:lnum && (l:pos[0] == 0 || l:pos[0] == bufnr('%'))
            execute 'delmarks ' . l:c
            call wplus#util#info_msg('marks', 'deleted mark ' . l:c)
            call s:refresh_marks(bufnr('%'))
            return
        endif
    endfor
    call wplus#util#warn_msg('marks', 'no mark on line ' . l:lnum)
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#marks#setup() abort
    call s:define_signs()

    command! WmarksRefresh call s:refresh_marks(bufnr('%'))
    command! WmarksList    call wplus#marks#list()
    command! WmarksDelete  call wplus#marks#delete_at_cursor()

    nnoremap <silent> <leader>ml :WmarksList<CR>
    nnoremap <silent> <leader>md :WmarksDelete<CR>

    augroup WplusMarks
        autocmd!
        " Refresh after any mark-setting command or buffer switch
        autocmd BufEnter,BufWinEnter * call s:schedule_refresh()
        " After : commands that could set/delete marks
        autocmd CmdlineLeave * call s:schedule_refresh()
    augroup END
endfunction
