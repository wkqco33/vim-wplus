" wplus/whichkey.vim — <leader> key hint popup (replaces vim-which-key)
" After timeoutlen ms of inactivity, shows a popup with registered key hints.

if exists('g:autoloaded_wplus_whichkey') | finish | endif
let g:autoloaded_wplus_whichkey = 1

" Registry: key → description  (populated by wplus#whichkey#register or auto-built)
let s:registry = {}
let s:popup_id  = -1
let s:timer     = -1

" ── public API ────────────────────────────────────────────────────────────

" Register a key hint:
"   call wplus#whichkey#register('<leader>e', 'NERDTree toggle')
function! wplus#whichkey#register(key, desc) abort
    let s:registry[a:key] = a:desc
endfunction

" ── auto-discover from nmap ───────────────────────────────────────────────

function! s:discover_leader_maps() abort
    " Parse :nmap output to find <Space>X mappings
    let output = execute('nmap')
    for line in split(output, "\n")
        " format:  n  <Space>e    :NERDTreeToggle<CR>
        let m = matchlist(line, '^\s*n\s\+<Space>\(\S\+\)\s\+\(.*\)')
        if empty(m) | continue | endif
        let key  = '<leader>' . m[1]
        let desc = substitute(m[2], '<CR>\|<Esc>\|<C-.*>', '', 'g')
        let desc = trim(substitute(desc, '^:', '', ''))
        let desc = desc[:40]
        if !has_key(s:registry, key)
            let s:registry[key] = desc
        endif
    endfor
endfunction

" ── build popup lines ─────────────────────────────────────────────────────

function! s:build_lines(prefix) abort
    call s:discover_leader_maps()
    let lines = []
    let prefix_escaped = escape(a:prefix, '\\')
    for [key, desc] in sort(items(s:registry))
        if key =~# '^' . prefix_escaped
            " Show only the suffix after prefix
            let suffix = key[len(a:prefix):]
            if len(suffix) == 1 || (len(suffix) == 2 && suffix[0] == '<')
                call add(lines, printf('  %-8s  %s', suffix, desc))
            endif
        endif
    endfor
    if empty(lines)
        call add(lines, '  (no bindings registered)')
    endif
    return lines
endfunction

" ── show / hide ───────────────────────────────────────────────────────────

function! wplus#whichkey#show(prefix) abort
    call wplus#whichkey#close()
    let lines = s:build_lines(a:prefix)
    let opts = {
        \ 'line':     &lines - len(lines) - 3,
        \ 'col':      1,
        \ 'minwidth': 40,
        \ 'maxheight': &lines / 2,
        \ 'border':   [1, 1, 1, 1],
        \ 'borderhighlight': ['WplusWKBorder'],
        \ 'title':    ' ' . a:prefix . ' ',
        \ 'wrap':     0,
        \ 'zindex':   50,
        \ }
    let s:popup_id = popup_create(lines, opts)
endfunction

function! wplus#whichkey#close() abort
    if s:popup_id != -1
        try | call popup_close(s:popup_id) | catch | endtry
        let s:popup_id = -1
    endif
    if s:timer != -1
        call timer_stop(s:timer)
        let s:timer = -1
    endif
endfunction

" ── key intercept ─────────────────────────────────────────────────────────
" We hook into the leader press: after timeoutlen we show the popup.

function! wplus#whichkey#leader_pressed() abort
    call wplus#whichkey#close()
    let s:timer = timer_start(&timeoutlen, {_ -> wplus#whichkey#show('<leader>')})
    return ''  " pass-through
endfunction

" ── highlights ────────────────────────────────────────────────────────────

function! s:init_highlights() abort
    hi default WplusWKKey    ctermfg=214 guifg=#fabd2f
    hi default WplusWKDesc   ctermfg=223 guifg=#ebdbb2
    hi default WplusWKBorder ctermfg=239 guifg=#504945
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#whichkey#setup() abort
    call s:init_highlights()

    " Register hints for mappings defined in ~/.vimrc
    call wplus#whichkey#register('<leader>e',  'File explorer toggle')
    call wplus#whichkey#register('<leader>f',  'File explorer find')
    call wplus#whichkey#register('<leader>t',  'Tagbar toggle')
    call wplus#whichkey#register('<leader>u',  'Undotree toggle')
    call wplus#whichkey#register('<leader>p',  'Fuzzy file finder')
    call wplus#whichkey#register('<leader>b',  'Buffer list (fzf)')
    call wplus#whichkey#register('<leader>g',  'Grep (Rg)')
    call wplus#whichkey#register('<leader>/',  'Buffer lines')
    call wplus#whichkey#register('<leader>h',  'Clear search highlight')
    call wplus#whichkey#register('<leader>w',  'Save file')
    call wplus#whichkey#register('<leader>q',  'Quit')
    call wplus#whichkey#register('<leader>Q',  'Force quit all')
    call wplus#whichkey#register('<leader>`',  'Open terminal')
    call wplus#whichkey#register('<leader>tv', 'Vertical terminal')
    call wplus#whichkey#register('<leader>ts', 'Horizontal terminal')
    call wplus#whichkey#register('<leader>xd', 'Diagnostics list')
    call wplus#whichkey#register('<leader>xs', 'Symbols list')
    call wplus#whichkey#register('<leader>xc', 'Commands list')
    call wplus#whichkey#register('<leader>rn', 'Rename symbol')
    call wplus#whichkey#register('<leader>ca', 'Code action')
    call wplus#whichkey#register('<leader>cf', 'Format code')
    call wplus#whichkey#register('<leader>bl', 'Git blame toggle')

    " Hook leader key to show popup after timeout
    nnoremap <expr> <leader> wplus#whichkey#leader_pressed() .. "\<leader>"
    vnoremap <expr> <leader> wplus#whichkey#leader_pressed() .. "\<leader>"

    " Close popup on any key
    augroup wplus_whichkey
        autocmd!
        autocmd CursorMoved,InsertEnter,BufLeave * call wplus#whichkey#close()
        autocmd ColorScheme * call s:init_highlights()
    augroup END
endfunction
