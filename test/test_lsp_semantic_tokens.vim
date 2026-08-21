" test/test_lsp_semantic_tokens.vim — Test LSP semantic token delta decoding

" decode_semantic_tokens returns a list of {lnum, col, length, type, modifiers}
" with 1-based lnum/col, from the flat delta-encoded LSP array.
function! Test_lsp_semantic_tokens_empty() abort
    call wplus#lsp#setup()
    call assert_equal([], wplus#lsp#_test_decode_semantic_tokens([]), 'Empty data should decode to no tokens')
endfunction

function! Test_lsp_semantic_tokens_single() abort
    call wplus#lsp#setup()
    " [deltaLine=0, deltaStart=0, length=3, type=6(function), mods=0]
    let l:toks = wplus#lsp#_test_decode_semantic_tokens([0, 0, 3, 6, 0])
    call assert_equal(1, len(l:toks), 'One token expected')
    call assert_equal(1, l:toks[0].lnum, 'First token starts on line 1')
    call assert_equal(1, l:toks[0].col, 'First token starts at col 1')
    call assert_equal(3, l:toks[0].length, 'Token length should be 3')
    call assert_equal(6, l:toks[0].type, 'Token type should be 6')
endfunction

function! Test_lsp_semantic_tokens_same_line() abort
    call wplus#lsp#setup()
    " Token 1: line 0, col 0, len 3. Token 2: same line, deltaStart 4, len 2.
    let l:toks = wplus#lsp#_test_decode_semantic_tokens([0, 0, 3, 6, 0, 0, 4, 2, 7, 0])
    call assert_equal(2, len(l:toks), 'Two tokens expected')
    call assert_equal(1, l:toks[0].lnum, 'First token line')
    call assert_equal(1, l:toks[0].col, 'First token col')
    call assert_equal(1, l:toks[1].lnum, 'Second token same line')
    call assert_equal(5, l:toks[1].col, 'Second token col should be 1+4')
endfunction

function! Test_lsp_semantic_tokens_new_line() abort
    call wplus#lsp#setup()
    " Token 1: line 0, col 0, len 3. Token 2: deltaLine 2, deltaStart 1, len 4.
    let l:toks = wplus#lsp#_test_decode_semantic_tokens([0, 0, 3, 6, 0, 2, 1, 4, 7, 0])
    call assert_equal(2, len(l:toks), 'Two tokens expected')
    call assert_equal(1, l:toks[0].lnum, 'First token line')
    call assert_equal(3, l:toks[1].lnum, 'Second token line should be 1+2')
    call assert_equal(2, l:toks[1].col, 'Second token col should be absolute 1+1')
endfunction
