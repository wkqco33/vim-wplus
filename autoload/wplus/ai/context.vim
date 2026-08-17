" wplus/ai/context.vim — Context extraction for AI suggestions

if exists('g:autoloaded_wplus_ai_context') | finish | endif
let g:autoloaded_wplus_ai_context = 1

" ── Context cache ─────────────────────────────────────────────────────────────
" symbols/scope extraction scans ~200 lines per call. Cache by buffer with a
" short TTL so rapid TextChangedI timer callbacks reuse the same snapshot.
let s:cache = {}  " bufnr -> {'symbols': [...], 'scope': str, 'ft': str, 'ts': localtime()}
let s:cache_ttl = 5  " seconds

" Invalidate cache for a buffer (or all when bufnr <= 0).
function! wplus#ai#context#invalidate(...) abort
    if a:0 >= 1 && a:1 > 0
        if has_key(s:cache, a:1)
            call remove(s:cache, a:1)
        endif
        return
    endif
    let s:cache = {}
endfunction

function! s:cache_fresh(bufnr, ft) abort
    if !has_key(s:cache, a:bufnr) | return 0 | endif
    let l:entry = s:cache[a:bufnr]
    if l:entry.ft !=# a:ft | return 0 | endif
    return (localtime() - l:entry.ts) < s:cache_ttl
endfunction

function! s:cache_store(bufnr, ft, symbols, scope) abort
    let s:cache[a:bufnr] = {
        \ 'symbols': a:symbols,
        \ 'scope': a:scope,
        \ 'ft': a:ft,
        \ 'ts': localtime(),
        \ }
endfunction

" ── Helper patterns for language-specific symbol extraction ──────────────────

function! s:match_any(text, patterns) abort
    for l:pattern in a:patterns
        let l:match = matchstr(a:text, l:pattern)
        if !empty(l:match)
            return l:match
        endif
    endfor
    return ''
endfunction

" ── Public functions ──────────────────────────────────────────────────────────

function! s:collect_workspace_symbols(ft) abort
    let l:symbols = []
    for l:info in getbufinfo({'buflisted': 1})
        if l:info.bufnr == bufnr('%') || !bufloaded(l:info.bufnr) | continue | endif
        if getbufvar(l:info.bufnr, '&filetype') !=# a:ft | continue | endif
        let l:sample = getbufline(l:info.bufnr, 1, 50)
        for l:line in l:sample
            let l:m = matchstr(l:line, '\v^\s*%(class|struct|def|func|function|fn|enum|interface)\s+\zs\w+')
            if !empty(l:m)
                call add(l:symbols, l:m)
            endif
        endfor
    endfor
    try
        let l:tags = taglist('.*')
        for l:t in l:tags[:29]
            if has_key(l:t, 'name') && l:t.name =~# '^\w\+$'
                call add(l:symbols, l:t.name)
            endif
        endfor
    catch
    endtry
    return l:symbols
endfunction

" Extract symbols from current buffer context
function! wplus#ai#context#extract_symbols() abort
    let l:buf = bufnr('%')
    let l:ft = &filetype
    if s:cache_fresh(l:buf, l:ft)
        return s:cache[l:buf].symbols
    endif
    let l:symbols = []
    let l:lines = getline(max([1, line('.') - 100]), min([line('$'), line('.') + 100]))
    call extend(l:symbols, s:collect_workspace_symbols(l:ft))
    let l:ft = &filetype
    
    for l:line in l:lines
        let l:name = ''
        
        if l:ft == 'go'
            let l:name = matchstr(l:line, '\v^\s*func\s+%(\([^)]*\)\s+)?\zs\w+')
        elseif l:ft == 'python'
            let l:name = matchstr(l:line, '\v^\s*%(def|class)\s+\zs\w+')
        elseif l:ft =~# '\v^(c|cpp)$'
            " C/C++: Capture function/class definitions while excluding control
            " statements (if/for/switch/while/return) and regular function calls.
            let l:name = s:match_any(l:line, [
                \ '\v^\s*%(class|struct|enum\s+class|enum)\s+\zs\w+',
                \ '\v^\s*%(namespace)\s+\zs\w+',
                \ '\v^\s*%(\w+%(::\w+)*\s+)+\zs\w+\ze\s*\%(\n|\([^)]*\)\s*\%(\{\|;\|const\|noexcept\|\)\s*$)',
                \ ])
        elseif l:ft =~# '\v^(typescript|javascript)$'
            let l:name = s:match_any(l:line, [
                \ '\v^\s*%(export\s+)?%(async\s+)?function\s+\zs\w+',
                \ '\v^\s*%(export\s+)?%(const|let|var)\s+\zs\w+\ze\s*\=',
                \ '\v^\s*class\s+\zs\w+',
                \ ])
        elseif l:ft == 'rust'
            let l:name = matchstr(l:line, '\v^\s*%(pub\s+)?%(async\s+)?%(fn|struct|enum|trait|impl)\s+\zs\w+')
        elseif l:ft == 'java'
            let l:name = s:match_any(l:line, [
                \ '\v^\s*%(public|private|protected)?\s*%(static\s+)?%(class|interface|enum)\s+\zs\w+',
                \ '\v^\s*%(public|private|protected)?\s*%(static\s+)?\w+%(<[^>]+>)?\s+\zs\w+\ze\s*\(',
                \ ])
        elseif l:ft == 'kotlin'
            let l:name = s:match_any(l:line, [
                \ '\v^\s*%(class|object|interface|enum\s+class)\s+\zs\w+',
                \ '\v^\s*%(public|private|protected|internal)?\s*%(suspend\s+)?fun\s+\zs\w+\ze\s*\(',
                \ ])
        elseif l:ft == 'ruby'
            let l:name = matchstr(l:line, '\v^\s*%(def|class|module)\s+\zs\w+')
        elseif l:ft == 'lua'
            let l:name = matchstr(l:line, '\v^\s*%(local\s+)?function\s+\zs\w+')
        endif
        
        if !empty(l:name)
            call add(l:symbols, l:name)
        endif
    endfor
    
    " Filter out keywords and duplicates, preserve order
    let l:keywords = {'if': 1, 'for': 1, 'switch': 1, 'while': 1, 'do': 1,
          \ 'else': 1, 'return': 1, 'case': 1, 'goto': 1, 'break': 1,
          \ 'continue': 1, 'throw': 1, 'sizeof': 1, 'typeof': 1, 'alignof': 1,
          \ 'static_cast': 1, 'dynamic_cast': 1, 'reinterpret_cast': 1,
          \ 'const_cast': 1, 'new': 1, 'delete': 1,
          \ 'func': 1, 'def': 1,
          \ 'class': 1, 'fn': 1, 'const': 1, 'let': 1, 'var': 1,
          \ 'function': 1, 'struct': 1, 'impl': 1, 'trait': 1, 'enum': 1,
          \ 'module': 1, 'pub': 1, 'fun': 1, 'object': 1, 'interface': 1,
          \ 'namespace': 1, 'typename': 1, 'template': 1, 'using': 1,
          \ 'operator': 1, 'virtual': 1, 'override': 1, 'final': 1,
          \ 'explicit': 1, 'inline': 1, 'constexpr': 1, 'static': 1,
          \ 'extern': 1, 'friend': 1, 'typedef': 1, 'auto': 1}
    let l:seen = {}
    let l:ordered = []
    for l:symbol in l:symbols
        if has_key(l:keywords, l:symbol) || has_key(l:seen, l:symbol)
            continue
        endif
        let l:seen[l:symbol] = 1
        call add(l:ordered, l:symbol)
    endfor

    " Pre-compute scope too so get_scope() can hit the same cache entry.
    let l:scope = s:compute_scope()
    call s:cache_store(l:buf, l:ft, l:ordered, l:scope)
    return l:ordered
endfunction

" Get current scope (function/class/etc.)
function! wplus#ai#context#get_scope() abort
    let l:buf = bufnr('%')
    let l:ft = &filetype
    if s:cache_fresh(l:buf, l:ft) && has_key(s:cache[l:buf], 'scope')
        return s:cache[l:buf].scope
    endif
    let l:scope = s:compute_scope()
    " Merge into cache (preserve symbols if already cached, else leave empty).
    let l:symbols = has_key(s:cache, l:buf) ? s:cache[l:buf].symbols : []
    call s:cache_store(l:buf, l:ft, l:symbols, l:scope)
    return l:scope
endfunction

" Internal scope computation (originally inline in get_scope).
function! s:compute_scope() abort
    let l:ft = &filetype
    let l:line_nr = line('.')
    let l:scan_start = max([1, l:line_nr - 200])
    let l:scope = ''
    
    for l:i in reverse(range(l:scan_start, l:line_nr))
        let l:line_text = getline(l:i)
        
        if l:ft == 'go'
            let l:name = matchstr(l:line_text, '\v^\s*func\s+%(\([^)]*\)\s+)?\zs\w+')
            if !empty(l:name)
                let l:scope = 'func ' . l:name
                break
            endif
        elseif l:ft == 'python'
            let l:kind = matchstr(l:line_text, '\v^\s*\zs%(def|class)\ze\s+')
            let l:name = matchstr(l:line_text, '\v^\s*%(def|class)\s+\zs\w+')
            if !empty(l:kind) && !empty(l:name)
                let l:scope = l:kind . ' ' . l:name
                break
            endif
        elseif l:ft =~# '\v^(typescript|javascript)$'
            let l:name = matchstr(l:line_text, '\v^\s*%(export\s+)?%(async\s+)?function\s+\zs\w+')
            if !empty(l:name)
                let l:scope = 'function ' . l:name
                break
            endif
            let l:name = matchstr(l:line_text, '\v^\s*class\s+\zs\w+')
            if !empty(l:name)
                let l:scope = 'class ' . l:name
                break
            endif
            let l:kind = matchstr(l:line_text, '\v^\s*%(export\s+)?\zs%(const|let|var)\ze\s+')
            let l:name = matchstr(l:line_text, '\v^\s*%(export\s+)?%(const|let|var)\s+\zs\w+\ze\s*\=')
            if !empty(l:kind) && !empty(l:name)
                let l:scope = l:kind . ' ' . l:name
                break
            endif
        elseif l:ft == 'rust'
            let l:kind = matchstr(l:line_text, '\v^\s*%(pub\s+)?%(async\s+)?\zs%(fn|struct|enum|trait|impl)\ze\s+')
            let l:name = matchstr(l:line_text, '\v^\s*%(pub\s+)?%(async\s+)?%(fn|struct|enum|trait|impl)\s+\zs\w+')
            if !empty(l:kind) && !empty(l:name)
                let l:scope = l:kind . ' ' . l:name
                break
            endif
        elseif l:ft == 'java'
            let l:kind = matchstr(l:line_text, '\v^\s*%(public|private|protected)?\s*%(static\s+)?\zs%(class|interface|enum)\ze\s+')
            let l:name = matchstr(l:line_text, '\v^\s*%(public|private|protected)?\s*%(static\s+)?%(class|interface|enum)\s+\zs\w+')
            if !empty(l:kind) && !empty(l:name)
                let l:scope = l:kind . ' ' . l:name
                break
            endif
            let l:name = matchstr(l:line_text, '\v^\s*%(public|private|protected)?\s*%(static\s+)?\w+%(<[^>]+>)?\s+\zs\w+\ze\s*\(')
            if !empty(l:name)
                let l:scope = l:name
                break
            endif
        elseif l:ft == 'kotlin'
            let l:kind = matchstr(l:line_text, '\v^\s*\zs%(class|object|interface|enum\s+class)\ze\s+')
            let l:name = matchstr(l:line_text, '\v^\s*%(class|object|interface|enum\s+class)\s+\zs\w+')
            if !empty(l:kind) && !empty(l:name)
                let l:scope = l:kind . ' ' . l:name
                break
            endif
            let l:name = matchstr(l:line_text, '\v^\s*%(public|private|protected|internal)?\s*%(suspend\s+)?fun\s+\zs\w+\ze\s*\(')
            if !empty(l:name)
                let l:scope = 'fun ' . l:name
                break
            endif
        elseif l:ft =~# '\v^(c|cpp)$'
            let l:name = s:match_any(l:line_text, [
                \ '\v^\s*%(class|struct|enum\s+class|enum|namespace)\s+\zs\w+',
                \ '\v^\s*%(\w+%(::\w+)*\s+)+\zs\w+\ze\s*\([^)]*\)\s*\%(\{\|;\|const\|noexcept\|\)\s*$',
                \ ])
            if !empty(l:name)
                let l:scope = l:name
                break
            endif
        elseif l:ft == 'ruby'
            let l:kind = matchstr(l:line_text, '\v^\s*\zs%(def|class|module)\ze\s+')
            let l:name = matchstr(l:line_text, '\v^\s*%(def|class|module)\s+\zs\w+')
            if !empty(l:kind) && !empty(l:name)
                let l:scope = l:kind . ' ' . l:name
                break
            endif
        elseif l:ft == 'lua'
            let l:name = matchstr(l:line_text, '\v^\s*%(local\s+)?function\s+\zs\w+')
            if !empty(l:name)
                let l:scope = 'function ' . l:name
                break
            endif
        endif
    endfor
    
    return l:scope
endfunction

" Get prefix (code before cursor up to boundary)
function! wplus#ai#context#get_prefix(line_nr, col, ...) abort
    let l:min_lines = 20
    let l:max_lines = a:0 >= 1 ? max([1, a:1]) : 80
    let l:ft = &filetype
    
    let l:boundary_patterns = {
          \ 'go':         '\v^\s*func\s',
          \ 'python':     '\v^%(def|class)\s',
          \ 'typescript': '\v^%(export\s+)?%(async\s+)?%(function|class)\s',
          \ 'javascript': '\v^%(export\s+)?%(async\s+)?%(function|class)\s',
          \ 'rust':       '\v^%(pub\s+)?%(fn|struct|impl|trait|enum)\s',
          \ 'java':       '\v^\s*%(public|private|protected|class|interface)\s',
          \ 'kotlin':     '\v^%(fun|class|object|interface)\s',
          \ 'ruby':       '\v^%(def|class|module)\s',
          \ 'lua':        '\v^%(function|local\s+function)\s',
          \ 'c':          '\v^\s*%(class|struct|enum|namespace)\s|\v^\s*%(\w+%(::\w+)*\s+)+\w+\s*\(',
          \ 'cpp':        '\v^\s*%(class|struct|enum\s+class|enum|namespace)\s|\v^\s*%(\w+%(::\w+)*\s+)+\w+\s*\(',
          \ }
    let l:pattern = get(l:boundary_patterns, l:ft, '')
    
    let l:hard_start = max([1, a:line_nr - l:max_lines])
    let l:soft_start = max([1, a:line_nr - l:min_lines])
    let l:boundary_line = l:hard_start
    
    if !empty(l:pattern)
        for l:i in range(l:soft_start, l:hard_start, -1)
            if getline(l:i) =~# l:pattern
                let l:boundary_line = l:i
                break
            endif
        endfor
    endif
    
    let l:before_lines = getline(l:boundary_line, a:line_nr - 1)
    let l:current_line_before = a:col > 1 ? strpart(getline(a:line_nr), 0, a:col - 1, 1) : ''
    return join(l:before_lines + [l:current_line_before], "\n")
endfunction

" Get suffix (code after cursor)
function! wplus#ai#context#get_suffix(line_nr, col, ...) abort
    let l:max_lines = a:0 >= 1 ? max([0, a:1]) : 30
    let l:last_line = line('$')
    let l:end_line = min([l:last_line, a:line_nr + l:max_lines])
    let l:cur_line = getline(a:line_nr)
    let l:current_line_after = strpart(l:cur_line, a:col - 1, strlen(l:cur_line) - (a:col - 1), 1)
    let l:after_lines = getline(a:line_nr + 1, l:end_line)
    return join([l:current_line_after] + l:after_lines, "\n")
endfunction

" Check if cursor is inside comment
function! wplus#ai#context#is_in_comment() abort
    try
        let l:syn = synIDattr(synID(line('.'), col('.'), 1), 'name')
        return l:syn =~? 'comment' ? v:true : v:false
    catch
        return v:false
    endtry
endfunction
