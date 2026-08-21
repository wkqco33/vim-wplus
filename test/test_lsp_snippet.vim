" test/test_lsp_snippet.vim — Test LSP snippet parsing

" parse_snippet returns a list of segments:
"   {'type': 'text', 'text': '...'}
"   {'type': 'stop', 'index': N, 'placeholder': '...'}
function! Test_lsp_snippet_plain_text() abort
    call wplus#lsp#setup()
    let l:segs = wplus#lsp#_test_parse_snippet('hello world')
    call assert_equal([{'type': 'text', 'text': 'hello world'}], l:segs, 'Plain text should be a single text segment')
endfunction

function! Test_lsp_snippet_numbered_stop() abort
    call wplus#lsp#setup()
    let l:segs = wplus#lsp#_test_parse_snippet('foo$1bar')
    call assert_equal([
        \ {'type': 'text', 'text': 'foo'},
        \ {'type': 'stop', 'index': 1, 'placeholder': ''},
        \ {'type': 'text', 'text': 'bar'},
        \ ], l:segs, '$N should become a numbered stop')
endfunction

function! Test_lsp_snippet_placeholder_stop() abort
    call wplus#lsp#setup()
    let l:segs = wplus#lsp#_test_parse_snippet('${1:name}')
    call assert_equal([
        \ {'type': 'stop', 'index': 1, 'placeholder': 'name'},
        \ ], l:segs, '${N:placeholder} should carry its placeholder')
endfunction

function! Test_lsp_snippet_final_stop() abort
    call wplus#lsp#setup()
    let l:segs = wplus#lsp#_test_parse_snippet('a$0b')
    call assert_equal([
        \ {'type': 'text', 'text': 'a'},
        \ {'type': 'stop', 'index': 0, 'placeholder': ''},
        \ {'type': 'text', 'text': 'b'},
        \ ], l:segs, '$0 should become the final stop')
endfunction

function! Test_lsp_snippet_escaped_dollar_brace() abort
    call wplus#lsp#setup()
    let l:segs = wplus#lsp#_test_parse_snippet('\${literal}')
    call assert_equal([{'type': 'text', 'text': '${literal}'}], l:segs, '\${ should be a literal ${')
endfunction

function! Test_lsp_snippet_mixed() abort
    call wplus#lsp#setup()
    let l:segs = wplus#lsp#_test_parse_snippet('fn(${1:a}, $2) { $0 }')
    call assert_equal([
        \ {'type': 'text', 'text': 'fn('},
        \ {'type': 'stop', 'index': 1, 'placeholder': 'a'},
        \ {'type': 'text', 'text': ', '},
        \ {'type': 'stop', 'index': 2, 'placeholder': ''},
        \ {'type': 'text', 'text': ') { '},
        \ {'type': 'stop', 'index': 0, 'placeholder': ''},
        \ {'type': 'text', 'text': ' }'},
        \ ], l:segs, 'Mixed snippet should parse into ordered segments')
endfunction
