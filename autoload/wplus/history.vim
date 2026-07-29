" wplus/history.vim — Enhanced recent-files browser (oldfiles + MRU)
" Shows :oldfiles in a finder-style popup, optionally filtered to the
" current project root.  Combines Vim's built-in v:oldfiles with a
" per-session MRU list so freshly-opened files appear even before they
" land in ~/.viminfo.

if exists('g:autoloaded_wplus_history') | finish | endif
let g:autoloaded_wplus_history = 1

let g:wplus_history_max       = get(g:, 'wplus_history_max', 50)
let g:wplus_history_project_only = get(g:, 'wplus_history_project_only', 0)

" Per-session MRU list (most-recent first)
let s:mru = []

" ── MRU tracking ──────────────────────────────────────────────────────────

function! s:record(file) abort
    let l:file = a:file
    if empty(l:file) || !filereadable(l:file) | return | endif
    " Remove existing occurrence and prepend
    let l:idx = index(s:mru, l:file)
    if l:idx >= 0 | call remove(s:mru, l:idx) | endif
    call insert(s:mru, l:file, 0)
    if len(s:mru) > g:wplus_history_max
        let s:mru = s:mru[: g:wplus_history_max - 1]
    endif
endfunction

" ── build merged list ─────────────────────────────────────────────────────

function! s:get_files() abort
    " Merge session MRU + v:oldfiles, deduplicate, normalize paths
    let l:seen = {}
    let l:result = []

    for l:f in s:mru + v:oldfiles
        let l:norm = simplify(expand(l:f))
        if has('win32') | let l:norm = substitute(l:norm, '\\', '/', 'g') | endif
        if has_key(l:seen, l:norm) || !filereadable(l:norm) | continue | endif
        let l:seen[l:norm] = 1
        call add(l:result, l:norm)
        if len(l:result) >= g:wplus_history_max | break | endif
    endfor

    if g:wplus_history_project_only
        let l:root = wplus#root#find_root()
        if !empty(l:root)
            let l:root_norm = substitute(simplify(l:root), '\\', '/', 'g') . '/'
            let l:result = filter(l:result, 'v:val[: len(l:root_norm) - 1] ==# l:root_norm')
        endif
    endif

    return l:result
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#history#open() abort
    let l:files = s:get_files()
    if empty(l:files)
        call wplus#util#info_msg('history', 'no recent files')
        return
    endif
    " Display relative-to-home paths for readability
    let l:display = map(copy(l:files), 'fnamemodify(v:val, ":~:.")')
    call wplus#finder#open(l:display, function('s:jump_to', [l:files]), 'Recent Files')
endfunction

function! s:jump_to(files, item) abort
    " Find the full path by matching display label
    let l:display_list = map(copy(a:files), 'fnamemodify(v:val, ":~:.")')
    let l:idx = index(l:display_list, a:item)
    let l:target = l:idx >= 0 ? a:files[l:idx] : a:item
    if filereadable(l:target)
        execute 'edit ' . fnameescape(l:target)
    else
        call wplus#util#warn_msg('history', 'file not found: ' . l:target)
    endif
endfunction

function! wplus#history#open_project() abort
    let l:save = g:wplus_history_project_only
    let g:wplus_history_project_only = 1
    call wplus#history#open()
    let g:wplus_history_project_only = l:save
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#history#setup() abort
    command! Whistory        call wplus#history#open()
    command! WhistoryProject call wplus#history#open_project()

    nnoremap <silent> <leader>fh :Whistory<CR>
    nnoremap <silent> <leader>fH :WhistoryProject<CR>

    augroup WplusHistory
        autocmd!
        autocmd BufEnter * call s:record(expand('%:p'))
    augroup END
endfunction
