" wplus/project.vim — Per-project local configuration with security trust prompt

if exists('g:autoloaded_wplus_project') | finish | endif
let g:autoloaded_wplus_project = 1

let g:wplus_project_config    = get(g:, 'wplus_project_config',    '.wplus.vim')
let g:wplus_project_verbose   = get(g:, 'wplus_project_verbose',   0)
let g:wplus_project_trust_all = get(g:, 'wplus_project_trust_all', 0)

let s:loaded_configs = {}   " root path -> 1 (sourced) or 0 (skipped)
let s:trust_queue    = []   " root paths queued before VimEnter

" ── internal ──────────────────────────────────────────────────────────────

function! s:config_path(root) abort
    return a:root . '/' . g:wplus_project_config
endfunction

function! s:read_trust_store() abort
    let l:file = get(g:, 'wplus_project_trust_file', expand('~/.vim/wplus-trust.json'))
    if !filereadable(l:file)
        return {}
    endif
    try
        let l:content = join(readfile(l:file), "\n")
        let l:dict = json_decode(l:content)
        return type(l:dict) == v:t_dict ? l:dict : {}
    catch
        return {}
    endtry
endfunction

function! s:write_trust_store(store) abort
    let l:file = get(g:, 'wplus_project_trust_file', expand('~/.vim/wplus-trust.json'))
    let l:dir = fnamemodify(l:file, ':h')
    if !isdirectory(l:dir)
        call mkdir(l:dir, 'p')
    endif
    let l:json = json_encode(a:store)
    call writefile([l:json], l:file)
endfunction

function! s:calc_hash(filepath) abort
    if !filereadable(a:filepath) | return '' | endif
    let l:lines = readfile(a:filepath, 'b')
    if exists('*sha256')
        return sha256(join(l:lines, "\n"))
    elseif executable('shasum')
        let l:out = system('shasum -a 256 ' . shellescape(a:filepath))
        return split(l:out)[0]
    else
        return getfsize(a:filepath) . ':' . getftime(a:filepath)
    endif
endfunction

function! s:prompt_trust(cfg) abort
    if exists('g:wplus_test_trust_choice')
        return g:wplus_test_trust_choice
    endif

    " Open preview split to show contents of config
    execute 'pedit ' . fnameescape(a:cfg)
    redraw

    let l:msg = '[wplus] Untrusted project config: ' . fnamemodify(a:cfg, ':~:.')
    let l:choice = confirm(l:msg, "&Trust always\ntrust &Once\n&Skip", 3)
    pclose

    if l:choice == 1
        return 'T'
    elseif l:choice == 2
        return 't'
    else
        return 's'
    endif
endfunction

function! s:do_source(root, cfg) abort
    let s:loaded_configs[a:root] = 1
    try
        execute 'source ' . fnameescape(a:cfg)
        if g:wplus_project_verbose
            call wplus#util#info_msg('project', 'loaded ' . fnamemodify(a:cfg, ':~:.'))
        endif
    catch
        call wplus#util#error_msg('project', 'error in ' . fnamemodify(a:cfg, ':~:.') . ': ' . v:exception)
    endtry
endfunction

function! s:load_config(root) abort
    if empty(a:root) | return | endif
    if has_key(s:loaded_configs, a:root) | return | endif

    let l:cfg = s:config_path(a:root)
    if !filereadable(l:cfg) | return | endif

    " Delay until VimEnter if startup isn't complete
    if v:vim_did_enter == 0
        if index(s:trust_queue, a:root) == -1
            call add(s:trust_queue, a:root)
        endif
        return
    endif

    if g:wplus_project_trust_all
        call s:do_source(a:root, l:cfg)
        return
    endif

    let l:hash = s:calc_hash(l:cfg)
    let l:store = s:read_trust_store()
    if get(l:store, a:root, '') ==# l:hash && !empty(l:hash)
        call s:do_source(a:root, l:cfg)
        return
    endif

    let s:loaded_configs[a:root] = 0
    let l:choice = s:prompt_trust(l:cfg)
    if l:choice ==# 'T'
        let l:store[a:root] = l:hash
        call s:write_trust_store(l:store)
        call s:do_source(a:root, l:cfg)
    elseif l:choice ==# 't'
        call s:do_source(a:root, l:cfg)
    else
        call wplus#util#warn_msg('project', 'skipped untrusted config: ' . fnamemodify(l:cfg, ':~:.'))
    endif
endfunction

function! s:on_vimenter() abort
    for l:root in s:trust_queue
        call s:load_config(l:root)
    endfor
    let s:trust_queue = []
endfunction

" ── public API ────────────────────────────────────────────────────────────

function! wplus#project#edit() abort
    let l:root = wplus#root#find_root()
    if empty(l:root)
        call wplus#util#warn_msg('project', 'no project root found')
        return
    endif
    let l:cfg = s:config_path(l:root)
    execute 'edit ' . fnameescape(l:cfg)
    if !filereadable(l:cfg)
        call setline(1, [
            \ '" vim-wplus project configuration: ' . fnamemodify(l:root, ':~'),
            \ '" This file is sourced automatically when opening files under this project.',
            \ '" Example:',
            \ '"   let g:wplus_run_commands = {''go'': ''go run ./cmd/main.go''}',
            \ '"   set colorcolumn=100',
            \ '',
            \ ])
        call wplus#util#info_msg('project', 'new project config: ' . fnamemodify(l:cfg, ':~:.'))
    endif
endfunction

function! wplus#project#reload() abort
    let l:root = wplus#root#find_root()
    if empty(l:root)
        call wplus#util#warn_msg('project', 'no project root found')
        return
    endif
    if has_key(s:loaded_configs, l:root)
        call remove(s:loaded_configs, l:root)
    endif
    call s:load_config(l:root)
    call wplus#util#info_msg('project', 'reloaded project config')
endfunction

" ── setup ─────────────────────────────────────────────────────────────────

function! wplus#project#setup() abort
    command! WprojectEdit   call wplus#project#edit()
    command! WprojectReload call wplus#project#reload()

    nnoremap <silent> <leader>pe :WprojectEdit<CR>
    nnoremap <silent> <leader>pr :WprojectReload<CR>

    augroup WplusProject
        autocmd!
        autocmd VimEnter * call s:on_vimenter()
        autocmd BufEnter * call s:load_config(wplus#root#find_root())
        execute 'autocmd BufWritePost */' . g:wplus_project_config .
                    \ ',' . g:wplus_project_config .
                    \ ' call wplus#project#reload()'
    augroup END
endfunction
