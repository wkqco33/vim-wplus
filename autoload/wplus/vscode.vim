" wplus/vscode.vim — VS Code-aligned keymap layer (opt-in)
"
" Maps common VS Code shortcuts onto wplus features so users coming from VS
" Code do not have to learn a second set of bindings. Enable with:
"
"   let g:wplus_vscode_keymaps = 1
"
" Mappings are only installed for modules that are enabled, and keys that
" would hijack a Vim native key (see wplus#health#native_keys()) are skipped.
" Terminal caveat: <C-Space> and <C-S-...> may not be distinguishable in some
" terminals; <C-Space> is also bound to <C-@> (NUL) as a fallback.

if exists('g:autoloaded_wplus_vscode') | finish | endif
let g:autoloaded_wplus_vscode = 1

let g:wplus_vscode_keymaps = get(g:, 'wplus_vscode_keymaps', 0)

function! s:enabled(module) abort
    return get(g:, 'wplus_' . a:module . '_enabled', 1)
endfunction

function! s:map(mode, lhs, rhs) abort
    execute a:mode . 'noremap <silent> ' . a:lhs . ' ' . a:rhs
endfunction

function! wplus#vscode#setup() abort
    if !g:wplus_vscode_keymaps | return | endif

    " ── LSP navigation & editing ─────────────────────────────────────────
    if s:enabled('lsp')
        call s:map('n', '<F12>', ':WlspDefinition<CR>')
        call s:map('n', '<S-F12>', ':WlspReferences<CR>')
        call s:map('n', '<A-F12>', ':WlspPeekDefinition<CR>')
        call s:map('n', '<F2>', ':WlspRename<CR>')
        call s:map('n', '<C-.>', ':WlspCodeAction<CR>')
        call s:map('n', '<C-S-Space>', ':WlspSignatureHelp<CR>')
        call s:map('i', '<C-S-Space>', '<C-o>:WlspSignatureHelp<CR>')
        call s:map('i', '<C-Space>', '<C-o>:WlspCompletion<CR>')
        call s:map('i', '<C-@>', '<C-o>:WlspCompletion<CR>')
        call s:map('n', '<C-S-M>', ':WlspProblems<CR>')
        call s:map('n', '<C-T>', ':WlspSymbols<CR>')
        call s:map('n', '<C-S-H>', ':WlspCallHierarchy<CR>')
    endif

    " ── Search / navigation ───────────────────────────────────────────────
    if s:enabled('grep')
        call s:map('n', '<C-S-F>', ':WgrepWord<CR>')
        call s:map('x', '<C-S-F>', ':<C-u>call wplus#grep#search_visual()<CR>')
    endif
    if s:enabled('finder')
        call s:map('n', '<C-p>', ':WfindFiles<CR>')
    endif
    if s:enabled('outline')
        call s:map('n', '<C-S-O>', ':WoutlineToggle<CR>')
    endif
    if s:enabled('explorer')
        call s:map('n', '<C-S-E>', ':WexplorerToggle<CR>')
    endif
    if s:enabled('terminal')
        call s:map('n', '<C-`>', ':WterminalToggle<CR>')
        call s:map('n', '<C-S-C>', ':WterminalToggle<CR>')
    endif

    " ── Editing (line ops) ────────────────────────────────────────────────
    call s:map('n', '<C-S-K>', 'dd')
    call s:map('n', '<C-Enter>', 'o')
    call s:map('n', '<C-S-Enter>', 'O')
    call s:map('n', '<C-S-\\>', '%')

    " ── Folding ───────────────────────────────────────────────────────────
    if s:enabled('fold')
        call s:map('n', '<C-S-[>', ':call wplus#fold#toggle()<CR>')
        call s:map('n', '<C-S-]>', ':call wplus#fold#open_all()<CR>')
        call s:map('n', '<C-k><C-0>', ':call wplus#fold#close_all()<CR>')
        call s:map('n', '<C-k><C-j>', ':call wplus#fold#open_all()<CR>')
    endif

    " ── Buffer cycling ────────────────────────────────────────────────────
    call s:map('n', '<C-Tab>', ':bnext<CR>')
    call s:map('n', '<C-S-Tab>', ':bprev<CR>')
    call s:map('n', '<C-PageDown>', ':bnext<CR>')
    call s:map('n', '<C-PageUp>', ':bprev<CR>')
endfunction
