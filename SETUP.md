# vim-wplus 설정 가이드

> [← README](README.md) · [모듈 문서](docs/) · [단축키](docs/keymaps.md)

vim-wplus는 모듈형 구성로 구성된 의존성 없는 Vim 올인원 플러그인입니다.  
이 가이드는 설치·외부 도구·문제 해결·빠른 시작 설정을 다룹니다.

---

## 설치

### 요구사항

- **Vim 9.1+** (또는 NeoVim 0.7+)
- 필수 기능 확인:

```vim
:echo has('job') && has('channel') && has('popupwin') && has('signs') && has('textprop')
" 1이 출력되어야 합니다
```

### 방법 1 — vim-plug (권장)

```vim
call plug#begin()
Plug 'wkqco33/vim-wplus'   " GitHub
" 또는 로컬 경로
" Plug '/path/to/vim-wplus'
call plug#end()
```

Vim에서 `:PlugInstall` 실행.

### 방법 2 — pack 직접 설치

```bash
# Unix / macOS
git clone <url> ~/.vim/pack/user/start/vim-wplus

# Windows (PowerShell)
git clone <url> "$env:USERPROFILE\vimfiles\pack\user\start\vim-wplus"
```

별도 `source` 없이 자동 로드됩니다.

### 방법 3 — 수동 설치

```vim
" ~/.vimrc (Unix)
set runtimepath+=~/.vim/pack/user/start/vim-wplus
source ~/.vim/pack/user/start/vim-wplus/plugin/wplus.vim
```

```vim
" _vimrc (Windows — 슬래시 사용 권장)
set runtimepath+=C:/Users/<user>/vimfiles/pack/user/start/vim-wplus
source C:/Users/<user>/vimfiles/pack/user/start/vim-wplus/plugin/wplus.vim
```

### 빠른 시작

```bash
# 1. 복제
git clone <url> ~/.vim/pack/user/start/vim-wplus

# 2. 예시 설정 복사
cp ~/.vim/pack/user/start/vim-wplus/.vimrc.example ~/.vimrc

# 3. Vim 시작
vim
```

---

## 외부 도구

vim-wplus 자체는 의존성이 없지만, 일부 모듈은 외부 도구가 있으면 기능이 향상됩니다.

| 도구 | 관련 모듈 | 비고 |
|------|-----------|------|
| `git` | gitgutter, blame, diffview, conflict, ai | 대부분의 환경에 기본 포함 |
| `ripgrep` (`rg`) | grep, todo, finder | 강력 권장 (없으면 git grep → grep으로 폴백) |
| `curl` | ai | Windows 10 1803+에 기본 포함 |
| `ctags` (universal-ctags) | outline, ai/context | outline 사용 시 필수 |
| LSP 언어 서버 | lsp | 언어별 별도 설치 필요 |
| 포매터 (`gofmt`, `prettier` 등) | format | 없으면 `gg=G`로 폴백 |

### 도구 설치

#### ripgrep

```bash
# macOS
brew install ripgrep

# Ubuntu / Debian
sudo apt-get install ripgrep

# Windows (winget)
winget install BurntSushi.ripgrep.MSVC

# Windows (scoop)
scoop install ripgrep
```

#### ctags (universal-ctags)

```bash
# macOS
brew install universal-ctags

# Ubuntu / Debian
sudo apt-get install universal-ctags

# Windows
winget install universal-ctags
# 또는 scoop install universal-ctags
```

#### LSP 언어 서버

```bash
# Go
go install golang.org/x/tools/gopls@latest

# Python
pip install python-lsp-server

# TypeScript / JavaScript
npm install -g typescript-language-server typescript

# Rust
rustup component add rust-analyzer

# C / C++
# macOS: brew install llvm
# Ubuntu: sudo apt-get install clangd
```

---

## AI 설정

> 상세 내용 → **[docs/ai.md](docs/ai.md)**

### OpenAI

```vim
let g:wplus_ai_provider = 'openai'
let g:wplus_ai_api_key  = $OPENAI_API_KEY  " 환경 변수 권장
let g:wplus_ai_model    = 'gpt-4o'
```

### Claude

```vim
let g:wplus_ai_provider = 'claude'
let g:wplus_ai_api_key  = $ANTHROPIC_API_KEY
let g:wplus_ai_model    = 'claude-3-5-sonnet-20241022'
```

### Azure OpenAI

```vim
let g:wplus_ai_provider         = 'azure'
let g:wplus_ai_api_key          = $AZURE_OPENAI_KEY
let g:wplus_ai_azure_resource   = 'your-resource'
let g:wplus_ai_azure_deployment = 'gpt-4-deployment'
```

### Ollama (로컬)

```vim
let g:wplus_ai_provider          = 'ollama'
let g:wplus_ai_model             = 'qwen2.5-coder:7b'
let g:wplus_ai_ollama_host       = 'http://localhost:11434'
let g:wplus_ai_ollama_fim        = 1   " FIM 활성화 (코드 완성 품질 향상)
let g:wplus_ai_ollama_keep_alive = '30m'
```

**Ghost Text 수락 키 설정:**

`<Tab>`은 기본적으로 스마트 탭(`g:wplus_ai_tab_complete = 1`)으로 작동하여 AI 제안이 있으면 자동 수락합니다.
수동 매핑을 원할 경우:

```vim
inoremap <expr> <Tab> wplus#ai#smart_tab()
" 또는 <Plug> 매핑 사용:
imap <Tab> <Plug>WaiSmartTab
" Tab 대신 다른 키 사용 시:
inoremap <expr> <C-g> wplus#ai#accept_suggestion()
```

---

## 권장 키 매핑

```vim
" ~/.vimrc에 추가
let mapleader = ' '   " Space를 leader로

" 탐색
nnoremap <leader>e  :WexplorerToggle<CR>
nnoremap <leader>ff  :WfindFiles<CR>
nnoremap <leader>fb  :WfindBuffers<CR>
nnoremap <leader>fh :Whistory<CR>

" Harpoon
nnoremap <leader>ha :WharpoonAdd<CR>
nnoremap <leader>hl :WharpoonList<CR>
nnoremap <leader>h1 :call wplus#harpoon#jump(1)<CR>
nnoremap <leader>h2 :call wplus#harpoon#jump(2)<CR>

" AI
vnoremap <leader>ar :WaiReview<CR>
vnoremap <leader>ae :WaiExplain<CR>
vnoremap <leader>af :WaiRefactor<CR>
nnoremap <leader>am :WaiCommitMsg<CR>
nnoremap <leader>at :WaiToggleSuggest<CR>

" 코드 실행
nnoremap <leader>rr :Wrun<CR>
nnoremap <leader>rb :Wbuild<CR>
nnoremap <leader>rt :Wtest<CR>

" 프로젝트
nnoremap <leader>sc :WscratchToggle<CR>
nnoremap <leader>pe :WprojectEdit<CR>

" Git
nnoremap <leader>gd :WdiffviewFile<CR>
nnoremap <leader>gD :WdiffviewRepo<CR>

" 검색
nnoremap <leader>fg :Wgrep <C-r><C-w><CR>

" 버퍼·창
nnoremap <leader>bd :Bdelete<CR>
nnoremap <leader>tt :WplusTerminalToggle<CR>

" 창 이동
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
```

---

## Windows 사용 시 주의사항

vim-wplus는 Windows(gvim / 터미널 Vim)에서 정상 동작하도록 만들어졌습니다.

### `&shell` 설정

`format.vim`, `gitgutter.vim`, `diffview.vim` 등은 `shellescape()` + `system()`으로 외부 명령을 실행합니다.  
이 조합은 `&shell=cmd.exe` 기준으로 검증되었습니다.

`.vimrc`에서 `&shell`을 PowerShell 등으로 바꾸면 공백·특수문자 경로에서 명령이 깨질 수 있으니,  
위 기능을 사용한다면 `&shell`을 `cmd.exe`로 유지하세요.

### 경로 표기

```vim
" Windows에서는 슬래시(/) 사용 권장 — 백슬래시(\)도 동작하지만 escape 문제 방지
set runtimepath+=C:/Users/<user>/vimfiles/pack/user/start/vim-wplus
```

---

## 문제 해결

### E492: Not an editor command

플러그인이 로드되지 않은 경우입니다.

```vim
" 1. runtimepath 확인
:set runtimepath?
" vim-wplus 경로가 포함되어 있어야 합니다

" 2. 로드 확인
:echo exists(':WexplorerToggle')   " 2여야 함
:echo exists('*wplus#explorer#toggle')   " 1이어야 함

" 3. 수동 로드
set runtimepath+=~/.vim/pack/user/start/vim-wplus
source ~/.vim/pack/user/start/vim-wplus/plugin/wplus.vim
```

### AI: API key not configured

```vim
let g:wplus_ai_api_key = 'sk-...'
" 또는 환경 변수
let g:wplus_ai_api_key = $OPENAI_API_KEY
```

### Ghost Text가 표시되지 않음

1. `textprop` 지원 확인: `:echo has('textprop')` → `1`이어야 함
2. 모델 설정 확인: `let g:wplus_ai_model = 'gpt-4o'`
3. Insert 모드에서 잠시 기다려야 함 (기본 500ms)
4. 디버그 모드: `let g:wplus_ai_suggest_debug = 1`

### LSP가 시작되지 않음

```vim
" 지원 파일타입: go, c, cpp, python, dart, rust
" 해당 언어 파일을 열었을 때 자동 시작
:echo exists('*wplus#lsp#request')   " 1이어야 함

" 디버그 로그 활성화
let g:wplus_lsp_log_enabled = 1
" 프로젝트 루트에 lsp.log 파일 생성됨
```

### 대용량 파일에서 성능 저하

```vim
let g:wplus_finder_fuzzy_limit  = 5000   " finder 매칭 제한
let g:wplus_ai_suggest_enabled  = 0      " AI 자동완성 비활성화
let g:wplus_illuminate_delay    = 500    " 심볼 하이라이트 지연 증가
```

### Harpoon 슬롯이 저장되지 않음

`~/.vim/harpoon/` 디렉토리가 생성되는지 확인:

```vim
:echo isdirectory(expand('~/.vim/harpoon'))
" 0이면: :call mkdir(expand('~/.vim/harpoon'), 'p')
```

---

## 모듈 비활성화

원하는 모듈만 비활성화할 수 있습니다. `plugin/wplus.vim` 로드 **전**에 선언해야 합니다.

```vim
" 자주 비활성화하는 모듈 예시
let g:wplus_blame_enabled      = 0   " 인라인 blame 끄기 (느린 환경)
let g:wplus_indent_enabled     = 0   " 들여쓰기 가이드 끄기
let g:wplus_ai_enabled         = 0   " AI 완전 비활성화
let g:wplus_session_enabled    = 0   " 자동 세션 끄기
let g:wplus_fold_enabled       = 0   " 자동 폴드 끄기
```

> 전체 설정 레퍼런스 → **[docs/config.md](docs/config.md)**

---

## 추가 정보

| 문서 | 내용 |
|------|------|
| [README.md](README.md) | 모듈 목록 개요 |
| [docs/modules/editing.md](docs/modules/editing.md) | commentary, surround, pairs, textobj … |
| [docs/modules/navigation.md](docs/modules/navigation.md) | finder, explorer, harpoon, history … |
| [docs/modules/git.md](docs/modules/git.md) | gitgutter, blame, diffview, conflict |
| [docs/modules/ui.md](docs/modules/ui.md) | statusline, tabline, indent … |
| [docs/modules/code.md](docs/modules/code.md) | lsp, run, fold, format, marks … |
| [docs/ai.md](docs/ai.md) | AI 어시스턴트 심화 가이드 |
| [docs/config.md](docs/config.md) | 전체 설정 레퍼런스 |
| [docs/keymaps.md](docs/keymaps.md) | 기본 단축키 치트시트 |
| [CHANGE_LOG.md](CHANGE_LOG.md) | 변경 이력 |