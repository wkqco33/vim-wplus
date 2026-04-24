# vim-wplus

외부 의존성 없는 Vim 올인원 플러그인.  
31개 모듈로 구성된 완전한 Vim IDE (AI 어시스턴트, 스니펫, Git 충돌 해결 포함).

**요구사항**: Vim 9.1+ (`+job +channel +popupwin +signs +textprop`)

---

## 목차

- [설치](#설치)
- [주요 기능](#주요-기능)
- [대체 플러그인 목록](#대체-플러그인-목록)
- [모듈 가이드](#모듈-가이드)
  - [commentary — 주석 토글](#commentary--주석-토글)
  - [surround — 괄호·따옴표 조작](#surround--괄호따옴표-조작)
  - [pairs — 자동 괄호 완성](#pairs--자동-괄호-완성)
  - [textobj — 텍스트 오브젝트](#textobj--텍스트-오브젝트)
  - [format — 스마트 포매터](#format--스마트-포매터)
  - [gitgutter — Sign 컬럼 diff](#gitgutter--sign-컬럼-diff)
  - [blame — 인라인 Git Blame](#blame--인라인-git-blame)
  - [statusline — 상태바](#statusline--상태바)
  - [tabline — 버퍼 탭라인](#tabline--버퍼-탭라인)
  - [indent — 들여쓰기 가이드](#indent--들여쓰기-가이드)
  - [illuminate — 심볼 하이라이트](#illuminate--심볼-하이라이트)
  - [yankhighlight — 복사 피드백](#yankhighlight--복사-피드백)
  - [undotree — Undo 히스토리](#undotree--undo-히스토리)
  - [whichkey — 키 힌트 팝업](#whichkey--키-힌트-팝업)
  - [bufdelete — 버퍼 삭제](#bufdelete--버퍼-삭제)
  - [quickfix — Quickfix 강화](#quickfix--quickfix-강화)
  - [finder — 고속 퍼지 파인더](#finder--고속-퍼지-파인더)
  - [explorer — 사이드바 탐색기](#explorer--사이드바-탐색기)
  - [grep — 고속 검색](#grep--고속-검색)
  - [root — 프로젝트 루트 자동 인식](#root--프로젝트-루트-자동-인식)
  - [terminal — 터미널 토글](#terminal--터미널-토글)
  - [lsp — 경량 LSP 연동](#lsp--경량-lsp-연동)
  - [altfile — 헤더↔소스 전환](#altfile--헤더소스-전환)
  - [repeat — . 반복 지원](#repeat---반복-지원)
  - [ai — AI 어시스턴트](#ai--ai-어시스턴트-openai--claude--azure)
  - [snippet — 스니펫 엔진](#snippet--스니펫-엔진)
  - [conflict — Git 충돌 해결](#conflict--git-충돌-해결)
  - [todo — TODO 관리](#todo--todo-관리)
  - [colorscheme — 배경색 자동 감지](#colorscheme--배경색-자동-감지)
- [설정 가이드](#설정-가이드)
- [모듈 비활성화](#모듈-비활성화)
- [전체 설정 레퍼런스](#전체-설정-레퍼런스)

---

## 설치

### vim-plug (로컬 경로)

```vim
Plug '/path/to/vim-wplus'
```

### vim-plug (GitHub)

```vim
Plug 'your-user/vim-wplus'
```

---

## 대체 플러그인 목록

| 모듈 | 대체 플러그인 |
|------|--------------|
| `commentary` | tpope/vim-commentary |
| `surround` | tpope/vim-surround |
| `pairs` | jiangmiao/auto-pairs |
| `textobj` | kana/vim-textobj-indent, vim-textobj-parameter |
| `format` | vim-autoformat, 각 언어별 포매터 플러그인 |
| `gitgutter` | airblade/vim-gitgutter |
| `blame` | APZelos/blamer.nvim |
| `statusline` | vim-airline / lightline |
| `tabline` | vim-airline tabline |
| `indent` | Yggdroot/indentLine |
| `illuminate` | RRethy/vim-illuminate |
| `yankhighlight` | machakann/vim-highlightedyank |
| `undotree` | mbbill/undotree |
| `whichkey` | liuchengxu/vim-which-key |
| `bufdelete` | moll/vim-bbye |
| `quickfix` | romainl/vim-qf |
| `finder` | junegunn/fzf.vim |
| `explorer` | preservim/nerdtree |
| `grep` | mhinz/vim-grepper |
| `root` | airblade/vim-rooter |
| `terminal` | voldikss/vim-floaterm (비슷한 기능) |
| `lsp` | yegappan/lsp (Vim 9용 LSP) |
| `altfile` | vim-scripts/a.vim |
| `repeat` | tpope/vim-repeat |

---

## 모듈 가이드

### commentary — 주석 토글

| 키 | 모드 | 동작 |
|----|------|------|
| `gcc` | Normal | 현재 줄 주석 토글 |
| `gc{motion}` | Normal | motion 범위 주석 토글 (예: `gc3j`, `gcip`) |
| `gc` | Visual | 선택 범위 주석 토글 |

언어별 주석 기호는 `&commentstring` 에서 자동으로 읽어옵니다.

---

### surround — 괄호·따옴표 조작

| 키 | 동작 | 예시 |
|----|------|------|
| `ys{motion}{char}` | 감싸기 | `ysiw"` → `hello` → `"hello"` |
| `yss{char}` | 현재 줄 감싸기 | `yss(` → `( line )` |
| `cs{old}{new}` | 변경 | `cs"'` → `"hello"` → `'hello'` |
| `ds{char}` | 제거 | `ds"` → `"hello"` → `hello` |
| `S{char}` | Visual 선택 감싸기 | `viwS(` → `(hello)` |

**지원 문자**: `( ) [ ] { } < > " ' \`` 및 HTML 태그 (`t`)

---

### pairs — 자동 괄호 완성

| 동작 | 설명 |
|------|------|
| `(` 입력 | `()` 자동 완성, 커서를 안에 위치 |
| `"` 입력 | `""` 자동 완성 |
| `<BS>` | 빈 쌍 `()` 안에서 backspace → 양쪽 모두 삭제 |
| `)` 입력 | 닫는 괄호가 이미 있으면 skip |

지원: `( ) [ ] { } " ' \``

---

### textobj — 텍스트 오브젝트

#### 들여쓰기 블록 (`ii` / `ai`)

| 키 | 동작 |
|----|------|
| `ii` | 현재 들여쓰기 수준의 블록 선택 (Python 함수 바디 등) |
| `ai` | 들여쓰기 블록 + 위 헤더 줄 포함 (`def foo():` 포함) |

`dii`, `vii`, `cii`, `yii`, `>ii` 등 모든 operator와 조합 가능.

#### 함수 인자 (`ia` / `aa`)

```
function(arg1, arg2, arg3)
               ^^^^
               ia (inner argument)
```

| 키 | 동작 |
|----|------|
| `ia` | 인자 안쪽 (공백 제외) |
| `aa` | 인자 + 인접 쉼표 포함 |

중첩 괄호를 인식하므로 `f(a, g(b, c), d)` 에서도 올바르게 동작합니다.

---

### format — 스마트 포매터

`Alt+Shift+F` 로 현재 파일을 언어에 맞는 포매터로 자동 정렬합니다.

**우선순위 (순서대로 폴백)**:
1. **coc/LSP** — `CocHasProvider('format')` 가 true이면 LSP 포매터 사용
2. **외부 도구** — 아래 도구가 PATH에 있으면 stdin 포맷 실행
3. **ALE** — `:ALEFix` 실행
4. **vim 내장** — `gg=G` (indent 기반)

**언어별 외부 도구**:

| 언어 | 도구 |
|------|------|
| Go | `goimports` (없으면 `gofmt`) |
| Rust | `rustfmt` |
| Python | `autopep8 -` |
| C / C++ | `clang-format` |
| JS / TS / JSON / YAML / HTML / CSS | `prettier --stdin-filepath` |
| Shell | `shfmt` |
| Lua | `stylua -` |

| 키 | 모드 | 동작 |
|----|------|------|
| `<M-F>` (`Alt+Shift+F`) | Normal / Insert | 파일 전체 포맷 |
| `<M-F>` | Visual | 선택 범위 포맷 |

포매터 실패 시 자동으로 undo하여 버퍼를 보호합니다.

---

### gitgutter — Sign 컬럼 diff

git 변경사항을 sign 컬럼에 실시간으로 표시합니다 (비동기).

| 기호 | 의미 |
|------|------|
| `┃` (녹색) | 추가된 줄 |
| `┃` (노란색) | 수정된 줄 |
| `▁` (빨간색) | 삭제된 줄 |

파일 저장 및 `CursorHold` 이벤트에 자동 갱신됩니다.

**커스터마이즈**:
```vim
let g:wplus_gitgutter_sign_add    = '+'
let g:wplus_gitgutter_sign_change = '~'
let g:wplus_gitgutter_sign_delete = '_'
```

---

### blame — 인라인 Git Blame

커서가 있는 줄 끝에 커밋 정보를 흐린 색으로 표시합니다 (text-property 기반, 비동기).

| 키 | 동작 |
|----|------|
| `:BlamerToggle` | blame 표시 켜기/끄기 |

**설정**:

```vim
let g:wplus_blame_delay       = 500          " 표시까지 지연 (ms)
let g:wplus_blame_prefix      = '   '        " 줄 끝 앞 여백
let g:wplus_blame_template    = '<author>, <date> • <summary>'
let g:wplus_blame_date_format = '%y/%m/%d'
```

템플릿 변수: `<author>`, `<date>`, `<summary>`, `<hash>`

---

### statusline — 상태바

```
 NORMAL  main  src/main.go  [+]      E:1 W:2   go  UTF-8   42:10  85%
```

표시 항목: 모드 · git 브랜치 · 파일명 · 수정/RO 플래그 · coc 진단 수 · filetype · 인코딩 · 커서 위치 · 스크롤 %

---

### tabline — 버퍼 탭라인

열려 있는 버퍼를 상단 탭라인에 번호와 함께 표시합니다.

```
  1 init.vim   2 wplus.vim ● 3 README.md
```

`●` 표시: 저장되지 않은 버퍼

---

### indent — 들여쓰기 가이드

들여쓰기 레벨마다 세로선을 표시합니다 (conceal 기반, 성능 영향 최소).

```vim
let g:wplus_indent_char       = '▏'          " 기본 기호
let g:wplus_indent_ft_exclude = ['help', 'nerdtree', 'undotree']
```

---

### illuminate — 심볼 하이라이트

커서 아래 단어와 동일한 심볼을 버퍼 내에서 자동으로 하이라이트합니다.

```vim
let g:wplus_illuminate_delay    = 200        " 지연 (ms)
let g:wplus_illuminate_ft_block = ['help', 'nerdtree']
```

---

### yankhighlight — 복사 피드백

`y` 계열 명령으로 복사할 때 선택 영역이 250ms 동안 강조됩니다.

```vim
let g:wplus_yank_duration = 250              " 강조 지속 시간 (ms)
```

하이라이트 색상 변경:
```vim
highlight WplusYankHL guibg=#fabd2f guifg=#282828
```

---

### undotree — Undo 히스토리

```
<leader>u  — 사이드바 토글
```

사이드바에서:

| 키 | 동작 |
|----|------|
| `j` / `k` | 이전/다음 undo 상태로 이동 |
| `<CR>` | 해당 상태로 undo/redo |
| `q` | 닫기 |

```vim
let g:wplus_undotree_width = 30              " 사이드바 너비
```

---

### whichkey — 키 힌트 팝업

`<leader>` 를 누른 후 `timeoutlen` ms 이상 기다리면 등록된 키 매핑 목록이 팝업으로 표시됩니다.

커스텀 설명 등록:
```vim
call wplus#whichkey#register('w', 'save file')
call wplus#whichkey#register('q', 'quit')
```

---

### bufdelete — 버퍼 삭제

기본 `:bd` 는 창까지 닫히지만, 이 모듈은 **창을 유지**하고 버퍼만 닫습니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>bd` / `:Bdelete` | 현재 버퍼 닫기 (창 유지) |
| `<leader>bD` / `:Bwipeout` | 버퍼 wipeout (히스토리 포함 제거) |
| `:Bdelete!` | 미저장 버퍼 강제 닫기 |

---

### quickfix — Quickfix 강화

| 키 | 동작 |
|----|------|
| `<leader>xq` | Quickfix 패널 토글 |
| `<leader>xl` | Location list 토글 (ALE/coc 에러 목록) |
| `]q` / `[q` | 다음/이전 에러 (끝에서 wrap) |
| `]Q` / `[Q` | 마지막/첫 번째 에러로 이동 |
| `]l` / `[l` | Location list 다음/이전 |
| `<leader>xr` | 프로젝트 전체 치환 (quickfix 항목 기반) |

**프로젝트 전체 치환 워크플로우**:
```
1. :Rg <검색어>        — fzf로 검색 후 <C-a><Enter>로 전체 quickfix에 추가
2. <leader>xr          — 치환 패턴 입력 → 모든 파일에 자동 적용
```

치환 실행 전 `Apply`, `Confirm`, `Preview` 모드를 선택할 수 있습니다.

---

### finder — 고속 퍼지 파인더

Vim 9의 `matchfuzzy()`와 팝업 윈도우를 사용하여 파일, 버퍼, 최근 파일을 빠르게 찾습니다.

| 키 | 동작 |
|----|------|
| `<leader>p` | 파일 찾기 (Files) |
| `<leader>b` | 버퍼 찾기 (Buffers) |
| `<leader>m` | 최근 파일 찾기 (MRU) |

**팝업 내 키 매핑**:
- `Ctrl+n` / `Down`: 다음 항목
- `Ctrl+p` / `Up`: 이전 항목
- `Enter`: 선택 항목 열기
- `Esc`: 닫기

---

### explorer — 사이드바 탐색기

사이드바에서 프로젝트 파일을 관리합니다.

| 키 | 동작 |
|----|------|
| `<leader>e` | 사이드바 토글 |

**탐색기 내 키 매핑**:
- `Enter`: 파일 열기 또는 디렉토리 이동
- `a`: 새 파일/디렉토리 생성 (디렉토리는 이름 끝에 `/` 붙임)
- `d`: 삭제
- `r`: 이름 변경
- `R`: 새로고침
- `q`: 닫기

대용량 디렉토리 보호를 위해 최대 항목 수와 최대 재귀 깊이를 제한합니다.

---

### grep — 고속 검색

`ripgrep`(rg) 또는 `git grep`을 활용하여 프로젝트 전체를 빠르게 검색하고 Quickfix 창에 띄웁니다.

| 키 / 명령 | 모드 | 동작 |
|-----------|------|------|
| `:Wgrep {pattern}` | Normal | 패턴 검색 후 Quickfix 오픈 |
| `<leader>fg` | Normal | 커서 아래 단어로 프로젝트 검색 |
| `<leader>fg` | Visual | 선택 영역으로 프로젝트 검색 |

`rg`가 설치되어 있으면 `rg`를, 없으면 `git grep`을 우선적으로 사용합니다.

---

### root — 프로젝트 루트 자동 인식

파일을 열 때 상위 디렉토리에서 `.git`, `go.mod`, `Makefile` 등을 찾아 자동으로 작업 디렉토리(`lcd`)를 변경합니다.

- 별도의 설정 없이 자동으로 동작하며, 프로젝트 루트 기반의 검색 및 터미널 실행을 편리하게 해줍니다.

---

### terminal — 터미널 토글

하단 스플릿 창으로 터미널을 빠르게 열고 닫습니다.

| 키 / 명령 | 모드 | 동작 |
|-----------|------|------|
| `<leader>tt` / `:WplusTerminalToggle` | Normal | 터미널 토글 |
| `<Esc><Esc>` | Terminal | 터미널 모드 탈출 (Normal 모드로) |

---

### lsp — 경량 LSP 연동

복잡한 설정 없이 `gopls` 등 언어 서버의 핵심 기능을 활용합니다.

| 키 | 동작 |
|----|------|
| `gd` | 정의 이동 (Go to Definition) |
| `gr` | 참조 찾기 (References) |
| `K` | 심볼 정보 요약 (Hover) |

진단이 들어오면 sign 컬럼에 `E`, `W`, `I`, `H`를 표시하고, 현재 버퍼의 오류/경고 수를 상태줄의 `E:n W:n` 형식으로 보여줍니다.

기본 `signcolumn`은 호환성을 위해 `yes`를 사용합니다. 이미 사용자가 `signcolumn`을 직접 설정했다면 그 값을 유지합니다.

Go(`gopls`)를 우선 지원하며, 다른 언어는 `ctags` 및 `keywordprg`로 폴백됩니다.

---

### altfile — 헤더↔소스 전환

| 명령 | 동작 |
|------|------|
| `:A` | 같은 창에서 헤더↔소스 전환 |
| `:AV` | 수직 분할로 열기 |
| `:AS` | 수평 분할로 열기 |

`.h ↔ .c`, `.h ↔ .cpp`, `.hpp ↔ .cpp` 쌍을 지원합니다.

---

### repeat — . 반복 지원

vim-wplus 내부 명령들이 `.` 로 반복 가능하도록 `vim-repeat` API 호환 레이어를 제공합니다. 다른 플러그인에서도 사용 가능:

```vim
call wplus#repeat#set("\<Plug>MyAction", v:count)
```

---

### ai — AI 어시스턴트 (OpenAI, Claude, Azure)

ChatGPT, Claude, Azure OpenAI를 지원하는 AI 코드 어시스턴트입니다.

#### 명령어

| 명령 | 모드 | 동작 |
|------|------|------|
| `:WaiComment` | Normal | 현재 코드에 주석 생성 |
| `:WaiComplete` | Normal | 다음 줄 코드 완성 제안 |
| `:'<,'>WaiRefactor` | Visual | 선택 범위 리팩토링 제안 |
| `:WaiToggleSuggest` | Normal | Ghost Text 자동완성 토글 |

#### 설정

```vim
" 공급자 선택: 'openai' | 'claude' | 'azure'
let g:wplus_ai_provider = 'openai'
let g:wplus_ai_api_key = 'sk-...'                    " 필수
let g:wplus_ai_model = 'gpt-3.5-turbo'
let g:wplus_ai_temperature = 0.7                     " 0.0~1.0
let g:wplus_ai_max_tokens = 2000

" Azure OpenAI (provider='azure'일 때만)
let g:wplus_ai_azure_resource = 'your-resource'
let g:wplus_ai_azure_deployment = 'your-deployment'
let g:wplus_ai_azure_api_version = '2024-02-15-preview'

" Ghost Text 자동완성
let g:wplus_ai_suggest_enabled = 1                  " 활성화 여부
let g:wplus_ai_suggest_delay = 500                  " 지연 시간 (ms)
let g:wplus_ai_suggest_context_lines = 50           " 컨텍스트 라인 수
let g:wplus_ai_suggest_suffix_lines = 20            " suffix 라인 수
```

#### Ghost Text 자동완성

**작동 방식:**
- InsertMode에서 타이핑 후 delay 시간 경과 시 자동으로 제안 표시
- Tab 키로 제안 수락
- 다른 키나 Escape로 제안 취소
- 회색(NonText 색상)으로 표시

**컨텍스트 추출:**
- 현재 위치의 prefix (이전 코드)
- 현재 위치의 suffix (다음 코드)
- 현재 scope (함수/클래스 등)
- 주변 심볼 추출

**지원 언어:**
Go, Python, TypeScript, JavaScript, Rust, Java, Kotlin, Ruby, Lua, C/C++

#### 예시

```vimscript
" 키 매핑
nnoremap <leader>ac :WaiComment<CR>
nnoremap <leader>ao :WaiComplete<CR>
vnoremap <leader>ar :WaiRefactor<CR>
nnoremap <leader>at :WaiToggleSuggest<CR>

" Ghost Text 수락 (Tab 키)
imap <Tab> <Cmd>call wplus#ai#accept_suggestion()<CR>
```

---

### snippet — 스니펫 엔진

코드 템플릿을 빠르게 확장하는 스니펫 엔진입니다.

#### 플레이스홀더 문법

```
${1:default}  - 선택 가능한 필드
${2:second}   - 두 번째 필드
${0:end}      - 스니펫 종료 지점
```

#### 기본 스니펫

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

#### 설정

```vim
let g:wplus_snippet_enabled = 1
let g:wplus_snippet_jump_key = '<Tab>'
let g:wplus_snippet_jump_back_key = '<S-Tab>'
```

---

### conflict — Git 충돌 해결

Git merge 충돌을 시각적으로 감지하고 해결합니다.

#### 명령어

| 명령 | 동작 |
|------|------|
| `:WconflictNext` | 다음 충돌로 이동 |
| `:WconflictPrev` | 이전 충돌로 이동 |
| `:WconflictOurs` | ours 버전 선택 |
| `:WconflictTheirs` | theirs 버전 선택 |
| `:WconflictBoth` | 둘 다 선택 (ours + theirs) |

#### 설정

```vim
let g:wplus_conflict_enabled = 1
let g:wplus_conflict_auto_highlight = 1
```

---

### todo — TODO 관리

코드 내 TODO/FIXME/HACK 주석을 자동으로 수집하여 Quickfix에 표시합니다.

#### 명령어

| 명령 | 동작 |
|------|------|
| `:WtodoQuickfix` | TODO 목록을 Quickfix에 표시 |

#### 검색 대상

```vim
let g:wplus_todo_keywords = ['TODO', 'FIXME', 'HACK', 'BUG', 'XXX']
```

#### 설정

```vim
let g:wplus_todo_enabled = 1
let g:wplus_todo_grep_backend = 'rg'     " rg, git grep, grep
```

---

### colorscheme — 배경색 자동 감지

터미널의 밝기(dark/light)를 자동으로 감지하여 컬러스킴을 적응형으로 조정합니다.

#### 설정

```vim
let g:wplus_colorscheme_auto_detect = 1
```

---

## 설정 가이드

상세한 설정 방법은 [SETUP.md](SETUP.md)를 참고하세요.

주요 내용:
- LSP 서버 설치 및 설정
- AI 공급자 선택 및 API 키 설정
- 성능 최적화 설정
- 키 매핑 추천
- 문제 해결

---

## 모듈 비활성화

`plug#begin()` 전(또는 `plugin/wplus.vim` 로드 전)에 선언합니다.

```vim
let g:wplus_blame_enabled         = 0
let g:wplus_indent_enabled        = 0
let g:wplus_yankhighlight_enabled = 0
```

**전체 토글 변수 목록**:

```vim
" 기본 편집 (7)
g:wplus_commentary_enabled   " 주석 토글
g:wplus_surround_enabled     " 괄호 조작
g:wplus_pairs_enabled        " 자동 괄호
g:wplus_textobj_enabled      " 텍스트 오브젝트
g:wplus_format_enabled       " 스마트 포매터
g:wplus_repeat_enabled       " . 반복 지원
g:wplus_altfile_enabled      " 헤더↔소스 전환

" VCS/Git (5)
g:wplus_gitgutter_enabled    " Sign diff
g:wplus_blame_enabled        " Git blame
g:wplus_terminal_enabled     " 터미널 토글
g:wplus_explorer_enabled     " 사이드바 탐색기
g:wplus_session_enabled      " 세션 관리

" UI (5)
g:wplus_statusline_enabled   " 상태바
g:wplus_tabline_enabled      " 탭라인
g:wplus_indent_enabled       " 들여쓰기 가이드
g:wplus_undotree_enabled     " Undo 사이드바
g:wplus_quickfix_enabled     " Quickfix 강화

" 검색/네비게이션 (5)
g:wplus_finder_enabled       " 고속 퍼지 파인더
g:wplus_grep_enabled         " 고속 검색
g:wplus_whichkey_enabled     " 키 힌트 팝업
g:wplus_bufdelete_enabled    " 버퍼 삭제
g:wplus_root_enabled         " 루트 자동 인식

" 하이라이팅/시각화 (3)
g:wplus_illuminate_enabled   " 심볼 하이라이트
g:wplus_yankhighlight_enabled" 복사 피드백
g:wplus_lsp_enabled          " 경량 LSP

" 신규 기능 (5)
g:wplus_ai_enabled           " AI 어시스턴트
g:wplus_snippet_enabled      " 스니펫 엔진
g:wplus_conflict_enabled     " Git 충돌 해결
g:wplus_todo_enabled         " TODO 관리
g:wplus_colorscheme_enabled  " 배경색 자동 감지
```

---

## 전체 설정 레퍼런스

```vim
" ── blame ───────────────────────────────────────────────────────────────
let g:wplus_blame_delay       = 500          " 표시 지연 (ms)
let g:wplus_blame_prefix      = '   '
let g:wplus_blame_template    = '<author>, <date> • <summary>'
let g:wplus_blame_date_format = '%y/%m/%d'

" ── gitgutter ────────────────────────────────────────────────────────────
let g:wplus_gitgutter_sign_add    = '┃'
let g:wplus_gitgutter_sign_change = '┃'
let g:wplus_gitgutter_sign_delete = '▁'

" ── illuminate ───────────────────────────────────────────────────────────
let g:wplus_illuminate_delay    = 200        " 하이라이트 지연 (ms)
let g:wplus_illuminate_ft_block = ['help', 'nerdtree', 'undotree']

" ── indent ───────────────────────────────────────────────────────────────
let g:wplus_indent_char       = '▏'
let g:wplus_indent_ft_exclude = ['help', 'nerdtree', 'undotree', 'tagbar']

" ── yankhighlight ────────────────────────────────────────────────────────
let g:wplus_yank_duration     = 250          " 강조 지속 시간 (ms)

" ── lsp ─────────────────────────────────────────────────────────────────
let g:wplus_lsp_log_enabled   = 1
let g:wplus_lsp_signcolumn    = 'yes'        " signcolumn 기본값, 빈 문자열이면 건드리지 않음

" ── explorer ────────────────────────────────────────────────────────────
let g:wplus_explorer_max_entries = 1000      " 최대 표시 항목 수
let g:wplus_explorer_max_depth   = 8         " 최대 재귀 깊이

" ── session ─────────────────────────────────────────────────────────────
let g:wplus_session_autoload  = 1
let g:wplus_session_autosave  = 1
let g:wplus_session_max_files = 50          " 보관할 세션 파일 최대 개수

" ── undotree ─────────────────────────────────────────────────────────────
let g:wplus_undotree_width    = 30           " 사이드바 너비 (컬럼)

" ── ai ────────────────────────────────────────────────────────────────
let g:wplus_ai_provider = 'openai'          " 'openai' | 'claude' | 'azure'
let g:wplus_ai_api_key = ''                 " API 키 (필수)
let g:wplus_ai_model = 'gpt-3.5-turbo'
let g:wplus_ai_temperature = 0.7            " 0.0~1.0
let g:wplus_ai_max_tokens = 2000

" Azure OpenAI 전용 설정
let g:wplus_ai_azure_resource = ''
let g:wplus_ai_azure_deployment = ''
let g:wplus_ai_azure_api_version = '2024-02-15-preview'

" ── snippet ───────────────────────────────────────────────────────────
let g:wplus_snippet_jump_key = '<Tab>'
let g:wplus_snippet_jump_back_key = '<S-Tab>'
let g:wplus_snippet_placeholder_marker = '${}'

" ── conflict ──────────────────────────────────────────────────────────
let g:wplus_conflict_auto_highlight = 1

" ── todo ──────────────────────────────────────────────────────────────
let g:wplus_todo_keywords = ['TODO', 'FIXME', 'HACK', 'BUG', 'XXX']
let g:wplus_todo_grep_backend = 'rg'        " 'rg' | 'git grep' | 'grep'

" ── colorscheme ──────────────────────────────────────────────────────
let g:wplus_colorscheme_auto_detect = 1
```

---

## 도움말

```vim
:help wplus
```
