" wplus/conflict.vim — Git merge conflict resolver UI

if exists('g:autoloaded_wplus_conflict') | finish | endif
let g:autoloaded_wplus_conflict = 1

let s:conflicts = [] " [{lnum_start, lnum_ours, lnum_theirs, lnum_end, ours_lines, theirs_lines}...]
let s:current_conflict = 0

function! s:find_conflicts() abort
    let s:conflicts = []
    let l:bufnr = bufnr('%')
    let l:lines = getbufline(l:bufnr, 1, '$')
    let l:idx = 0
    
    while l:idx < len(l:lines)
        let l:line = l:lines[l:idx]
        
        if l:line =~# '^<<<<<<<'
            " Found conflict start
            let l:start = l:idx + 1
            let l:ours_start = l:idx + 1
            let l:ours_lines = []
            let l:theirs_lines = []
            let l:theirs_start = -1
            
            " Collect ours
            let l:idx += 1
            while l:idx < len(l:lines) && l:lines[l:idx] !~# '^======='
                call add(l:ours_lines, l:lines[l:idx])
                let l:idx += 1
            endwhile
            
            " Skip ======= marker
            let l:sep_lnum = l:idx + 1
            let l:idx += 1
            
            " Collect theirs
            let l:theirs_start = l:idx + 1
            while l:idx < len(l:lines) && l:lines[l:idx] !~# '^>>>>>>>'
                call add(l:theirs_lines, l:lines[l:idx])
                let l:idx += 1
            endwhile
            
            " Found end
            let l:end = l:idx + 1
            call add(s:conflicts, {
                \ 'lnum_start': l:start,
                \ 'lnum_ours': l:ours_start,
                \ 'lnum_sep': l:sep_lnum,
                \ 'lnum_theirs': l:theirs_start,
                \ 'lnum_end': l:end,
                \ 'ours_lines': l:ours_lines,
                \ 'theirs_lines': l:theirs_lines,
                \ })
            
            let l:idx += 1
        else
            let l:idx += 1
        endif
    endwhile
    
    return len(s:conflicts)
endfunction

function! wplus#conflict#resolve_ours() abort
    if s:current_conflict >= len(s:conflicts) | return | endif
    
    let l:conf = s:conflicts[s:current_conflict]
    let l:bufnr = bufnr('%')
    
    " Delete conflict markers and theirs
    " Keep ours, remove markers and theirs
    call deletebufline(l:bufnr, l:conf.lnum_start, l:conf.lnum_start)
    call deletebufline(l:bufnr, l:conf.lnum_sep + 1, l:conf.lnum_end)
    
    " Recalculate remaining conflicts
    call s:find_conflicts()
    call s:highlight_conflicts()
endfunction

function! wplus#conflict#resolve_theirs() abort
    if s:current_conflict >= len(s:conflicts) | return | endif
    
    let l:conf = s:conflicts[s:current_conflict]
    let l:bufnr = bufnr('%')
    
    " Delete conflict markers and ours, keep theirs
    call deletebufline(l:bufnr, l:conf.lnum_start, l:conf.lnum_sep)
    
    " Adjust lnum_end after deletion
    let l:adjust = l:conf.lnum_sep - l:conf.lnum_start + 1
    let l:new_end = l:conf.lnum_end - l:adjust
    call deletebufline(l:bufnr, l:new_end, l:new_end)
    
    " Recalculate
    call s:find_conflicts()
    call s:highlight_conflicts()
endfunction

function! wplus#conflict#resolve_both() abort
    if s:current_conflict >= len(s:conflicts) | return | endif
    
    let l:conf = s:conflicts[s:current_conflict]
    let l:bufnr = bufnr('%')
    
    " Keep both ours and theirs, remove markers
    call deletebufline(l:bufnr, l:conf.lnum_start, l:conf.lnum_start) " <<<<<<<
    
    " Adjust sep line
    let l:new_sep = l:conf.lnum_sep - 1
    call deletebufline(l:bufnr, l:new_sep, l:new_sep) " =======
    
    " Adjust end
    let l:adjust = 2
    let l:new_end = l:conf.lnum_end - l:adjust
    call deletebufline(l:bufnr, l:new_end, l:new_end) " >>>>>>>
    
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
    
    if empty(s:conflicts) | return | endif
    
    for l:idx in range(len(s:conflicts))
        let l:conf = s:conflicts[l:idx]
        
        " Add text markers for conflict locations
        try
            call prop_add(l:conf.lnum_start - 1, 1, {
                \ 'type': 'WplusConflictMarker',
                \ 'text': '<<< OURS'
                \ })
        catch
        endtry
    endfor
endfunction

function! wplus#conflict#next() abort
    if len(s:conflicts) == 0
        call wplus#util#info_msg('conflict', 'no conflicts found')
        return
    endif
    
    let s:current_conflict = min([s:current_conflict + 1, len(s:conflicts) - 1])
    let l:conf = s:conflicts[s:current_conflict]
    call cursor(l:conf.lnum_start, 1)
    call wplus#util#info_msg('conflict', printf('conflict %d/%d', s:current_conflict + 1, len(s:conflicts)))
endfunction

function! wplus#conflict#prev() abort
    if len(s:conflicts) == 0 | return | endif
    
    let s:current_conflict = max([s:current_conflict - 1, 0])
    let l:conf = s:conflicts[s:current_conflict]
    call cursor(l:conf.lnum_start, 1)
    call wplus#util#info_msg('conflict', printf('conflict %d/%d', s:current_conflict + 1, len(s:conflicts)))
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
endfunction
