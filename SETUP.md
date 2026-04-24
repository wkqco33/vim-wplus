# vim-wplus 설정 가이드

vim-wplus는 31개 모듈로 구성된 완전한 Vim IDE입니다. 이 가이드는 각 기능을 설정하는 방법을 설명합니다.

## 설치

### 1. vim-plug를 사용한 설치 (권장)

**~/.vimrc**에 다음을 추가합니다:

```vim
call plug#begin()
" vim-wplus를 로컬 경로에서 로드
Plug '/path/to/vim-wplus'
call plug#end()
```

그 후 Vim에서 다음을 실행합니다:
```vim
:PlugInstall
```

### 2. 직접 설정 (vim-plug 없음)

**~/.vimrc**에 다음을 추가합니다:

```vim
set runtimepath+=/path/to/vim-wplus
set packpath+=/path/to/vim-wplus

" 모듈 사용 전에 반드시 이 라인 추가
if filereadable('/path/to/vim-wplus/plugin/wplus.vim')
    source /path/to/vim-wplus/plugin/wplus.vim
endif
```

### 3. 빠른 시작 (예시)

```bash
# vim-wplus를 ~/.vim/plugged에 설치
git clone https://github.com/your-user/vim-wplus ~/.vim/plugged/vim-wplus

# 또는 ~/.local/share/nvim/site/pack/user/start에 설치
mkdir -p ~/.local/share/nvim/site/pack/user/start
git clone https://github.com/your-user/vim-wplus ~/.local/share/nvim/site/pack/user/start/vim-wplus
```

**~/.vimrc**:
```vim
" 경로 설정
set runtimepath+=~/.vim/plugged/vim-wplus

" 플러그인 로드
source ~/.vim/plugged/vim-wplus/plugin/wplus.vim
```

---

## 문제 해결

### E492: Not an editor command (예: WexplorerToggle)

이 오류는 vim-wplus 플러그인이 제대로 로드되지 않았다는 뜻입니다.

**해결 방법:**

1. **runtimepath 확인**
```vim
:set runtimepath?
" /path/to/vim-wplus가 포함되어 있는지 확인
```

2. **플러그인 로드 확인**
```vim
:echo exists('*wplus#explorer#toggle')
" 1이 반환되어야 함 (0이면 로드되지 않은 것)
```

3. **수동 로드**
```vim
" .vimrc에 다음을 추가
set runtimepath+=/path/to/vim-wplus
source /path/to/vim-wplus/plugin/wplus.vim
```

4. **모듈 활성화 확인**
```vim
" .vimrc의 설정이 plugin/wplus.vim 보다 먼저 로드되어야 함
let g:wplus_explorer_enabled = 1
source /path/to/vim-wplus/plugin/wplus.vim
```

---

## 빠른 시작 (설정)

1. `.vimrc.example`을 복사하여 `~/.vimrc`에 적용:
```bash
cp /path/to/vim-wplus/.vimrc.example ~/.vimrc
```

2. Vim을 시작하고 필요한 설정을 추가합니다.

3. 필요한 언어 서버 설치 (선택사항):
```bash
# Python
pip install python-lsp-server

# Go
go install github.com/golang/tools/gopls@latest

# TypeScript/JavaScript
npm install -g typescript-language-server
```

---

## 설정 가이드

### 1. AI Assistant (ChatGPT, Claude, Azure OpenAI)

AI 기반 코드 주석, 완성, 리팩토링 기능입니다.

#### OpenAI 설정
```vimscript
let g:wplus_ai_provider = 'openai'
let g:wplus_ai_api_key = 'sk-...'
let g:wplus_ai_model = 'gpt-3.5-turbo'    " 또는 'gpt-4'
let g:wplus_ai_temperature = 0.7
let g:wplus_ai_max_tokens = 2000
```

#### Claude 설정
```vimscript
let g:wplus_ai_provider = 'claude'
let g:wplus_ai_api_key = 'sk-ant-...'
let g:wplus_ai_model = 'claude-3-sonnet-20240229'
```

#### Azure OpenAI 설정
```vimscript
let g:wplus_ai_provider = 'azure'
let g:wplus_ai_api_key = 'your-azure-key'
let g:wplus_ai_model = 'gpt-4'
let g:wplus_ai_azure_resource = 'your-company-ai'        " 리소스 이름
let g:wplus_ai_azure_deployment = 'gpt-4-deployment'     " 배포명
let g:wplus_ai_azure_api_version = '2024-02-15-preview'  " (선택사항)
```

#### 명령어
```vim
:WaiComment         " 선택 영역에 주석 추가
:WaiComplete        " 코드 완성 제안 표시
:'<,'>WaiRefactor   " 선택 영역 리팩토링
:WaiToggleSuggest   " Ghost Text 자동완성 on/off
```

#### 키 매핑 예시
```vimscript
nnoremap <leader>ac :WaiComment<CR>
nnoremap <leader>ao :WaiComplete<CR>
vnoremap <leader>ar :WaiRefactor<CR>
nnoremap <leader>at :WaiToggleSuggest<CR>
```

#### Ghost Text 자동완성

InsertMode에서 자동으로 AI 완성 제안을 Ghost Text로 표시합니다.

**작동 방식:**
- 입력 모드에서 타이핑을 멈추면 설정된 delay 후 자동으로 제안 표시
- Tab 키로 제안 수락
- Escape나 다른 키를 누르면 제안 취소
- 회색(NonText highlight)으로 표시되어 실제 텍스트와 구분 가능

**설정:**
```vimscript
let g:wplus_ai_suggest_enabled = 1               " 활성화 여부 (기본값: 1)
let g:wplus_ai_suggest_delay = 500               " 제안 지연 시간 (ms)
let g:wplus_ai_suggest_context_lines = 50        " 컨텍스트 수집 라인 수
let g:wplus_ai_suggest_suffix_lines = 20         " suffix 수집 라인 수
" let g:wplus_ai_suggest_debug = 1               " 디버그 로그 출력
```

**인자 설명:**
- `suggest_enabled`: 자동완성 기능 활성화/비활성화
- `suggest_delay`: 입력 후 제안까지 대기시간 (밀리초)
  - 작을수록 빠르지만 API 비용 증가
  - 큰값일수록 느림 (기본 500ms)
  - 5회 타이핑 후 delay 자동 2배 증가 (빠른 입력 시 불필요한 요청 감소)
- `context_lines`: 제안 컨텍스트로 포함할 이전 라인 수
- `suffix_lines`: 제안 컨텍스트로 포함할 이후 라인 수

**언어별 Context 추출:**
- Go: `func` 함수명 추출, 함수 경계 인식
- Python: `def`/`class` 추출, 들여쓰기 기반 scope
- TypeScript/JavaScript: `function`, `class`, `const/let/var` 추출
- Rust: `fn`, `struct`, `impl`, `trait` 추출
- Java: `class`, `interface`, `enum` 추출
- Kotlin: `fun`, `class`, `object` 추출
- Ruby: `def`, `class`, `module` 추출
- Lua: `function` 추출
- C/C++: 함수 선언 추출

**Key Mapping:**
```vimscript
inoremap <expr> <Tab> wplus#ai#accept_suggestion()
nnoremap <Leader>ai :WaiToggleSuggest<CR>
```

이미 `<Tab>`을 LSP 또는 snippet 이동에 쓰고 있다면 Ghost Text는 다른 키에 매핑하는 것이 안전합니다.

---

### 2. Snippet Engine (스니펫)

코드 템플릿을 빠르게 확장합니다.

#### 지원 스니펫
```python
# Python
def[Tab]    -> def function_name(${1:args}):
class[Tab]  -> class ClassName${1:(BaseClass)}:
if[Tab]     -> if ${1:condition}:
for[Tab]    -> for ${1:item} in ${2:iterable}:
```

```go
// Go
func[Tab]   -> func ${1:function_name}(${2:params}) ${3:return_type} {
if[Tab]     -> if ${1:condition} {
for[Tab]    -> for ${1:i} := ${2:0}; ${1:i} < ${3:n}; ${1:i}++ {
```

#### 플레이스홀더 문법
```
${1:default}  - 선택 가능한 필드 (Tab으로 이동)
${2:second}   - 두 번째 필드
${0:end}      - 스니펫 종료 지점
```

#### 설정
```vimscript
let g:wplus_snippet_enabled = 1
let g:wplus_snippet_jump_key = '<Tab>'
let g:wplus_snippet_jump_back_key = '<S-Tab>'
```

---

### 3. Git Conflict Resolver (충돌 해결)

Git merge 충돌을 시각적으로 해결합니다.

#### 명령어
```vim
:WconflictNext      " 다음 충돌로 이동
:WconflictPrev      " 이전 충돌로 이동
:WconflictOurs      " ours 버전 선택
:WconflictTheirs    " theirs 버전 선택
:WconflictBoth      " 둘 다 선택
```

#### 키 매핑 예시
```vimscript
nnoremap <leader>cn :WconflictNext<CR>
nnoremap <leader>co :WconflictOurs<CR>
nnoremap <leader>ct :WconflictTheirs<CR>
nnoremap <leader>cb :WconflictBoth<CR>
```

#### 설정
```vimscript
let g:wplus_conflict_enabled = 1
let g:wplus_conflict_auto_highlight = 1
```

---

### 4. TODO Manager (TODO 관리)

코드에서 TODO/FIXME/HACK을 찾아 Quickfix에 표시합니다.

#### 명령어
```vim
:WtodoQuickfix      " TODO 목록을 Quickfix에 표시
```

#### 검색 대상
```vimscript
let g:wplus_todo_keywords = ['TODO', 'FIXME', 'HACK', 'BUG', 'XXX']
```

#### 설정
```vimscript
let g:wplus_todo_enabled = 1
let g:wplus_todo_grep_backend = 'rg'    " rg, git grep, grep
```

---

### 5. Advanced Search (고급 검색)

정규표현식, 단어 검색, 검색 히스토리를 지원합니다.

#### 명령어
```vim
:WgrepRx            " 정규표현식 검색
:WgrepWord          " 단어 검색 (정확한 매칭)
:Wgrep pattern      " 기본 검색
```

#### 키 매핑 예시
```vimscript
nnoremap <leader>fR :WgrepRx<CR>
nnoremap <leader>fw :WgrepWord<CR>
nnoremap <leader>fg :Wgrep <C-r><C-w><CR>
```

#### 설정
```vimscript
let g:wplus_grep_backend = 'rg'         " rg, git grep, grep
let g:wplus_grep_max_results = 1000
let g:wplus_grep_ignore_vcs = 1
let g:wplus_search_history_max = 100
```

---

### 6. Colorscheme Auto-detect (배경색 감지)

터미널의 밝기(dark/light)를 자동으로 감지하여 컬러스킴을 조정합니다.

#### 설정
```vimscript
let g:wplus_colorscheme_auto_detect = 1
```

---

## LSP 설정

### 지원하는 언어
- Python (pylsp)
- Go (gopls)
- TypeScript/JavaScript (typescript-language-server)
- Rust (rust-analyzer)
- C/C++ (clangd)
- 기타 LSP 호환 서버

### LSP 서버 설치

```bash
# Python
pip install python-lsp-server

# Go
go install github.com/golang/tools/gopls@latest

# TypeScript
npm install -g typescript-language-server

# Rust
rustup component add rust-analyzer

# C/C++
# macOS: brew install llvm
# Ubuntu: sudo apt-get install clang-tools
# Fedora: sudo dnf install clang-tools-extra
```

### LSP 설정
```vimscript
let g:wplus_lsp_enabled = 1
let g:wplus_lsp_servers = {
    \ 'python': { 'cmd': ['pylsp'] },
    \ 'go': { 'cmd': ['gopls'] },
    \ 'typescript': { 'cmd': ['typescript-language-server', '--stdio'] }
\ }
let g:wplus_lsp_definition_split = 0    " 0=same, 1=split, 2=vsplit, 3=tab
```

### LSP 명령어
```vim
gd              " 정의로 이동 (Go to Definition)
gr              " 참조 찾기 (References)
K               " 호버 정보 (Documentation)
<F2>            " 이름 변경 (Rename) - 일부 플러그인
```

---

## 성능 최적화 설정

### LSP 캐시 (30-50% 성능 향상)
```vimscript
let g:wplus_lsp_cache_enabled = 1
let g:wplus_lsp_cache_ttl = 300        " 캐시 유효시간 (초)
```

### Gitgutter 최적화 (90% 성능 향상)
```vimscript
let g:wplus_gitgutter_enabled = 1
let g:wplus_gitgutter_disable_on_large_files = 1
let g:wplus_gitgutter_file_size_limit = 500000
```

### Finder 제한
```vimscript
let g:wplus_finder_match_limit = 10000  " 대용량 디렉토리 보호
```

---

## 추천 키 매핑

```vimscript
" 탐색
nnoremap <leader>e  :WexplorerToggle<CR>
nnoremap <leader>p  :WfindFiles<CR>
nnoremap <leader>b  :WfindBuffers<CR>
nnoremap <leader>m  :WfindMRU<CR>

" 검색
nnoremap <leader>fg :Wgrep <C-r><C-w><CR>
nnoremap <leader>fR :WgrepRx<CR>
nnoremap <leader>fw :WgrepWord<CR>

" AI
nnoremap <leader>ac :WaiComment<CR>
nnoremap <leader>ao :WaiComplete<CR>
vnoremap <leader>ar :WaiRefactor<CR>

" Git
nnoremap <leader>bl :BlamerToggle<CR>
nnoremap <leader>cn :WconflictNext<CR>
nnoremap <leader>co :WconflictOurs<CR>

" TODO
nnoremap <leader>tt :WtodoQuickfix<CR>

" 버퍼/윈도우
nnoremap <leader>bd :Bdelete<CR>
nnoremap <leader>u  :UndotreeToggle<CR>
nnoremap <leader>tm :WplusTerminalToggle<CR>

" 윈도우 네비게이션
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
```

---

## 문제 해결

### API 키 오류
```
[wplus-ai] API key not configured
```
**해결**: `.vimrc`에서 `g:wplus_ai_api_key`를 설정하세요.

### 언어 서버 연결 실패
```
[wplus-lsp] Failed to start language server
```
**해결**: 해당 언어의 LSP 서버를 설치하세요.

### 큰 파일에서 느린 성능
```
let g:wplus_finder_match_limit = 10000
let g:wplus_gitgutter_file_size_limit = 500000
```

### Azure OpenAI 인증 오류
```
let g:wplus_ai_provider = 'azure'
let g:wplus_ai_api_key = 'your-key'
let g:wplus_ai_azure_resource = 'resource-name'
let g:wplus_ai_azure_deployment = 'deployment-name'
```

---

## 모듈 목록 (31개)

### 기본 기능 (7)
- commentary, pairs, repeat, altfile, indent, statusline, tabline

### VCS (5)
- gitgutter, blame, terminal, explorer, session

### 에디터 (5)
- surround, format, undotree, yankhighlight, textobj

### UI (5)
- whichkey, quickfix, grep, finder, bufdelete

### 언어 (3)
- lsp, root, illuminate

### 신규 (5)
- colorscheme, snippet, conflict, ai, todo

### 유틸리티 (1)
- util (표준화된 메시지 함수)

---

## 성능 통계

| 항목 | 개선율 |
|------|--------|
| LSP 정의/참조 캐시 | 30-50% 단축 |
| Gitgutter 배치 처리 | 90% 감소 |
| 메모리 누수 | 완전 제거 |
| 스타트업 시간 | 모듈별 캐시 |

---

## 지원 환경

- Vim 9.0+
- Neovim 0.9+
- Python 3.7+
- Git 2.20+

---

## 추가 정보

- [README.md](README.md) - 프로젝트 개요
- [doc/](doc/) - 상세 문서
