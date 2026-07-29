" wplus/harpoon.vim — Quick file bookmarks with indexed jump
" Up to g:wplus_harpoon_max_slots numbered slots, persisted per project root.

if exists('g:autoloaded_wplus_harpoon') | finish | endif
let g:autoloaded_wplus_harpoon = 1

let g:wplus_harpoon_max_slots = get(g:, 'wplus_harpoon_max_slots', 4)

" s:slots: list of absolute file paths ('' = empty slot)
let s:slots = []
let s:loaded_root = ''

" ── persistence ───────────────────────────────────────────────────────────

function! s:harpoon_file() abort
    let l:root = wplus#root#find_root()
    if empty(l:root) | let l:root = getcwd() | endif
    let l:safe = substitute(l:root, '[/\\:*?"<>|]', '_', 'g')
    let l:dir = expand('~/.vim/harpoon')
    if !isdirectory(l:dir) | call mkdir(l:dir, 'p') | endif
    return l:dir . '/' . l:safe . '.json'
endfunction

function! s:load_slots() abort
    let l:root = wplus#root#find_root()
    if empty(l:root) | let l:root = getcwd() | endif
    if l:root ==# s:loaded_root | return | endif
    let s:loaded_root = l:root
    let l:file = s:harpoon_file()
    if filereadable(l:file)
        try
            let l:data = json_decode(join(readfile(l:file), ''))
            let s:slots = type(l:data) == v:t_list ? l:data : []
        catch
            let s:slots = []
        endtry
    else
        let s:slots = []
    endif
    " Ensure list has exactly max_slots entries
    while len(s:slots) < g:wplus_harpoon_max_slots
        call add(s:slots, '')
    endwhile
    let s:slots = s:slots[: g:wplus_harpoon_max_slots - 1]
endfunction

function! s:save_slots() abort
    call writefile([json_encode(s:slots)], s:harpoon_file())
endfunction

" ── public API ────────────────────────────────────────────────────────────

" Add current file to the next empty slot (or replace last if all full).
function! wplus#harpoon#add() abort
    call s:load_slots()
    let l:file = expand('%:p')
    if empty(l:file) || &buftype !=# ''
        call wplus#util#warn_msg('harpoon', 'no file in current buffer')
        return
    endif
    " Already in a slot → report and return
    let l:idx = index(s:slots, l:file)
    if l:idx >= 0
        call wplus#util#info_msg('harpoon', 'already in slot ' . (l:idx + 1))
        return
    endif
    " Find first empty slot
    let l:empty = index(s:slots, '')
    if l:empty >= 0
        let s:slots[l:empty] = l:file
        call s:save_slots()
        call wplus#util#info_msg('harpoon', 'added to slot ' . (l:empty + 1) . ': ' . fnamemodify(l:file, ':~:.'))
    else
        call wplus#util#warn_msg('harpoon', 'all slots full — use :WharoonRemove or <leader>hd')
    endif
endfunction

" Jump to slot number (1-based).
function! wplus#harpoon#jump(n) abort
    call s:load_slots()
    let l:idx = a:n - 1
    if l:idx < 0 || l:idx >= len(s:slots)
        call wplus#util#warn_msg('harpoon', 'invalid slot ' . a:n)
        return
    endif
    let l:file = s:slots[l:idx]
    if empty(l:file)
        call wplus#util#warn_msg('harpoon', 'slot ' . a:n . ' is empty')
        return
    endif
    if !filereadable(l:file)
        call wplus#util#warn_msg('harpoon', 'file no longer exists: ' . fnamemodify(l:file, ':~:.'))
        return
    endif
    execute 'edit ' . fnameescape(l:file)
endfunction

" Remove current file from its slot.
function! wplus#harpoon#remove() abort
    call s:load_slots()
    let l:file = expand('%:p')
    let l:idx = index(s:slots, l:file)
    if l:idx < 0
        call wplus#util#warn_msg('harpoon', 'current file is not in any slot')
        return
    endif
    let s:slots[l:idx] = ''
    call s:save_slots()
    call wplus#util#info_msg('harpoon', 'removed from slot ' . (l:idx + 1))
endfunction

" Show all slots in a finder-style popup.
function! wplus#harpoon#list() abort
    call s:load_slots()
    let l:items = []
    for l:i in range(len(s:slots))
        let l:f = s:slots[l:i]
        let l:label = (l:i + 1) . '  ' . (empty(l:f) ? '(empty)' : fnamemodify(l:f, ':~:.'))
        call add(l:items, l:label)
    endfor
    call wplus#finder#open(l:items, function('s:jump_from_list'), 'Harpoon Slots')
endfunction

function! s:jump_from_list(item) abort
    let l:m = matchlist(a:item, '^\(\d\+\)')
    if !empty(l:m)
        call wplus#harpoon#jump(str2nr(l:m[1]))
    endif
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#harpoon#setup() abort
    command! WharoonAdd    call wplus#harpoon#add()
    command! WharoonRemove call wplus#harpoon#remove()
    command! WharoonList   call wplus#harpoon#list()

    nnoremap <silent> <leader>ha :WharoonAdd<CR>
    nnoremap <silent> <leader>hd :WharoonRemove<CR>
    nnoremap <silent> <leader>hl :WharoonList<CR>

    for s:i in range(1, g:wplus_harpoon_max_slots)
        execute 'nnoremap <silent> <leader>h' . s:i
                    \ . ' :call wplus#harpoon#jump(' . s:i . ')<CR>'
    endfor
    unlet s:i

    " Invalidate slot cache on directory change so multi-project sessions work
    augroup WplusHarpoon
        autocmd!
        autocmd DirChanged * let s:loaded_root = ''
    augroup END
endfunction
