" wplus/finder.vim — Minimal fuzzy finder using Vim 9 popup and matchfuzzy()

if exists('g:autoloaded_wplus_finder') | finish | endif
let g:autoloaded_wplus_finder = 1

let s:prompt = '> '
let s:state = {
    \ 'winid': -1,
    \ 'bufnr': -1,
    \ 'items': [],
    \ 'filtered': [],
    \ 'query': '',
    \ 'callback': '',
    \ 'selected': 0
    \ }

function! wplus#finder#open(items, callback, title) abort
    let s:state.items = a:items
    let s:state.filtered = copy(a:items)
    let s:state.query = ''
    let s:state.callback = a:callback
    let s:state.selected = 0

    let l:width = float2nr(&columns * 0.7)
    let l:height = float2nr(&lines * 0.4)
    
    let s:state.winid = popup_create([], {
        \ 'title': ' ' . a:title . ' ',
        \ 'line': (&lines - l:height) / 2,
        \ 'col': (&columns - l:width) / 2,
        \ 'minwidth': l:width,
        \ 'maxwidth': l:width,
        \ 'minheight': l:height,
        \ 'maxheight': l:height,
        \ 'border': [1,1,1,1],
        \ 'padding': [0,1,0,1],
        \ 'filter': 'wplus#finder#filter',
        \ 'mapping': 0,
        \ 'cursorline': 1,
        \ })
    let s:state.bufnr = winbufnr(s:state.winid)
    call s:update_display()
endfunction

function! wplus#finder#filter(winid, key) abort
    if a:key == "\<Esc>" || a:key == "\<C-c>"
        call popup_close(a:winid)
        return 1
    elseif a:key == "\<CR>"
        let l:res = get(s:state.filtered, s:state.selected, '')
        call popup_close(a:winid)
        if !empty(l:res)
            execute s:state.callback . ' ' . fnameescape(l:res)
        endif
        return 1
    elseif a:key == "\<C-n>" || a:key == "\<Down>"
        let s:state.selected = min([s:state.selected + 1, len(s:state.filtered) - 1])
    elseif a:key == "\<C-p>" || a:key == "\<Up>"
        let s:state.selected = max([s:state.selected - 1, 0])
    elseif a:key == "\<BS>" || a:key == "\<C-h>"
        let s:state.query = s:state.query[:-2]
        call s:filter_items()
    elseif a:key =~ '^\p$'
        let s:state.query .= a:key
        call s:filter_items()
    endif

    call s:update_display()
    return 1
endfunction

function! s:filter_items() abort
    if empty(s:state.query)
        let s:state.filtered = copy(s:state.items)
    else
        let s:state.filtered = matchfuzzy(s:state.items, s:state.query)
    endif
    let s:state.selected = 0
endfunction

function! s:update_display() abort
    let l:display = [s:prompt . s:state.query, repeat('─', &columns)]
    let l:display += s:state.filtered
    call popup_settext(s:state.winid, l:display)
    " Highlight input line and selection
    call win_execute(s:state.winid, 'syntax clear')
    call win_execute(s:state.winid, 'syntax match Title /^' . s:prompt . '.*/')
    call win_execute(s:state.winid, 'call clearmatches()')
    " Popup cursorline handles the selection highlight, but we need to account for prompt lines
    call win_execute(s:state.winid, 'call setwinvar(' . s:state.winid . ', "&cursorline", 1)')
    " Move 'cursor' to selected line (3 is start of items)
    call win_execute(s:state.winid, 'execute ' . (s:state.selected + 3))
    redraw
endfunction

" ── Sources ────────────────────────────────────────────────────────────────

function! wplus#finder#files() abort
    let l:cmd = executable('rg') ? 'rg --files' : (executable('git') ? 'git ls-files' : 'find . -type f')
    let l:items = systemlist(l:cmd)
    call wplus#finder#open(l:items, 'edit', 'Find Files')
endfunction

function! wplus#finder#buffers() abort
    let l:bufs = filter(getbufinfo({'buflisted':1}), 'v:val.name != ""')
    let l:items = map(l:bufs, 'fnamemodify(v:val.name, ":.")')
    call wplus#finder#open(l:items, 'buffer', 'Find Buffers')
endfunction

function! wplus#finder#mru() abort
    let l:items = filter(copy(v:oldfiles), 'filereadable(v:val) && v:val !~# "lsp.log$"')
    let l:items = map(l:items, 'fnamemodify(v:val, ":.")')
    call wplus#finder#open(l:items, 'edit', 'Recent Files')
endfunction

function! wplus#finder#setup() abort
    command! WfindFiles   call wplus#finder#files()
    command! WfindBuffers call wplus#finder#buffers()
    command! WfindMRU     call wplus#finder#mru()

    nnoremap <silent> <leader>p :WfindFiles<CR>
    nnoremap <silent> <leader>b :WfindBuffers<CR>
    nnoremap <silent> <leader>m :WfindMRU<CR>
endfunction
