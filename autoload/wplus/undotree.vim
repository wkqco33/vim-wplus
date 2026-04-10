" wplus/undotree.vim — undo history visualiser (replaces mbbill/undotree)
" Opens a sidebar showing the undo tree built from undotree() data.

if exists('g:autoloaded_wplus_undotree') | finish | endif
let g:autoloaded_wplus_undotree = 1

let s:buf_name = '__WplusUndoTree__'
let s:width    = get(g:, 'wplus_undotree_width', 30)

" ── tree rendering ────────────────────────────────────────────────────────

function! s:build_lines(tree, current) abort
    " Flatten the undotree into lines (depth-first, newest-first).
    " a:tree  = undotree() result
    " Returns list of strings to display.
    let lines = ['  Undo Tree', '  ' . repeat('─', s:width - 4), '']
    call s:walk(a:tree.entries, a:current, 0, lines)
    return lines
endfunction

function! s:walk(entries, current, depth, lines) abort
    " Walk entries newest-first
    let sorted = copy(a:entries)
    " reverse to show most-recent at top
    call reverse(sorted)
    for entry in sorted
        let seq   = entry.seq
        let mark  = seq == a:current ? '▶ ' : '  '
        let saved = get(entry, 'save', 0) ? ' [SAVED]' : ''
        let alt   = get(entry, 'alt', [])
        let indent = repeat('  ', a:depth)
        if !empty(alt)
            call add(a:lines, indent . mark . seq . saved . '  ┐')
            " recurse into alt branch
            call s:walk(alt, a:current, a:depth + 1, a:lines)
            call add(a:lines, indent . '        ┘')
        else
            call add(a:lines, indent . mark . seq . saved)
        endif
    endfor
endfunction

" ── buffer management ─────────────────────────────────────────────────────

function! s:get_or_create_buf() abort
    let bufnr = bufnr(s:buf_name)
    if bufnr == -1
        execute 'silent! badd ' . s:buf_name
        let bufnr = bufnr(s:buf_name)
    endif
    return bufnr
endfunction

function! s:is_open() abort
    for win in range(1, winnr('$'))
        if bufname(winbufnr(win)) ==# s:buf_name | return 1 | endif
    endfor
    return 0
endfunction

function! s:refresh(src_bufnr) abort
    let utree   = getbufvar(a:src_bufnr, '', {})
    " We need to call undotree() while src buffer is active
    let prev    = bufnr('%')
    execute 'silent! noautocmd buffer ' . a:src_bufnr
    let tree    = undotree()
    execute 'silent! noautocmd buffer ' . prev

    let current = tree.seq_cur
    let lines   = s:build_lines(tree, current)

    let buf = s:get_or_create_buf()
    call setbufvar(buf, '&modifiable', 1)
    call setbufvar(buf, '&buftype', 'nofile')
    call setbufvar(buf, '&bufhidden', 'hide')
    call setbufvar(buf, '&swapfile', 0)
    call setbufvar(buf, '&buflisted', 0)
    call setbufvar(buf, 'wplus_undotree_src', a:src_bufnr)
    call deletebufline(buf, 1, '$')
    call setbufline(buf, 1, lines)
    call setbufvar(buf, '&modifiable', 0)
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#undotree#toggle() abort
    if s:is_open()
        " close
        for win in range(1, winnr('$'))
            if bufname(winbufnr(win)) ==# s:buf_name
                execute win . 'wincmd w'
                quit
                break
            endif
        endfor
        return
    endif

    let src_bufnr = bufnr('%')
    call s:refresh(src_bufnr)

    " open sidebar
    let buf = s:get_or_create_buf()
    execute 'topleft vertical ' . s:width . 'split'
    execute 'silent! buffer ' . buf
    setlocal winfixwidth nonumber norelativenumber
    setlocal nolist nocursorline colorcolumn=
    setlocal statusline=\ UndoTree

    augroup wplus_undotree_buf
        autocmd!
        autocmd BufWritePost,CursorHold <buffer>
            \ call s:refresh(getbufvar('%', 'wplus_undotree_src', bufnr('#')))
    augroup END
endfunction

function! wplus#undotree#setup() abort
    command! -bar UndotreeToggle call wplus#undotree#toggle()
endfunction
