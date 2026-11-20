" wplus/keys/ui.vim — Popup UI for the :WplusKeys reference
"
" Split from keys.vim so the collection logic stays pure and testable; the
" stateful shell (popup, selection, filter typing) lives here.

if exists('g:autoloaded_wplus_keys_ui') | finish | endif
let g:autoloaded_wplus_keys_ui = 1

let s:view_titles = {'keys': 'Keys', 'commands': 'Commands', 'modules': 'Modules'}

" ── popup UI ──────────────────────────────────────────────────────────────

let s:state = {
    \ 'winid': -1,
    \ 'view': 'keys',
    \ 'query': '',
    \ 'filtered': [],
    \ 'selected': 0,
    \ 'height': 20,
    \ }

function! wplus#keys#ui#open(view, query) abort
    let l:view = empty(a:view) ? 'keys' : a:view
    let l:query = a:query
    if index(wplus#keys#views(), l:view) < 0 | let l:view = 'keys' | endif
    if s:state.winid != -1 && !empty(popup_getpos(s:state.winid))
        call popup_close(s:state.winid)
    endif
    let s:state.view = l:view
    let s:state.query = l:query
    let s:state.selected = 0

    if !exists('*popup_create')
        call s:open_buffer(l:view, l:query)
        return
    endif

    let l:width = min([max([&columns - 8, 40]), 120])
    let l:height = max([min([&lines - 6, 24]), 10])
    let s:state.height = l:height
    let s:state.winid = popup_create([], {
        \ 'title': ' wplus Reference ',
        \ 'line': (&lines - l:height) / 2,
        \ 'col': (&columns - l:width) / 2,
        \ 'minwidth': l:width, 'maxwidth': l:width,
        \ 'minheight': l:height, 'maxheight': l:height,
        \ 'border': [1, 1, 1, 1],
        \ 'padding': [0, 1, 0, 1],
        \ 'filter': 'wplus#keys#ui#filter',
        \ 'mapping': 0,
        \ 'cursorline': 1,
        \ 'wrap': 0,
        \ })
    call s:refresh()
endfunction

function! wplus#keys#ui#close() abort
    if s:state.winid != -1 && !empty(popup_getpos(s:state.winid))
        call popup_close(s:state.winid)
    endif
    let s:state.winid = -1
endfunction

function! s:visible_height() abort
    " Header (1) + hint (1) + borders (2).
    return max([s:state.height - 4, 3])
endfunction

function! s:refresh() abort
    if s:state.winid == -1 || empty(popup_getpos(s:state.winid))
        return
    endif
    let s:state.filtered = wplus#keys#filter(
        \ wplus#keys#entries(s:state.view), s:state.query)
    let l:total = len(s:state.filtered)
    let l:max = s:visible_height()
    let s:state.selected = max([0, min([s:state.selected, l:total - 1])])
    let l:offset = l:total <= l:max ? 0
        \ : max([0, min([s:state.selected - l:max / 2, l:total - l:max])])
    let l:window = l:total == 0
        \ ? ['  no match for: ' . s:state.query]
        \ : map(s:state.filtered[l:offset : l:offset + l:max - 1], 'v:val.text')
    let l:shown = l:total == 0 ? 0 : l:offset + min([len(l:window), l:total])
    let l:header = printf(' %s  [%d/%d]  query: %s',
        \ s:view_titles[s:state.view], l:shown, l:total,
        \ empty(s:state.query) ? '-' : s:state.query)
    let l:hint = ' <Tab> view   <CR> open   <C-n>/<C-p> move   q close'
    call popup_settext(s:state.winid, [l:header] + l:window + [l:hint])
    call win_execute(s:state.winid, 'call cursor(' . (2 + s:state.selected - l:offset) . ', 1)')
endfunction

function! s:selected_entry() abort
    return get(s:state.filtered, s:state.selected, {})
endfunction

" <CR>: fills the command line (or opens the module help) so the request can be
" reviewed before it runs.
function! s:open_selected() abort
    let l:entry = s:selected_entry()
    let l:target = wplus#keys#target(l:entry)
    call wplus#keys#ui#close()
    if empty(l:target)
        call wplus#util#info_msg('keys', 'nothing to open for '
            \ . get(l:entry, 'lhs', get(l:entry, 'name', '?')))
        return
    endif
    if l:target.type ==# 'command'
        call feedkeys(':' . l:target.value, 'n')
        return
    endif
    try
        execute 'help' l:target.value
    catch
        call wplus#util#info_msg('keys', 'no help section for ' . l:target.value)
    endtry
endfunction

function! wplus#keys#ui#filter(winid, key) abort
    if a:key ==# "\<Esc>" || a:key ==# 'q' || a:key ==# "\<C-c>"
        call wplus#keys#ui#close()
        return 1
    elseif a:key ==# "\<CR>"
        call s:open_selected()
        return 1
    elseif a:key ==# "\<Tab>"
        let l:idx = index(wplus#keys#views(), s:state.view)
        let l:views = wplus#keys#views()
        let s:state.view = l:views[(l:idx + 1) % len(l:views)]
        let s:state.selected = 0
    elseif a:key ==# "\<C-n>" || a:key ==# "\<Down>" || a:key ==# "\<C-j>"
        let s:state.selected += 1
    elseif a:key ==# "\<C-p>" || a:key ==# "\<Up>" || a:key ==# "\<C-k>"
        let s:state.selected -= 1
    elseif a:key ==# "\<BS>" || a:key ==# "\<C-h>"
        if !empty(s:state.query)
            let s:state.query = strcharpart(s:state.query, 0, strchars(s:state.query) - 1)
            let s:state.selected = 0
        endif
    elseif strchars(a:key) == 1 && char2nr(a:key) >= 32
        let s:state.query .= a:key
        let s:state.selected = 0
    else
        return 1
    endif
    call s:refresh()
    return 1
endfunction

" ── no-popup fallback ─────────────────────────────────────────────────────

function! s:open_buffer(view, query) abort
    let l:lines = []
    for l:view in wplus#keys#views()
        call add(l:lines, repeat('─', 78))
        call add(l:lines, s:view_titles[l:view]
            \ . (l:view ==# a:view && !empty(a:query) ? ' (query: ' . a:query . ')' : ''))
        call add(l:lines, repeat('─', 78))
        call extend(l:lines, wplus#keys#render(l:view,
            \ l:view ==# a:view ? a:query : ''))
        call add(l:lines, '')
    endfor

    let l:existing = bufnr('__WplusKeys__')
    if l:existing != -1 && bufexists(l:existing)
        execute 'buffer' l:existing
    else
        enew
        silent! execute 'file __WplusKeys__'
    endif
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    setlocal modifiable
    silent %delete _
    call setline(1, l:lines)
    setlocal nomodifiable
    setlocal filetype=wpluskeys
    nnoremap <buffer> <silent> q :close<CR>
endfunction

