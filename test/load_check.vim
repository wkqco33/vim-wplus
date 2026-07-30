" load_check.vim — source every module and call its setup().
"
" Sourcing alone only proves the file parses; a setup() that throws would still
" ship. This runs both and collects every failure instead of aborting on the
" first, so one broken module does not mask the others.
"
" Usage: vim -Nu NONE -i NONE -n -es -S test/load_check.vim
" Writes findings to load_errors.txt in the cwd and always creates the file,
" so a missing file means Vim died and the caller should treat that as failure.

set cpoptions&vim

let s:repo = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:repo)

let s:errors = []

for s:f in glob(s:repo . '/autoload/**/*.vim', 0, 1) + [s:repo . '/plugin/wplus.vim']
    try
        execute 'source' fnameescape(s:f)
    catch
        call add(s:errors, 'source ' . fnamemodify(s:f, ':t') . ': ' . v:exception)
    endtry
endfor

for s:path in glob(s:repo . '/autoload/wplus/*.vim', 0, 1)
    let s:mod = fnamemodify(s:path, ':t:r')
    if !exists('*wplus#' . s:mod . '#setup')
        continue
    endif
    try
        execute 'call wplus#' . s:mod . '#setup()'
    catch
        call add(s:errors, 'setup ' . s:mod . ': ' . v:exception)
    endtry
endfor

call writefile(s:errors, 'load_errors.txt')
