" wplus/format.vim — Smart formatter (Alt+Shift+F)
" Priority: coc/LSP → external tool → ALE → vim indent

" ── external formatter map ────────────────────────────────────────────────
" Values:
"   cmd      : shell command (reads stdin, writes stdout)
"   filepath : if 1, append shellescape(expand('%')) to cmd (for prettier etc.)
"   check    : binary name to check with executable() [defaults to first word of cmd]
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
    \ }

" ── public API ───────────────────────────────────────────────────────────

function! wplus#format#run() abort
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
    if !s:coc_ready()
        return 0
    endif
    call CocAction('format')
    echo '[wplus] formatted (coc/LSP)'
    return 1
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
    let l:bin = split(l:cmd)[0]
    if !executable(l:bin)
        " Try gofmt as fallback for Go
        if l:ft ==# 'go' && executable('gofmt')
            let l:cmd = 'gofmt'
            let l:bin = 'gofmt'
        else
            return 0
        endif
    endif

    return s:run_stdin_fmt(l:cmd, l:bin)
endfunction

function! s:run_stdin_fmt(cmd, bin) abort
    let l:view = winsaveview()
    let l:orig = getline(1, '$')

    silent execute '%!' . a:cmd

    if v:shell_error != 0
        " Restore original content
        silent undo
        echohl WarningMsg
        echomsg '[wplus] formatter failed: ' . a:bin . ' (exit ' . v:shell_error . ')'
        echohl None
        call winrestview(l:view)
        return 0
    endif

    " Guard against empty output (some tools output nothing on failure)
    if getline(1, '$') == ['']
        silent undo
        echohl WarningMsg
        echomsg '[wplus] formatter returned empty output: ' . a:bin
        echohl None
        call winrestview(l:view)
        return 0
    endif

    call winrestview(l:view)
    redraw!
    echo '[wplus] formatted (' . a:bin . ')'
    return 1
endfunction

function! s:try_ale() abort
    if exists(':ALEFix') != 2
        return 0
    endif
    ALEFix
    echo '[wplus] formatted (ALE)'
    return 1
endfunction

function! s:vim_indent() abort
    let l:view = winsaveview()
    silent normal! gg=G
    call winrestview(l:view)
    redraw!
    echo '[wplus] formatted (vim indent)'
endfunction
