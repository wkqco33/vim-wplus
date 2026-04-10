# vim-wplus

외부 의존성 없는 Vim 올인원 플러그인.  
자주 쓰이는 플러그인 18개의 기능을 순수 VimScript로 직접 구현합니다.

**요구사항**: Vim 9.1+ (`+job +channel +popupwin +signs +textprop`)

---

## 목차

- [설치](#설치)
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
  - [altfile — 헤더↔소스 전환](#altfile--헤더소스-전환)
  - [repeat — . 반복 지원](#repeat---반복-지원)
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

## 모듈 비활성화

`plug#begin()` 전(또는 `plugin/wplus.vim` 로드 전)에 선언합니다.

```vim
let g:wplus_blame_enabled         = 0
let g:wplus_indent_enabled        = 0
let g:wplus_yankhighlight_enabled = 0
```

**전체 토글 변수 목록**:

```vim
g:wplus_commentary_enabled   " 주석 토글
g:wplus_surround_enabled     " 괄호 조작
g:wplus_pairs_enabled        " 자동 괄호
g:wplus_textobj_enabled      " 텍스트 오브젝트
g:wplus_format_enabled       " 스마트 포매터
g:wplus_gitgutter_enabled    " Sign diff
g:wplus_blame_enabled        " Git blame
g:wplus_statusline_enabled   " 상태바
g:wplus_tabline_enabled      " 탭라인
g:wplus_indent_enabled       " 들여쓰기 가이드
g:wplus_illuminate_enabled   " 심볼 하이라이트
g:wplus_yankhighlight_enabled" 복사 피드백
g:wplus_undotree_enabled     " Undo 사이드바
g:wplus_whichkey_enabled     " 키 힌트 팝업
g:wplus_bufdelete_enabled    " 버퍼 삭제
g:wplus_quickfix_enabled     " Quickfix 강화
g:wplus_altfile_enabled      " 헤더↔소스 전환
g:wplus_repeat_enabled       " . 반복 지원
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

" ── undotree ─────────────────────────────────────────────────────────────
let g:wplus_undotree_width    = 30           " 사이드바 너비 (컬럼)
```

---

## 도움말

```vim
:help wplus
```

