" wplus/project.vim — Per-project local configuration
" Auto-sources .wplus.vim (or the file named g:wplus_project_config) from
" the project root detected by wplus#root#find_root().  Provides a command
" to open and edit the local config file directly.

if exists('g:autoloaded_wplus_project') | finish | endif
let g:autoloaded_wplus_project = 1

let g:wplus_project_config  = get(g:, 'wplus_project_config',  '.wplus.vim')
let g:wplus_project_verbose = get(g:, 'wplus_project_verbose', 0)

let s:loaded_configs = {}   " root path -> 1 (already sourced this session)

" ── internal ──────────────────────────────────────────────────────────────

function! s:config_path(root) abort
    return a:root . '/' . g:wplus_project_config
endfunction

function! s:load_config(root) abort
    if empty(a:root) | return | endif
    if has_key(s:loaded_configs, a:root) | return | endif

    let l:cfg = s:config_path(a:root)
    if !filereadable(l:cfg) | return | endif

    let s:loaded_configs[a:root] = 1
    try
        execute 'source ' . fnameescape(l:cfg)
        if g:wplus_project_verbose
            call wplus#util#info_msg('project', 'loaded ' . fnamemodify(l:cfg, ':~:.'))
        endif
    catch
        call wplus#util#error_msg('project', 'error in ' . fnamemodify(l:cfg, ':~:.') . ': ' . v:exception)
    endtry
endfunction

" ── public API ────────────────────────────────────────────────────────────

" Open (or create) the project config in the current window.
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

" Reload the current project's config (useful after editing it).
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
        " Load config whenever we enter a buffer that belongs to a project
        autocmd BufEnter * call s:load_config(wplus#root#find_root())
        " After saving the project config file, reload it automatically.
        " The pattern is a glob, not a regex -- escaping the dots produced
        " '\.wplus\.vim', which matches no filename, so this never once fired.
        execute 'autocmd BufWritePost */' . g:wplus_project_config .
                    \ ',' . g:wplus_project_config .
                    \ ' call wplus#project#reload()'
    augroup END
endfunction
