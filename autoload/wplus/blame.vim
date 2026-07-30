" wplus/blame.vim — inline git blame (replaces blamer.nvim / APZelos/blamer.nvim)
" Shows commit info as virtual text at end of current line.
" Requires: Vim 9.1 with prop_add() (text-properties)

if exists('g:autoloaded_wplus_blame') | finish | endif
let g:autoloaded_wplus_blame = 1

let g:wplus_blame_delay        = get(g:, 'wplus_blame_delay',        500)
let g:wplus_blame_prefix       = get(g:, 'wplus_blame_prefix',       '   ')
let g:wplus_blame_template     = get(g:, 'wplus_blame_template',     '<author>, <date> • <summary>')
let g:wplus_blame_date_format  = get(g:, 'wplus_blame_date_format',  '%y/%m/%d')
let g:wplus_blame_enabled_flag = get(g:, 'wplus_blame_enabled_flag', 1)  " runtime toggle

let s:prop_type = 'WplusBlameProp'
let s:timer     = -1
let s:blame_jobs = {} " channel_key -> {bufnr, lnum, lines}

" ── highlight & prop type ─────────────────────────────────────────────────

function! s:init() abort
    " Register text-property type (idempotent)
    if empty(prop_type_get(s:prop_type))
        call prop_type_add(s:prop_type, {'highlight': 'WplusBlameText', 'after': 1})
    endif
endfunction

" ── clear virtual text on current line ────────────────────────────────────

function! s:clear(bufnr, lnum) abort
    try
        call prop_remove({'type': s:prop_type, 'bufnr': a:bufnr, 'all': 1},
                    \ a:lnum, a:lnum)
    catch
    endtry
endfunction

function! s:clear_all(bufnr) abort
    try
        call prop_remove({'type': s:prop_type, 'bufnr': a:bufnr, 'all': 1})
    catch
    endtry
endfunction

" ── git blame callback ────────────────────────────────────────────────────

function! s:on_blame(bufnr, lnum, lines, chan) abort
    if !bufloaded(a:bufnr) | return | endif
    if empty(a:lines) | return | endif

    " porcelain format: first line is hash + metadata keys follow
    let author  = ''
    let summary = ''
    let epoch   = 0
    for l in a:lines
        if l =~# '^author '         | let author  = l[7:] | endif
        if l =~# '^summary '        | let summary = l[8:] | endif
        if l =~# '^author-time '    | let epoch   = str2nr(l[12:]) | endif
    endfor
    if empty(author) || author ==# 'Not Committed Yet' | return | endif

    let date = strftime(g:wplus_blame_date_format, epoch)
    let text = g:wplus_blame_prefix
                \ . substitute(substitute(substitute(g:wplus_blame_template,
                \   '<author>', author, ''), '<date>', date, ''), '<summary>', summary, '')

    call s:clear(a:bufnr, a:lnum)
    try
        call prop_add(a:lnum, 0, {
                    \ 'type':   s:prop_type,
                    \ 'bufnr':  a:bufnr,
                    \ 'text':   text,
                    \ })
    catch
    endtry
endfunction

" ── trigger (debounced) ───────────────────────────────────────────────────

function! s:trigger() abort
    if !g:wplus_blame_enabled_flag | return | endif
    if &buftype !=# '' | return | endif  " skip special buffers

    let bufnr = bufnr('%')
    let lnum  = line('.')
    let file  = expand('%:p')
    if empty(file) | return | endif
    let root = wplus#util#find_git_root(fnamemodify(file, ':p:h'))
    if empty(root)
        call s:clear_all(bufnr)
        return
    endif

    if s:timer != -1
        call timer_stop(s:timer)
    endif
    call s:clear_all(bufnr)

    let lines = []
    let s:timer = timer_start(g:wplus_blame_delay, {_ ->
                \ s:start_job(bufnr, lnum, root, file, lines)})
endfunction

function! s:start_job(bufnr, lnum, root, file, lines) abort
    let s:timer = -1
    let l:job = job_start(
                \ ['git', '-C', a:root, 'blame', '--porcelain', '-L',
                \   a:lnum . ',' . a:lnum, wplus#util#relpath(a:root, a:file)], {
                \ 'out_cb':  {_, l -> add(a:lines, l)},
                \ 'close_cb': function('s:on_blame_complete'),
                \ 'err_cb':  {_ch, _msg -> 0},
                \ })
    if l:job isnot v:null
        let l:key = wplus#util#channel_key(l:job)
        let s:blame_jobs[l:key] = {'bufnr': a:bufnr, 'lnum': a:lnum, 'lines': a:lines}
    endif
endfunction

function! s:on_blame_complete(channel) abort
    let l:key = wplus#util#channel_key(a:channel)
    if !has_key(s:blame_jobs, l:key)
        return
    endif
    let l:data = remove(s:blame_jobs, l:key)
    call s:on_blame(l:data.bufnr, l:data.lnum, l:data.lines, a:channel)
endfunction

" ── public toggle ─────────────────────────────────────────────────────────

function! wplus#blame#toggle() abort
    let g:wplus_blame_enabled_flag = !g:wplus_blame_enabled_flag
    if !g:wplus_blame_enabled_flag
        call s:clear_all(bufnr('%'))
        echo 'wplus-blame: disabled'
    else
        echo 'wplus-blame: enabled'
        call s:trigger()
    endif
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#blame#setup() abort
    call s:init()
    augroup wplus_blame
        autocmd!
        autocmd CursorHold  * call s:trigger()
        autocmd BufLeave    * call s:clear_all(bufnr('%'))
        autocmd BufDelete   * call s:on_buf_delete()
        autocmd InsertEnter * call s:clear_all(bufnr('%'))
    augroup END

    " :BlamerToggle compat alias + <leader>bl
    command! -bar BlamerToggle call wplus#blame#toggle()
    nnoremap <silent> <leader>bl :BlamerToggle<CR>
endfunction

function! s:on_buf_delete() abort
    " Clean up any pending timer for this buffer
    let l:buf = str2nr(expand('<abuf>'))
    let l:blame_timer = getbufvar(l:buf, 'wplus_blame_timer', -1)
    if l:blame_timer != -1
        silent! call timer_stop(l:blame_timer)
    endif
endfunction
