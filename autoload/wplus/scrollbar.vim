" wplus/scrollbar.vim — Lightweight text-based scrollbar in the sign column
" Renders a scrollbar in the rightmost sign column using Unicode block chars.
" LSP diagnostics (errors/warnings) are overlaid as markers on the bar.

if exists('g:autoloaded_wplus_scrollbar') | finish | endif
let g:autoloaded_wplus_scrollbar = 1

let g:wplus_scrollbar_enabled   = get(g:, 'wplus_scrollbar_enabled', 1)
let g:wplus_scrollbar_char      = get(g:, 'wplus_scrollbar_char', '▐')
let g:wplus_scrollbar_thumb     = get(g:, 'wplus_scrollbar_thumb', '█')
let g:wplus_scrollbar_min_lines = get(g:, 'wplus_scrollbar_min_lines', 50)
let g:wplus_scrollbar_width     = get(g:, 'wplus_scrollbar_width', 1)

let s:sign_group = 'wplus_scrollbar'
let s:diag_group = 'wplus_scrollbar_diag'
let s:update_timer = -1

" ── highlights & signs ────────────────────────────────────────────────────

function! s:init_signs() abort
    highlight default WplusScrollbarTrack ctermfg=238 guifg=#3c3836
    highlight default WplusScrollbarThumb ctermfg=246 guifg=#928374
    highlight default WplusScrollbarError ctermfg=167 guifg=#fb4934
    highlight default WplusScrollbarWarn  ctermfg=214 guifg=#fabd2f

    call sign_define('WplusScrollTrack', {
        \ 'text': g:wplus_scrollbar_char,
        \ 'texthl': 'WplusScrollbarTrack'})
    call sign_define('WplusScrollThumb', {
        \ 'text': g:wplus_scrollbar_thumb,
        \ 'texthl': 'WplusScrollbarThumb'})
    call sign_define('WplusScrollError', {
        \ 'text': '●',
        \ 'texthl': 'WplusScrollbarError'})
    call sign_define('WplusScrollWarn',  {
        \ 'text': '●',
        \ 'texthl': 'WplusScrollbarWarn'})
endfunction

" ── core rendering ────────────────────────────────────────────────────────

function! s:render(bufnr, winid) abort
    if !bufloaded(a:bufnr) | return | endif
    let l:total = line('$', a:winid)
    if l:total < g:wplus_scrollbar_min_lines | return | endif

    " Window geometry
    let l:win_height = winheight(a:winid)
    let l:top = line('w0', a:winid)
    let l:bot = line('w$', a:winid)

    " Unplace previous signs
    call sign_unplace(s:sign_group, {'buffer': a:bufnr})
    call sign_unplace(s:diag_group, {'buffer': a:bufnr})

    " Map each screen row → buffer line for the scrollbar column
    " We distribute scrollbar over the visible buffer line range (1..total).
    let l:ratio = str2float(l:total) / l:win_height

    " Thumb range in line-space
    let l:thumb_top = float2nr(round((l:top - 1) * l:win_height / l:total)) + 1
    let l:thumb_bot = float2nr(round(l:bot * l:win_height / l:total))

    for l:row in range(1, l:win_height)
        let l:lnum = float2nr(ceil(l:row * l:ratio))
        let l:lnum = max([1, min([l:lnum, l:total])])
        if l:row >= l:thumb_top && l:row <= l:thumb_bot
            call sign_place(0, s:sign_group, 'WplusScrollThumb', a:bufnr,
                        \ {'lnum': l:lnum, 'priority': 1})
        else
            call sign_place(0, s:sign_group, 'WplusScrollTrack', a:bufnr,
                        \ {'lnum': l:lnum, 'priority': 1})
        endif
    endfor

    " Overlay LSP diagnostics
    let l:diags = getbufvar(a:bufnr, 'wplus_lsp_diags', {})
    for [l:dline, l:d] in items(l:diags)
        let l:dline = str2nr(l:dline)
        if l:dline < 1 || l:dline > l:total | continue | endif
        let l:sign = get(l:d, 'severity', 1) <= 1 ? 'WplusScrollError' : 'WplusScrollWarn'
        call sign_place(0, s:diag_group, l:sign, a:bufnr, {'lnum': l:dline, 'priority': 3})
    endfor
endfunction

function! s:schedule_render() abort
    if !g:wplus_scrollbar_enabled | return | endif
    if s:update_timer != -1
        call timer_stop(s:update_timer)
    endif
    let l:bufnr = bufnr('%')
    let l:winid = win_getid()
    let s:update_timer = timer_start(80,
        \ {_ -> s:render(l:bufnr, l:winid)})
endfunction

function! wplus#scrollbar#clear(bufnr) abort
    call sign_unplace(s:sign_group, {'buffer': a:bufnr})
    call sign_unplace(s:diag_group, {'buffer': a:bufnr})
endfunction

function! wplus#scrollbar#toggle() abort
    let g:wplus_scrollbar_enabled = !g:wplus_scrollbar_enabled
    if g:wplus_scrollbar_enabled
        call s:schedule_render()
        call wplus#util#info_msg('scrollbar', 'enabled')
    else
        call wplus#scrollbar#clear(bufnr('%'))
        call wplus#util#info_msg('scrollbar', 'disabled')
    endif
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#scrollbar#setup() abort
    call s:init_signs()

    command! WscrollbarToggle call wplus#scrollbar#toggle()
    nnoremap <silent> <leader>sb :WscrollbarToggle<CR>

    augroup WplusScrollbar
        autocmd!
        autocmd WinScrolled,CursorMoved,BufEnter,VimResized * call s:schedule_render()
        " Clear on buffer delete to avoid sign leaks
        autocmd BufDelete * call wplus#scrollbar#clear(expand('<abuf>') + 0)
        " Refresh after LSP diagnostics update (b:wplus_lsp_diags changes)
        autocmd User WplusLspDiagUpdate call s:schedule_render()
    augroup END
endfunction
