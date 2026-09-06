" wplus/fold.vim — Smart fold management
" Indent-based folds by default; uses LSP textDocument/foldingRange when the
" LSP server advertises the capability.  Fold state is saved with the session.

if exists('g:autoloaded_wplus_fold') | finish | endif
let g:autoloaded_wplus_fold = 1

let g:wplus_fold_method       = get(g:, 'wplus_fold_method', 'indent')  " 'indent' | 'lsp' | 'syntax'
let g:wplus_fold_level        = get(g:, 'wplus_fold_level', 99)         " &foldlevel on open (99 = all open)
let g:wplus_fold_min_lines    = get(g:, 'wplus_fold_min_lines', 1)
let g:wplus_fold_column       = get(g:, 'wplus_fold_column', 0)         " foldcolumn width (0=off)
let g:wplus_fold_ft_exclude   = get(g:, 'wplus_fold_ft_exclude',
    \ ['help', 'quickfix', 'qf', 'undotree', 'explorer', 'tagbar'])

" ── per-buffer state ──────────────────────────────────────────────────────

let s:lsp_folds = {}   " bufnr -> list of {start, end, kind}
let s:pending   = {}   " bufnr -> 1 (awaiting LSP response)

" ── helpers ───────────────────────────────────────────────────────────────

function! s:is_excluded() abort
    return index(g:wplus_fold_ft_exclude, &filetype) >= 0
endfunction

function! s:apply_indent() abort
    setlocal foldmethod=indent
    setlocal foldminlines=1
    execute 'setlocal foldlevel=' . g:wplus_fold_level
    if g:wplus_fold_column > 0
        execute 'setlocal foldcolumn=' . g:wplus_fold_column
    endif
endfunction

" ── LSP fold ranges ───────────────────────────────────────────────────────

" Called by lsp.vim when it receives a foldingRange response.
" lsp.vim does not implement foldingRange by default; this module registers
" a User autocommand and can also be invoked directly.
function! wplus#fold#on_lsp_ranges(bufnr, ranges) abort
    let l:bufnr = a:bufnr
    let s:lsp_folds[l:bufnr] = a:ranges
    if bufnr('%') == l:bufnr
        call s:apply_lsp(l:bufnr)
    endif
endfunction

function! s:apply_lsp(bufnr) abort
    if !has_key(s:lsp_folds, a:bufnr) || empty(s:lsp_folds[a:bufnr])
        " Fall back to indent if no LSP ranges
        call s:apply_indent()
        return
    endif
    " Use expr folding to map LSP ranges
    let b:wplus_fold_ranges = s:lsp_folds[a:bufnr]
    setlocal foldmethod=expr
    setlocal foldexpr=wplus#fold#expr(v:lnum)
    setlocal foldminlines=1
    execute 'setlocal foldlevel=' . g:wplus_fold_level
    if g:wplus_fold_column > 0
        execute 'setlocal foldcolumn=' . g:wplus_fold_column
    endif
endfunction

function! s:rebuild_fold_index() abort
    let l:ranges = get(b:, 'wplus_fold_ranges', [])
    let b:wplus_fold_ranges_cached = l:ranges
    let b:wplus_fold_index = {}
    if empty(l:ranges) | return | endif

    let l:items = []
    for l:r in l:ranges
        let l:s = get(l:r, 'startLine', get(l:r, 'start', -1))
        let l:e = get(l:r, 'endLine', get(l:r, 'end', -1))
        if l:s >= 0 && l:e >= l:s
            call add(l:items, {'start': l:s + 1, 'end': l:e + 1})
        endif
    endfor
    if empty(l:items) | return | endif

    " Sort: start ascending, end descending (outer ranges first)
    call sort(l:items, {a, b -> a.start != b.start ? a.start - b.start : b.end - a.end})

    " Calculate depth for each item
    for l:i in range(len(l:items))
        let l:item = l:items[l:i]
        let l:depth = 1
        for l:j in range(0, l:i - 1)
            let l:prev = l:items[l:j]
            if l:prev.start <= l:item.start && l:prev.end >= l:item.end && (l:prev.start != l:item.start || l:prev.end != l:item.end)
                let l:depth += 1
            endif
        endfor
        let l:item.depth = l:depth
    endfor

    " Populate index
    for l:item in l:items
        let l:cur_start = get(b:wplus_fold_index, l:item.start, '')
        if empty(l:cur_start) || str2nr(l:cur_start[1:]) < l:item.depth
            let b:wplus_fold_index[l:item.start] = '>' . l:item.depth
        endif

        let l:cur_end = get(b:wplus_fold_index, l:item.end, '')
        if empty(l:cur_end) || str2nr(l:cur_end[1:]) < l:item.depth
            let b:wplus_fold_index[l:item.end] = '<' . l:item.depth
        endif
    endfor
endfunction

" Called for every line when foldmethod=expr.
function! wplus#fold#expr(lnum) abort
    let l:ranges = get(b:, 'wplus_fold_ranges', [])
    if empty(l:ranges) | return '=' | endif
    if !exists('b:wplus_fold_index') || get(b:, 'wplus_fold_ranges_cached', []) isnot l:ranges
        call s:rebuild_fold_index()
    endif
    return get(b:wplus_fold_index, a:lnum, '=')
endfunction

" ── request LSP fold ranges ───────────────────────────────────────────────

function! s:request_lsp_ranges() abort
    " wplus#lsp#request_fold_ranges is called if the lsp module is loaded.
    " If it doesn't exist we silently fall back to indent folding.
    if exists('*wplus#lsp#request_fold_ranges')
        call wplus#lsp#request_fold_ranges(bufnr('%'))
    endif
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#fold#setup_buffer() abort
    if s:is_excluded() | return | endif
    if g:wplus_fold_method ==# 'lsp'
        call s:request_lsp_ranges()
        " Immediately use indent as placeholder while waiting for LSP
        call s:apply_indent()
    elseif g:wplus_fold_method ==# 'syntax'
        setlocal foldmethod=syntax
        execute 'setlocal foldlevel=' . g:wplus_fold_level
    else
        call s:apply_indent()
    endif
endfunction

function! wplus#fold#toggle() abort
    if foldlevel(line('.')) == 0
        call wplus#util#info_msg('fold', 'no fold at cursor')
        return
    endif
    normal! za
endfunction

function! wplus#fold#open_all() abort
    execute 'setlocal foldlevel=' . g:wplus_fold_level
    call wplus#util#info_msg('fold', 'all folds opened')
endfunction

function! wplus#fold#close_all() abort
    setlocal foldlevel=0
    call wplus#util#info_msg('fold', 'all folds closed')
endfunction

function! wplus#fold#close_others() abort
    " Close all folds except those containing the current line
    normal! zMzv
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#fold#setup() abort
    " Pretty fold text: show first line + line count
    function! WplusFoldText() abort
        let l:line   = getline(v:foldstart)
        let l:count  = v:foldend - v:foldstart + 1
        let l:indent = matchstr(l:line, '^\s*')
        let l:body   = substitute(l:line, '^\s*', '', '')
        return l:indent . '▶ ' . l:body . '  [' . l:count . ' lines]'
    endfunction
    set foldtext=WplusFoldText()
    set fillchars+=fold:\ 

    command! WfoldToggle     call wplus#fold#toggle()
    command! WfoldOpenAll    call wplus#fold#open_all()
    command! WfoldCloseAll   call wplus#fold#close_all()
    command! WfoldCloseOthers call wplus#fold#close_others()

    nnoremap <silent> <leader>zz :WfoldToggle<CR>
    nnoremap <silent> <leader>za :WfoldOpenAll<CR>
    nnoremap <silent> <leader>zc :WfoldCloseAll<CR>
    nnoremap <silent> <leader>zo :WfoldCloseOthers<CR>

    " Save fold state in sessions
    set sessionoptions+=folds

    augroup WplusFold
        autocmd!
        autocmd FileType * call wplus#fold#setup_buffer()
        autocmd User WplusLspFoldsUpdate call s:on_lsp_folds_update()
        " Reload LSP folds on file write (server may push new ranges)
        autocmd BufWritePost * if g:wplus_fold_method ==# 'lsp' | call s:request_lsp_ranges() | endif
    augroup END
endfunction

function! s:on_lsp_folds_update() abort
    if exists('b:wplus_lsp_fold_ranges')
        call wplus#fold#on_lsp_ranges(bufnr('%'), b:wplus_lsp_fold_ranges)
    endif
endfunction

