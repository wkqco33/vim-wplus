" wplus/finder.vim — Minimal fuzzy finder using Vim 9 popup and matchfuzzy()

if exists('g:autoloaded_wplus_finder') | finish | endif
let g:autoloaded_wplus_finder = 1

let g:wplus_finder_width_ratio  = get(g:, 'wplus_finder_width_ratio',  0.7)
let g:wplus_finder_height_ratio = get(g:, 'wplus_finder_height_ratio', 0.4)
let g:wplus_finder_fuzzy_limit  = get(g:, 'wplus_finder_fuzzy_limit', 10000)

let s:prompt = '> '
let s:file_job = v:null
let s:file_job_items = []

let s:state = {
    \ 'winid': -1,
    \ 'bufnr': -1,
    \ 'items': [],
    \ 'filtered': [],
    \ 'query': '',
    \ 'callback': '',
    \ 'selected': 0,
    \ 'width': 0,
    \ 'height': 0
    \ }

function! wplus#finder#open(items, callback, title) abort
    let s:state.items = a:items
    let s:state.filtered = copy(a:items)
    let s:state.query = ''
    let s:state.callback = a:callback
    let s:state.selected = 0

    let l:width = float2nr(&columns * g:wplus_finder_width_ratio)
    let l:height = float2nr(&lines * g:wplus_finder_height_ratio)
    let s:state.width = l:width
    let s:state.height = l:height
    
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
    call win_execute(s:state.winid, 'syntax match Title /^' . s:prompt . '.*/')
    call s:update_display()
endfunction

function! wplus#finder#filter(winid, key) abort
    if a:key == "\<Esc>" || a:key == "\<C-c>"
        call popup_close(a:winid)
        call s:cleanup_state()
        return 1
    elseif a:key == "\<CR>" || a:key == "\<C-v>" || a:key == "\<C-s>" || a:key == "\<C-t>"
        let l:res = get(s:state.filtered, s:state.selected, '')
        call popup_close(a:winid)
        if !empty(l:res)
            if type(s:state.callback) == v:t_func
                call call(s:state.callback, [l:res])
            else
                if a:key ==# "\<C-v>"
                    let l:cmd = 'vsplit'
                elseif a:key ==# "\<C-s>"
                    let l:cmd = 'split'
                elseif a:key ==# "\<C-t>"
                    let l:cmd = 'tabedit'
                else
                    let l:cmd = s:state.callback
                endif
                execute l:cmd . ' ' . fnameescape(l:res)
            endif
        endif
        call s:cleanup_state()
        return 1
    elseif a:key == "\<C-n>" || a:key == "\<Down>"
        let s:state.selected = min([s:state.selected + 1, len(s:state.filtered) - 1])
    elseif a:key == "\<C-p>" || a:key == "\<Up>"
        let s:state.selected = max([s:state.selected - 1, 0])
    elseif a:key == "\<BS>" || a:key == "\<C-h>"
        if !empty(s:state.query)
            let s:state.query = s:state.query[:-2]
            call s:filter_items()
        endif
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
        " Use matchfuzzy with limit for large result sets
        let s:state.filtered = matchfuzzy(s:state.items, s:state.query, {'limit': g:wplus_finder_fuzzy_limit})
    endif
    let s:state.selected = 0
endfunction

function! s:get_visible_items() abort
    let l:max_items = max([s:state.height - 2, 1])
    let l:count = len(s:state.filtered)
    if l:count <= l:max_items
        return {'items': copy(s:state.filtered), 'offset': 0}
    endif

    let l:offset = min([
        \ max([s:state.selected - float2nr(l:max_items / 2), 0]),
        \ l:count - l:max_items,
        \ ])
    return {'items': s:state.filtered[l:offset : l:offset + l:max_items - 1], 'offset': l:offset}
endfunction

function! s:update_display() abort
    let l:visible = s:get_visible_items()
    let l:display = [s:prompt . s:state.query, repeat('─', max([s:state.width - 2, 1]))]
    let l:display += l:visible.items
    call popup_settext(s:state.winid, l:display)
    let l:cursor = len(l:visible.items) > 0 ? (s:state.selected - l:visible.offset + 3) : 1
    call win_execute(s:state.winid, 'execute ' . l:cursor)
    redraw
endfunction

function! s:cleanup_state() abort
    " Clear state to free memory
    let s:state.items = []
    let s:state.filtered = []
    let s:state.query = ''
    let s:state.callback = ''
    let s:state.selected = 0
    let s:state.winid = -1
    let s:state.bufnr = -1
endfunction

" ── Sources ────────────────────────────────────────────────────────────────

function! s:on_file_job_output(channel, lines) abort
    if type(a:lines) == v:t_list
        call extend(s:file_job_items, a:lines)
    else
        call add(s:file_job_items, a:lines)
    endif
endfunction

function! s:on_file_job_close(job, status) abort
    let l:items = filter(copy(s:file_job_items), '!empty(v:val)')
    let s:file_job = v:null
    let s:file_job_items = []
    if a:status != 0
        call wplus#util#warn_msg('finder', 'file search failed (exit ' . a:status . ')')
        return
    endif
    call wplus#finder#open(l:items, 'edit', 'Find Files')
endfunction

function! wplus#finder#files() abort
    if type(s:file_job) == v:t_job && job_status(s:file_job) ==# 'run'
        call job_stop(s:file_job)
    endif
    let s:file_job_items = []
    if executable('rg')
        let l:cmd = ['rg', '--files']
    elseif executable('git')
        let l:cmd = ['git', 'ls-files']
    else
        let l:items = glob('**/*', 0, 1)
        call filter(l:items, '!isdirectory(v:val)')
        call wplus#finder#open(l:items, 'edit', 'Find Files')
        return
    endif
    let s:file_job = job_start(l:cmd, {
        \ 'out_mode': 'nl',
        \ 'out_cb': function('s:on_file_job_output'),
        \ 'close_cb': function('s:on_file_job_close'),
        \ })
    if type(s:file_job) != v:t_job
        let s:file_job = v:null
        call wplus#util#error_msg('finder', 'failed to start file search')
    endif
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
    augroup WplusFinder
        autocmd!
        autocmd VimLeavePre * if type(s:file_job) == v:t_job | silent! call job_stop(s:file_job) | endif
    augroup END

    command! WfindFiles   call wplus#finder#files()
    command! WfindBuffers call wplus#finder#buffers()
    command! WfindMRU     call wplus#finder#mru()

    " These live under the <leader>f "find" prefix rather than on bare
    " <leader>p / <leader>b / <leader>m. A complete mapping that is also the
    " prefix of a longer one costs a full 'timeoutlen' wait on every press, and
    " each of those three collided with a longer mapping from another module
    " (bufdelete/blame, project, marks).
    nnoremap <silent> <leader>ff :WfindFiles<CR>
    nnoremap <silent> <leader>fb :WfindBuffers<CR>
    nnoremap <silent> <leader>fr :WfindMRU<CR>
endfunction
