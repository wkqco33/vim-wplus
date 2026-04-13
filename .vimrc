" ============================================================
" 사전 설정 (플러그인 로드 전에 선언해야 함)
" ============================================================
set nocompatible
set encoding=utf-8
let mapleader = " "

" vim-polyglot이 개별 언어 플러그인(vim-go, rust.vim, python-syntax)과
" 충돌하지 않도록 해당 언어 비활성화
let g:polyglot_disabled = ['go', 'rust', 'python']

" ============================================================
" vim-plug 플러그인 관리자
" ============================================================
call plug#begin('~/.vim/plugged')

" --- UI / 편의기능 ---
Plug '/home/wkqco/Workspace/utils/vim-wplus'
Plug 'preservim/nerdtree'               " 파일 탐색기
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'                 " 퍼지 파인더
Plug 'morhetz/gruvbox'                  " 컬러 테마
Plug 'tpope/vim-fugitive'               " git 통합
Plug 'preservim/tagbar'                 " 코드 구조 보기 (ctags 필요)

" --- LSP & 코드 완성 (coc.nvim) ---
Plug 'neoclide/coc.nvim', {'branch': 'release'}

" --- GitHub Copilot ---
Plug 'github/copilot.vim'

" --- Go ---
Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }

" --- Rust ---
Plug 'rust-lang/rust.vim'

" --- C / C++ ---
" (:A 명령은 vim-wplus/altfile 모듈이 제공)

" --- Python ---
Plug 'vim-python/python-syntax'
Plug 'heavenshell/vim-pydocstring', { 'do': 'make install', 'for': 'python' }

" --- 공통 ---
Plug 'dense-analysis/ale'              " 비동기 linting
Plug 'sheerun/vim-polyglot'            " 다양한 언어 syntax
Plug 'mg979/vim-visual-multi', {'branch': 'master'}  " 멀티 커서

call plug#end()

" ============================================================
" 기본 설정
" ============================================================
syntax on

set fileencoding=utf-8
set fileencodings=utf-8,cp949,euc-kr,latin1
set number                  " 줄 번호
set relativenumber          " 상대 줄 번호
set cursorline              " 현재 줄 강조
set signcolumn=yes          " 사인 컬럼 항상 표시

set tabstop=4
set shiftwidth=4
set expandtab               " 탭을 스페이스로
set autoindent              " smartindent 제거: filetype indent on과 충돌, Python # 들여쓰기 버그 유발

set hlsearch                " 검색 결과 강조
set incsearch               " 입력하면서 검색
set ignorecase
set smartcase

set hidden                  " 저장 안 해도 버퍼 전환
set nobackup
set noswapfile
set undofile                " 영구 undo
set undodir=~/.vim/undodir

set scrolloff=8             " 스크롤 여백
set sidescrolloff=8
set wrap
set linebreak

set clipboard=unnamedplus   " 시스템 클립보드 사용
set mouse=a                 " 마우스 지원

" 명령줄 탭 자동완성 개선
set wildmenu
set wildmode=longest:full,full
set wildignore+=*.o,*.obj,*.pyc,__pycache__,*.class,*.so,*.swp

" 자동완성 팝업 최대 높이
set pumheight=10

" 터미널 타이틀에 파일명 표시
set title

" 007 → 010 (octal) 증가 방지 (Ctrl+a/x)
set nrformats-=octal

" 트레일링 스페이스 / 탭 시각화
set list
set listchars=tab:→\ ,trail:·,nbsp:␣

set updatetime=300          " coc.nvim 반응속도
set timeoutlen=500
set shortmess+=c            " coc.nvim 자동완성 메시지 억제 (ins-completion-menu 노이즈 제거)

set splitbelow
set splitright

" 80자 가이드라인
set colorcolumn=80,120

" ============================================================
" 컬러 테마
" ============================================================
set termguicolors
set background=dark
colorscheme gruvbox

" ============================================================
" 키 매핑
" ============================================================

" 파일 탐색기
nnoremap <leader>e :NERDTreeToggle<CR>
nnoremap <leader>f :NERDTreeFind<CR>

" Tagbar
nnoremap <leader>t :TagbarToggle<CR>

" Undotree
nnoremap <leader>u :UndotreeToggle<CR>

" fzf
nnoremap <leader>p :Files<CR>
nnoremap <leader>b :Buffers<CR>
nnoremap <leader>g :Rg<CR>
nnoremap <leader>/ :BLines<CR>

" 창 이동
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" 버퍼 이동
nnoremap <Tab>   :bnext<CR>
nnoremap <S-Tab> :bprev<CR>

" 검색 하이라이트 제거 (<Esc> 직접 매핑은 터미널 arrow key 오작동 유발)
" <C-l>은 창 이동에 사용 중이므로 <leader>h 사용
nnoremap <silent> <leader>h :noh<CR>

" 저장 / 종료
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>Q :qa!<CR>

" 줄 이동 (Alt+j/k)
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv

" 통합 터미널 (VS Code Ctrl+` 유사)
nnoremap <leader>`  :terminal<CR>
nnoremap <leader>tv :vertical terminal<CR>
nnoremap <leader>ts :below terminal<CR>
tnoremap <Esc>      <C-\><C-n>
tnoremap <C-h>      <C-\><C-n><C-w>h
tnoremap <C-j>      <C-\><C-n><C-w>j
tnoremap <C-k>      <C-\><C-n><C-w>k
tnoremap <C-l>      <C-\><C-n><C-w>l

" 진단 목록 패널 (VS Code Problems panel 유사)
nnoremap <leader>xd :CocList diagnostics<CR>
nnoremap <leader>xs :CocList symbols<CR>
nnoremap <leader>xc :CocList commands<CR>

" ============================================================
" NERDTree 설정
" ============================================================
let NERDTreeShowHidden = 1
let NERDTreeMinimalUI  = 1

function! s:OpenIDELayout() abort
    if exists('s:std_in') | return | endif
    if argc() > 0 && isdirectory(argv(0))
        execute 'NERDTree ' . argv(0)
    else
        NERDTree
        wincmd p
    endif
endfunction

augroup nerdtree_settings
    autocmd!
    autocmd StdinReadPre * let s:std_in = 1
    autocmd VimEnter * call s:OpenIDELayout()
    " NERDTree 내부 WinEnter auto-close 비활성화 (Vim 9.1+ E1312 방지)
    " WinEnter 안에서 창 레이아웃 변경이 금지됐으므로 BufEnter로 대체
    autocmd VimEnter * silent! autocmd! NERDTree WinEnter
    " vim만 남으면 자동 닫기 (BufEnter는 E1312 제약 없음)
    autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 &&
        \ exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif
augroup END

" ============================================================
" coc.nvim 설정 (LSP 코드 완성)
" ============================================================
" 필요한 coc 확장 자동 설치
let g:coc_global_extensions = [
    \ 'coc-go',
    \ 'coc-clangd',
    \ 'coc-pyright',
    \ 'coc-rust-analyzer',
    \ 'coc-json',
    \ 'coc-yaml',
    \ 'coc-toml',
    \ 'coc-sh',
    \ 'coc-snippets',
    \ ]

" Tab으로 완성 선택
inoremap <silent><expr> <TAB>
    \ coc#pum#visible() ? coc#pum#next(1) :
    \ CheckBackspace() ? "\<Tab>" :
    \ coc#refresh()
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

function! CheckBackspace() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Enter로 완성 확정
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
    \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

" Ctrl+Space로 완성 강제 트리거
inoremap <silent><expr> <C-Space> coc#refresh()

" 진단 이동
nmap <silent> [g <Plug>(coc-diagnostic-prev)
nmap <silent> ]g <Plug>(coc-diagnostic-next)

" 정의/참조 이동
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)

" 호버로 문서 보기
nnoremap <silent> K :call ShowDocumentation()<CR>
function! ShowDocumentation() abort
    if CocAction('hasProvider', 'hover')
        call CocActionAsync('doHover')
    else
        call feedkeys('K', 'in')
    endif
endfunction

" 심볼 리네임
nmap <leader>rn <Plug>(coc-rename)

" 코드 액션
nmap <leader>ca <Plug>(coc-codeaction-cursor)
vmap <leader>ca <Plug>(coc-codeaction-selected)

" 포맷
nmap <leader>cf <Plug>(coc-format)
vmap <leader>cf <Plug>(coc-format-selected)

" VS Code 스타일 포맷 단축키는 vim-wplus/format 모듈이 담당 (<M-F>)

" ============================================================
" GitHub Copilot 설정
" ============================================================
" Copilot 제안 수락: Tab (coc와 충돌 방지: Copilot은 Ctrl+l로)
let g:copilot_no_tab_map = v:true
imap <silent><script><expr> <C-l> copilot#Accept("\<CR>")
imap <C-]> <Plug>(copilot-next)
imap <M-[> <Plug>(copilot-previous)    " <C-[>는 <Esc>와 동일 → <M-[>(Alt+[) 으로 변경
imap <C-\> <Plug>(copilot-dismiss)

" Copilot 비활성화할 파일 타입 지정 (v:true는 기본값이므로 의미 없음)
let g:copilot_filetypes = {
    \ 'xml':  v:false,
    \ 'env':  v:false,
    \ }

" ============================================================
" Go 설정 (vim-go)
" ============================================================
let g:go_fmt_autosave      = 0  " 저장 시 포맷을 coc-go(gopls)로 통일, vim-go fmt 비활성화
let g:go_fmt_command       = 'goimports'  " vim-go 수동 :GoFmt 호출 시 사용할 도구 (참조용)
let g:go_auto_type_info    = 0  " gopls 비활성화 시 사용 불가 (coc-go가 대신 처리)
let g:go_highlight_types   = 1
let g:go_highlight_fields  = 1
let g:go_highlight_funcs   = 1
let g:go_highlight_methods = 1
let g:go_highlight_operators = 1
let g:go_highlight_extra_types = 1
let g:go_highlight_build_constraints = 1

" coc-go 사용하므로 vim-go LSP 기능 비활성화 (중복 방지)
let g:go_gopls_enabled = 0
let g:go_def_mapping_enabled = 0
let g:go_doc_keywordprg_enabled = 0
let g:go_echo_command_info = 0

augroup go_settings
    autocmd!
    autocmd FileType go nmap <buffer> <leader>gr :GoRun<CR>
    autocmd FileType go nmap <buffer> <leader>gt :GoTest<CR>
    autocmd FileType go nmap <buffer> <leader>gb :GoBuild<CR>
    autocmd FileType go nmap <buffer> <leader>gi :GoImports<CR>
    autocmd FileType go setlocal noexpandtab tabstop=4 shiftwidth=4
augroup END

" ============================================================
" Rust 설정
" ============================================================
let g:rustfmt_autosave = 0  " ALE fixer가 rustfmt 처리하므로 중복 비활성화
augroup rust_settings
    autocmd!
    autocmd FileType rust nmap <buffer> <leader>rr :!cargo run<CR>
    autocmd FileType rust nmap <buffer> <leader>rc :!cargo check<CR>
    autocmd FileType rust nmap <buffer> <leader>rt :!cargo test<CR>
augroup END

" ============================================================
" C / C++ 설정
" ============================================================
augroup c_cpp_settings
    autocmd!
    autocmd FileType c,cpp setlocal tabstop=4 shiftwidth=4 expandtab
    autocmd FileType c,cpp nmap <buffer> <leader>ah :A<CR>  " 헤더/소스 전환 (<leader>h는 전역 noh)
augroup END

" ============================================================
" Python 설정
" ============================================================
let g:python_highlight_all = 1
augroup python_settings
    autocmd!
    autocmd FileType python setlocal tabstop=4 shiftwidth=4 expandtab
    autocmd FileType python nmap <buffer> <leader>rr :!python3 %<CR>
augroup END

" ============================================================
" ALE (Linting)
" ============================================================
let g:ale_linters = {
    \ 'go':     ['golangci-lint'],
    \ 'c':      ['clang'],
    \ 'cpp':    ['clang'],
    \ 'python': ['flake8', 'mypy'],
    \ 'rust':   ['cargo'],
    \ }
" Go/Rust 포맷은 coc.nvim(LSP)으로 통일, ALE는 linting 전용
let g:ale_fixers = {
    \ '*':      ['remove_trailing_lines', 'trim_whitespace'],
    \ 'go':     [],
    \ 'c':      ['clang-format'],
    \ 'cpp':    ['clang-format'],
    \ 'python': ['black', 'isort'],
    \ 'rust':   [],
    \ }
let g:ale_fix_on_save     = 1
let g:ale_sign_error      = '✗'
let g:ale_sign_warning    = '⚠'

" coc와 함께 사용하므로 ALE LSP 비활성화
let g:ale_disable_lsp = 1

" ============================================================
" 파일 열 때 마지막 커서 위치로 복귀
" ============================================================
augroup restore_cursor
    autocmd!
    autocmd BufReadPost *
        \ if line("'\"") > 1 && line("'\"") <= line("$") |
        \   exe "normal! g'\"" |
        \ endif
augroup END

" ============================================================
" vim-wplus: git blame 설정 (wplus/blame 모듈)
" ============================================================
let g:wplus_blame_delay        = 500
let g:wplus_blame_prefix       = '   '
let g:wplus_blame_template     = '<author>, <date> • <summary>'
let g:wplus_blame_date_format  = '%y/%m/%d'
nnoremap <leader>bl :BlamerToggle<CR>

" ============================================================
" undodir 생성 (없으면)
" ============================================================
if !isdirectory(expand('~/.vim/undodir'))
    call mkdir(expand('~/.vim/undodir'), 'p')
endif
