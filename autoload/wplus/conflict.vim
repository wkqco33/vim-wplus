" wplus/conflict.vim — Git merge conflict resolver UI

if exists('g:autoloaded_wplus_conflict') | finish | endif
let g:autoloaded_wplus_conflict = 1

" Conflict state is per-buffer, not script-global.
"
" It used to live in s:conflicts / s:current_conflict while BufEnter rescanned
" on every buffer switch. Entering another file therefore overwrote the state,
" and resolve_ours()/resolve_theirs() would deletebufline() using line indices
" that belonged to a different buffer's scan.
"
" b:wplus_conflicts       [{lnum_start, lnum_ours, lnum_theirs, lnum_end,
"                           ours_lines, theirs_lines}, ...]
" b:wplus_conflict_current index into the above

function! s:list() abort
    return get(b:, 'wplus_conflicts', [])
endfunction

function! s:current() abort
    return get(b:, 'wplus_conflict_current', 0)
endfunction

function! s:target_conflict_index() abort
    let l:list = s:list()
    if empty(l:list) | return -1 | endif
    let l:cur = line('.')
    for l:i in range(len(l:list))
        let l:conf = l:list[l:i]
        if l:cur >= l:conf.lnum_start && l:cur <= l:conf.lnum_end
            let b:wplus_conflict_current = l:i
            return l:i
        endif
    endfor
    let l:idx = s:current()
    return (l:idx >= 0 && l:idx < len(l:list)) ? l:idx : 0
endfunction

function! s:find_conflicts() abort
    let b:wplus_conflicts = []
    let b:wplus_conflict_current = get(b:, 'wplus_conflict_current', 0)
    let l:bufnr = bufnr('%')
    let l:lines = getbufline(l:bufnr, 1, '$')
    let l:idx = 0
    
    while l:idx < len(l:lines)
        let l:line = l:lines[l:idx]
        
        if l:line =~# '^<<<<<<<'
            let l:start = l:idx + 1
            let l:ours_start = l:idx + 1
            let l:ours_lines = []
            let l:base_lines = []
            let l:base_start = 0
            let l:theirs_lines = []
            let l:theirs_start = -1
            let l:sep_lnum = -1
            
            " Collect ours until ||||||| or =======
            let l:idx += 1
            while l:idx < len(l:lines) && l:lines[l:idx] !~# '^|||||||' && l:lines[l:idx] !~# '^======='
                call add(l:ours_lines, l:lines[l:idx])
                let l:idx += 1
            endwhile
            
            " Collect diff3 base if present
            if l:idx < len(l:lines) && l:lines[l:idx] =~# '^|||||||'
                let l:base_start = l:idx + 1
                let l:idx += 1
                while l:idx < len(l:lines) && l:lines[l:idx] !~# '^======='
                    call add(l:base_lines, l:lines[l:idx])
                    let l:idx += 1
                endwhile
            endif
            
            " Separator =======
            if l:idx < len(l:lines) && l:lines[l:idx] =~# '^======='
                let l:sep_lnum = l:idx + 1
                let l:idx += 1
            endif
            
            " Collect theirs
            let l:theirs_start = l:idx + 1
            while l:idx < len(l:lines) && l:lines[l:idx] !~# '^>>>>>>>'
                call add(l:theirs_lines, l:lines[l:idx])
                let l:idx += 1
            endwhile
            
            " Found end
            let l:end = l:idx + 1
            call add(b:wplus_conflicts, {
                \ 'lnum_start': l:start,
                \ 'lnum_ours': l:ours_start,
                \ 'lnum_base': l:base_start,
                \ 'lnum_sep': l:sep_lnum,
                \ 'lnum_theirs': l:theirs_start,
                \ 'lnum_end': l:end,
                \ 'ours_lines': l:ours_lines,
                \ 'base_lines': l:base_lines,
                \ 'theirs_lines': l:theirs_lines,
                \ })
            
            let l:idx += 1
        else
            let l:idx += 1
        endif
    endwhile
    
    return len(s:list())
endfunction

function! wplus#conflict#resolve_ours() abort
    if empty(s:list()) && s:find_conflicts() == 0 | return | endif
    let l:target_idx = s:target_conflict_index()
    if l:target_idx < 0 || l:target_idx >= len(s:list()) | return | endif
    
    let l:conf = s:list()[l:target_idx]
    let l:bufnr = bufnr('%')
    
    " Remove base/separator..end, then remove start marker
    let l:del_start = l:conf.lnum_base > 0 ? l:conf.lnum_base : l:conf.lnum_sep
    call deletebufline(l:bufnr, l:del_start, l:conf.lnum_end)
    call deletebufline(l:bufnr, l:conf.lnum_start, l:conf.lnum_start)
    
    " Recalculate remaining conflicts
    call s:find_conflicts()
    call s:highlight_conflicts()
endfunction

function! wplus#conflict#resolve_theirs() abort
    if empty(s:list()) && s:find_conflicts() == 0 | return | endif
    let l:target_idx = s:target_conflict_index()
    if l:target_idx < 0 || l:target_idx >= len(s:list()) | return | endif
    
    let l:conf = s:list()[l:target_idx]
    let l:bufnr = bufnr('%')
    
    " Remove start marker..separator (including ours and base), then remove shifted end marker
    call deletebufline(l:bufnr, l:conf.lnum_start, l:conf.lnum_sep)
    let l:new_end = l:conf.lnum_end - (l:conf.lnum_sep - l:conf.lnum_start + 1)
    call deletebufline(l:bufnr, l:new_end, l:new_end)
    
    " Recalculate
    call s:find_conflicts()
    call s:highlight_conflicts()
endfunction

function! wplus#conflict#resolve_both() abort
    if empty(s:list()) && s:find_conflicts() == 0 | return | endif
    let l:target_idx = s:target_conflict_index()
    if l:target_idx < 0 || l:target_idx >= len(s:list()) | return | endif
    
    let l:conf = s:list()[l:target_idx]
    let l:bufnr = bufnr('%')
    
    " Remove markers from bottom to top so line numbers stay valid.
    call deletebufline(l:bufnr, l:conf.lnum_end, l:conf.lnum_end)
    if l:conf.lnum_base > 0
        call deletebufline(l:bufnr, l:conf.lnum_base, l:conf.lnum_sep)
    else
        call deletebufline(l:bufnr, l:conf.lnum_sep, l:conf.lnum_sep)
    endif
    call deletebufline(l:bufnr, l:conf.lnum_start, l:conf.lnum_start)
    
    " Recalculate
    call s:find_conflicts()
    call s:highlight_conflicts()
endfunction

function! s:highlight_conflicts() abort
    " Clear previous highlights
    try
        call prop_remove({'type': 'WplusConflictMarker', 'all': 1})
    catch
    endtry
    
    if empty(s:list()) | return | endif
    
    for l:conf in s:list()
        " lnum_start is already the 1-based line of the <<<<<<< marker, so the
        " previous `lnum_start - 1` annotated the line above it -- and for a
        " conflict on line 1 that meant line 0, which throws and was swallowed by
        " the catch below, so the marker simply never appeared.
        try
            call prop_add(l:conf.lnum_start, 1, {
                \ 'type': 'WplusConflictMarker',
                \ 'text': '<<< OURS'
                \ })
        catch
        endtry
    endfor
endfunction

function! wplus#conflict#next() abort
    if len(s:list()) == 0
        call wplus#util#info_msg('conflict', 'no conflicts found')
        return
    endif
    
    let b:wplus_conflict_current = min([s:current() + 1, len(s:list()) - 1])
    let l:conf = s:list()[s:current()]
    call cursor(l:conf.lnum_start, 1)
    call wplus#util#info_msg('conflict', printf('conflict %d/%d', s:current() + 1, len(s:list())))
endfunction

function! wplus#conflict#prev() abort
    if len(s:list()) == 0 | return | endif
    
    let b:wplus_conflict_current = max([s:current() - 1, 0])
    let l:conf = s:list()[s:current()]
    call cursor(l:conf.lnum_start, 1)
    call wplus#util#info_msg('conflict', printf('conflict %d/%d', s:current() + 1, len(s:list())))
endfunction

function! wplus#conflict#setup() abort
    " Highlights
    highlight default WplusConflictMarker guifg=#fb4934 ctermfg=167 gui=bold
    
    if empty(prop_type_get('WplusConflictMarker'))
        call prop_type_add('WplusConflictMarker', {
            \ 'highlight': 'WplusConflictMarker',
            \ 'priority': 100
            \ })
    endif
    
    augroup WplusConflict
        autocmd!
        autocmd BufEnter * call s:find_conflicts() | call s:highlight_conflicts()
        autocmd BufWritePost * call s:find_conflicts() | call s:highlight_conflicts()
    augroup END
    
    " Commands
    command! WconflictOurs  call wplus#conflict#resolve_ours()
    command! WconflictTheirs call wplus#conflict#resolve_theirs()
    command! WconflictBoth  call wplus#conflict#resolve_both()
    command! WconflictNext  call wplus#conflict#next()
    command! WconflictPrev  call wplus#conflict#prev()
    
    " Mappings
    nnoremap <silent> <Plug>WconflictOurs   :WconflictOurs<CR>
    nnoremap <silent> <Plug>WconflictTheirs :WconflictTheirs<CR>
    nnoremap <silent> <Plug>WconflictBoth   :WconflictBoth<CR>
    nnoremap <silent> <Plug>WconflictNext   :WconflictNext<CR>
    nnoremap <silent> <Plug>WconflictPrev   :WconflictPrev<CR>

    " Default navigation keys. Only <Plug> mappings existed before, so the module
    " was unreachable out of the box and every user had to bind it by hand.
    " ]x / [x follow the ]h / ]e "next thing of this kind" convention; the
    " resolve commands stay <Plug>-only since picking a side is destructive.
    nmap <silent> ]x <Plug>WconflictNext
    nmap <silent> [x <Plug>WconflictPrev
endfunction
