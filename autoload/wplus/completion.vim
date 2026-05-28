" wplus/completion.vim — Lightweight buffer-word + path completion
" Triggers on <C-Space> in insert mode.
" Falls back gracefully when LSP completion is available.

if exists('g:autoloaded_wplus_completion') | finish | endif
let g:autoloaded_wplus_completion = 1

let g:wplus_completion_max_items = get(g:, 'wplus_completion_max_items', 200)

" ── word helpers ──────────────────────────────────────────────────────────

function! s:get_prefix() abort
    if col('.') <= 1 | return '' | endif
    let l:line = getline('.')[:col('.') - 2]
    let l:m = matchstr(l:line, '\k\+$')
    return l:m
endfunction

function! s:collect_words(prefix) abort
    let l:pat    = '\<' . escape(a:prefix, '\/.*$^~[]') . '\k\+'
    let l:seen   = {a:prefix: 1}
    let l:words  = []
    for l:bufnr in range(1, bufnr('$'))
        if !buflisted(l:bufnr) | continue | endif
        for l:line in getbufline(l:bufnr, 1, '$')
            let l:idx = 0
            while 1
                let l:m = matchstrpos(l:line, l:pat, l:idx)
                if l:m[1] == -1 | break | endif
                if !has_key(l:seen, l:m[0])
                    let l:seen[l:m[0]] = 1
                    call add(l:words, {'word': l:m[0], 'menu': '[buf]'})
                endif
                let l:idx = l:m[2]
            endwhile
        endfor
    endfor
    return l:words[:g:wplus_completion_max_items - 1]
endfunction

" ── path helpers ──────────────────────────────────────────────────────────

function! s:collect_paths(prefix) abort
    let l:dir   = fnamemodify(a:prefix, ':h')
    let l:base  = fnamemodify(a:prefix, ':t')
    let l:dir   = empty(l:dir) || l:dir ==# '.' ? '.' : l:dir
    try
        let l:entries = readdir(l:dir, {n -> n =~# '^' . escape(l:base, '\/.*$^~[]')})
    catch
        return []
    endtry
    return map(l:entries, '{
        \ "word": (l:dir ==# "." ? "" : l:dir . "/") . v:val,
        \ "menu": isdirectory(l:dir . "/" . v:val) ? "[dir]" : "[file]"
        \ }')
endfunction

" ── trigger ───────────────────────────────────────────────────────────────

function! wplus#completion#trigger() abort
    " If popup menu already visible (LSP/etc), cycle through it
    if pumvisible() | return "\<C-n>" | endif

    let l:ft = &filetype
    if get(g:, 'wplus_lsp_enabled', 1) && exists('*wplus#lsp#is_ready') && wplus#lsp#is_ready(l:ft)
        call wplus#lsp#request('textDocument/completion')
        return ''
    endif

    let l:prefix = s:get_prefix()
    if empty(l:prefix) | return '' | endif

    if l:prefix =~# '^[/.]'
        let l:matches = s:collect_paths(l:prefix)
    else
        let l:matches = s:collect_words(l:prefix)
    endif

    if empty(l:matches) | return '' | endif

    call complete(col('.') - len(l:prefix), l:matches)
    return ''
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#completion#setup() abort
    inoremap <silent><expr> <C-Space> wplus#completion#trigger()
endfunction
