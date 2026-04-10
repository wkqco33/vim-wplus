" wplus/illuminate.vim — highlight same word under cursor (replaces vim-illuminate)
" Uses matchadd() so highlights survive syntax changes.

if exists('g:autoloaded_wplus_illuminate') | finish | endif
let g:autoloaded_wplus_illuminate = 1

let g:wplus_illuminate_delay    = get(g:, 'wplus_illuminate_delay',    200)
let g:wplus_illuminate_ft_block = get(g:, 'wplus_illuminate_ft_block',
    \ ['NERDTree', 'tagbar', 'undotree', 'fzf', 'help', 'qf'])

let s:match_ids = {}  " winid → [match_id, ...]
let s:timer     = -1
let s:last_word = ''

" ── highlight group ───────────────────────────────────────────────────────

function! s:init_highlight() abort
    hi default WplusIlluminate cterm=underline gui=underline guibg=#504945
endfunction

" ── clear matches in current window ──────────────────────────────────────

function! s:clear() abort
    let wid = win_getid()
    for id in get(s:match_ids, wid, [])
        try | call matchdelete(id) | catch | endtry
    endfor
    let s:match_ids[wid] = []
endfunction

" ── apply highlight for word ─────────────────────────────────────────────

function! s:apply(word) abort
    call s:clear()
    if empty(a:word) | return | endif
    let pat = '\<' . escape(a:word, '\/.*$^~[]') . '\>'
    let id = matchadd('WplusIlluminate', pat, 10)
    let wid = win_getid()
    let s:match_ids[wid] = [id]
endfunction

" ── debounced trigger ─────────────────────────────────────────────────────

function! s:trigger() abort
    if index(g:wplus_illuminate_ft_block, &filetype) >= 0
        call s:clear()
        return
    endif
    if s:timer != -1 | call timer_stop(s:timer) | endif
    let s:timer = timer_start(g:wplus_illuminate_delay, {_ -> s:do_illuminate()})
endfunction

function! s:do_illuminate() abort
    let s:timer = -1
    let word = expand('<cword>')
    if word ==# s:last_word && !empty(get(s:match_ids, win_getid(), []))
        return
    endif
    let s:last_word = word
    if word =~# '^\w\+$'
        call s:apply(word)
    else
        call s:clear()
    endif
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#illuminate#setup() abort
    call s:init_highlight()
    augroup wplus_illuminate
        autocmd!
        autocmd CursorMoved,CursorMovedI * call s:trigger()
        autocmd BufLeave,WinLeave        * call s:clear()
        autocmd ColorScheme              * call s:init_highlight()
    augroup END
endfunction
