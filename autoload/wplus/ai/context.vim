" wplus/ai/context.vim — Context extraction for AI suggestions

if exists('g:autoloaded_wplus_ai_context') | finish | endif
let g:autoloaded_wplus_ai_context = 1

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

" Extract symbols from current buffer context
function! wplus#ai#context#extract_symbols() abort
    let l:symbols = []
    let l:lines = getline(max([1, line('.') - 100]), min([line('$'), line('.') + 100]))
    let l:ft = &filetype
    
    for l:line in l:lines
        let l:name = ''
        
        if l:ft == 'go'
            let l:name = matchstr(l:line, '\v^\s*func\s+%(\([^)]*\)\s+)?\zs\w+')
        elseif l:ft == 'python'
            let l:name = matchstr(l:line, '\v^\s*%(def|class)\s+\zs\w+')
        elseif l:ft =~# '\v^(c|cpp)$'
            let l:name = matchstr(l:line, '\v^\s*\w+(\s+\w+)*\s+\zs\w+\ze\s*\(')
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
    let l:keywords = {'if': 1, 'for': 1, 'switch': 1, 'func': 1, 'def': 1,
          \ 'class': 1, 'fn': 1, 'const': 1, 'let': 1, 'var': 1,
          \ 'function': 1, 'struct': 1, 'impl': 1, 'trait': 1, 'enum': 1,
          \ 'module': 1, 'pub': 1, 'fun': 1, 'object': 1, 'interface': 1}
    let l:seen = {}
    let l:ordered = []
    for l:symbol in l:symbols
        if has_key(l:keywords, l:symbol) || has_key(l:seen, l:symbol)
            continue
        endif
        let l:seen[l:symbol] = 1
        call add(l:ordered, l:symbol)
    endfor
    
    return l:ordered
endfunction

" Get current scope (function/class/etc.)
function! wplus#ai#context#get_scope() abort
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
            let l:name = matchstr(l:line_text, '\v^\s*\w+(\s+\w+)*\s+\zs\w+\ze\s*\(')
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
function! wplus#ai#context#get_prefix(line_nr, col) abort
    let l:min_lines = 20
    let l:max_lines = 80
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
    let l:current_line_before = getline(a:line_nr)[:a:col - 2]
    return join(l:before_lines + [l:current_line_before], "\n")
endfunction

" Get suffix (code after cursor)
function! wplus#ai#context#get_suffix(line_nr, col) abort
    let l:max_lines = 30
    let l:last_line = line('$')
    let l:end_line = min([l:last_line, a:line_nr + l:max_lines])
    let l:current_line_after = getline(a:line_nr)[a:col - 1:]
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
