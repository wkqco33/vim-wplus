" wplus/format.vim — Smart formatter (Alt+Shift+F)
" Priority: coc/LSP → external tool → ALE → vim indent

" ── external formatter map ────────────────────────────────────────────────
" Values:
"   cmd      : shell command (reads stdin, writes stdout)
"   filepath : if 1, append shellescape(expand('%')) to cmd (for prettier etc.)
"   check    : binary name to check with executable() [defaults to first word of cmd]
"   tmpfile  : if 1, write buffer to temp file, run cmd on it, read back result
let s:fmts = {
    \ 'go':         { 'cmd': 'goimports' },
    \ 'rust':       { 'cmd': 'rustfmt' },
    \ 'python':     { 'cmd': 'autopep8 -' },
    \ 'c':          { 'cmd': 'clang-format' },
    \ 'cpp':        { 'cmd': 'clang-format' },
    \ 'javascript': { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'javascriptreact': { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'typescript': { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'typescriptreact': { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'json':       { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'yaml':       { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'html':       { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'css':        { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'scss':       { 'cmd': 'prettier --stdin-filepath', 'filepath': 1 },
    \ 'sh':         { 'cmd': 'shfmt' },
    \ 'bash':       { 'cmd': 'shfmt' },
    \ 'lua':        { 'cmd': 'stylua -' },
    \ 'dart':       { 'cmd': 'dart format --line-length 120', 'check': 'dart', 'tmpfile': 1 },
    \ }

let g:wplus_format_on_save = get(g:, 'wplus_format_on_save', 0)

" ── public API ───────────────────────────────────────────────────────────

function! wplus#format#run() abort
    if &buftype !=# '' || !&modifiable
        call wplus#util#warn_msg('format', 'current buffer is not formattable')
        return
    endif
    if s:try_lsp()      | return | endif
    if s:try_external() | return | endif
    if s:try_ale()      | return | endif
    call s:vim_indent()
endfunction

function! wplus#format#range() abort
    if exists('*CocAction') && s:coc_ready()
        call CocAction('formatSelected', visualmode())
    else
        silent normal! gv=
        redraw!
        echo '[wplus] formatted selection (indent)'
    endif
endfunction

function! wplus#format#setup() abort
    augroup WplusFormat
        autocmd!
        autocmd BufWritePre * if get(g:, 'wplus_format_on_save', 0) && &buftype ==# '' && &modifiable | call wplus#format#run() | endif
    augroup END

    nnoremap <silent> <M-F> :call wplus#format#run()<CR>
    nnoremap <silent> <leader>i :call wplus#format#run()<CR>
    inoremap <silent> <M-F> <Esc>:call wplus#format#run()<CR>
    vnoremap <silent> <M-F> :<C-u>call wplus#format#range()<CR>
    vnoremap <silent> <leader>i :<C-u>call wplus#format#range()<CR>
endfunction

" ── internals ────────────────────────────────────────────────────────────

function! s:coc_ready() abort
    return exists('*CocHasProvider') && CocHasProvider('format')
endfunction

function! s:try_lsp() abort
    let l:ft = &filetype
    if get(g:, 'wplus_lsp_enabled', 1) && !empty(l:ft)
        " Try built-in wplus LSP formatter if available
        try
            call wplus#lsp#format(bufnr('%'))
            return 1
        catch
        endtry
    endif
    if s:coc_ready()
        call CocAction('format')
        call wplus#util#info_msg('format', 'formatted (coc/LSP)')
        return 1
    endif
    return 0
endfunction

function! s:try_external() abort
    let l:ft = &filetype
    if !has_key(s:fmts, l:ft)
        return 0
    endif

    let l:spec = s:fmts[l:ft]
    let l:cmd  = l:spec.cmd

    " Append filepath for tools like prettier
    if get(l:spec, 'filepath', 0)
        let l:fname = expand('%')
        if empty(l:fname)
            let l:fname = 'file.' . l:ft
        endif
        let l:cmd .= ' ' . shellescape(l:fname)
    endif

    " Check binary availability
    let l:bin = get(l:spec, 'check', split(l:cmd)[0])
    if !executable(l:bin)
        " Try gofmt as fallback for Go
        if l:ft ==# 'go' && executable('gofmt')
            let l:cmd = 'gofmt'
            let l:bin = 'gofmt'
        else
            return 0
        endif
    endif

    if get(l:spec, 'tmpfile', 0)
        return s:run_tmpfile_fmt(l:cmd, l:bin)
    endif
    return s:run_stdin_fmt(l:cmd, l:bin)
endfunction

" Restore the buffer to a captured snapshot.
"
" This replaces what used to be `silent undo`. Two things were wrong with that:
" the undo point it relied on was never created (undofile() returns the name of
" the undo file, it does not write an undo entry), and if the filter produced no
" change at all there was nothing to undo, so `undo` reverted the *user's*
" previous edit instead.
function! s:restore(lines) abort
    if getline(1, '$') ==# a:lines
        return
    endif
    call setline(1, a:lines)
    if line('$') > len(a:lines)
        call deletebufline('%', len(a:lines) + 1, line('$'))
    endif
endfunction

function! s:run_stdin_fmt(cmd, bin) abort
    let l:view = winsaveview()
    let l:orig = getline(1, '$')

    silent execute '%!' . a:cmd

    if v:shell_error != 0
        call s:restore(l:orig)
        call wplus#util#warn_msg('format', 'formatter failed: ' . a:bin . ' (exit ' . v:shell_error . ')')
        call winrestview(l:view)
        return 0
    endif

    " Guard against empty output (some tools output nothing on failure)
    if getline(1, '$') == ['']
        call s:restore(l:orig)
        call wplus#util#warn_msg('format', 'formatter returned empty output: ' . a:bin)
        call winrestview(l:view)
        return 0
    endif

    if getline(1, '$') ==# l:orig
        call winrestview(l:view)
        redraw!
        call wplus#util#info_msg('format', 'already formatted (' . a:bin . ')')
        return 1
    endif

    call winrestview(l:view)
    redraw!
    call wplus#util#info_msg('format', 'formatted (' . a:bin . ')')
    return 1
endfunction

function! s:run_tmpfile_fmt(cmd, bin) abort
    let l:view = winsaveview()
    let l:orig = getline(1, '$')
    let l:ext = expand('%:e')
    let l:tmp = tempname() . (empty(l:ext) ? '' : '.' . l:ext)

    call writefile(l:orig, l:tmp)
    call system(a:cmd . ' ' . shellescape(l:tmp))

    if v:shell_error != 0
        call delete(l:tmp)
        call wplus#util#warn_msg('format', 'formatter failed: ' . a:bin . ' (exit ' . v:shell_error . ')')
        return 0
    endif

    let l:result = readfile(l:tmp)
    call delete(l:tmp)

    if l:result ==# l:orig
        call winrestview(l:view)
        redraw
        call wplus#util#info_msg('format', 'already formatted (' . a:bin . ')')
        return 1
    endif

    silent execute '%delete _'
    call setline(1, l:result)
    call winrestview(l:view)
    redraw
    call wplus#util#info_msg('format', 'formatted (' . a:bin . ')')
    return 1
endfunction

function! s:try_ale() abort
    if exists(':ALEFix') != 2
        return 0
    endif
    ALEFix
    call wplus#util#info_msg('format', 'formatted (ALE)')
    return 1
endfunction

function! s:vim_indent() abort
    let l:view = winsaveview()
    silent normal! gg=G
    call winrestview(l:view)
    redraw!
    call wplus#util#info_msg('format', 'formatted (vim indent)')
endfunction
