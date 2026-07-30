# 코드 도구 모듈

> [← README](../../README.md) · [전체 단축키](../keymaps.md) · [설정 레퍼런스](../config.md)

---

## lsp — 경량 LSP 클라이언트

복잡한 설정 없이 `gopls` 등 언어 서버의 핵심 기능을 활용합니다.

| 키 | 동작 |
|----|------|
| `gd` | 정의 이동 (Go to Definition) |
| `gr` | 참조 찾기 (References) |
| `K` | 심볼 정보 (Hover) |
| `<leader>rn` | 심볼 이름 변경 (Rename) |
| `<leader>ca` | Code Action |
| `]e` / `[e` | 다음/이전 진단 |
| `<leader>E` | 현재 줄 진단 팝업 |

진단은 sign 컬럼에 `E`, `W`, `I`, `H`로 표시되며 상태바에 `E:n W:n` 형식으로도 표시됩니다.

**지원 언어 서버 설치:**

```bash
# Go
go install github.com/golang/tools/gopls@latest

# Python
pip install python-lsp-server

# TypeScript
npm install -g typescript-language-server

# Rust
rustup component add rust-analyzer
```

**LSP Inlay Hints** (타입·파라미터 힌트):

```vim
:WplusLspInlayHints    " 현재 버퍼 inlay hints 갱신
```

```vim
let g:wplus_lsp_log_enabled  = 0    " 디버그 로그 (lsp.log)
let g:wplus_lsp_signcolumn   = 'yes'
let g:wplus_lsp_cache_ttl    = 300  " 캐시 유효시간 (초)
```

---

## format — 스마트 포매터

`<M-F>` (`Alt+Shift+F`)로 현재 파일을 언어에 맞는 포매터로 자동 정렬합니다.

**우선순위:** LSP formatter → 외부 도구 → ALE → `gg=G`

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
| `<M-F>` | Normal / Insert | 파일 전체 포맷 |
| `<M-F>` | Visual | 선택 범위 포맷 |

---

## outline — 코드 아웃라인

ctags를 사용하여 현재 파일 내 클래스·함수·구조체 등을 사이드바에 표시합니다.  
**ctags 설치 필요** (universal-ctags 권장).

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>o` / `:WoutlineToggle` | 아웃라인 사이드바 토글 |
| `<CR>` | 선택된 심볼 위치로 이동 |
| `R` | 수동 새로고침 |
| `q` | 닫기 |

---

## fold — 스마트 폴드

들여쓰기 기반 또는 LSP `foldingRange` 기반의 자동 폴드를 제공합니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>zz` / `:WfoldToggle` | 커서 위치 폴드 토글 |
| `<leader>za` / `:WfoldOpenAll` | 모든 폴드 펼치기 |
| `<leader>zc` / `:WfoldCloseAll` | 모든 폴드 닫기 |
| `<leader>zo` / `:WfoldCloseOthers` | 현재 위치 제외 나머지 닫기 |

폴드 텍스트 형식: `▶ 첫 줄 내용  [N lines]`

```vim
let g:wplus_fold_method   = 'indent'  " 'indent' | 'lsp' | 'syntax'
let g:wplus_fold_level    = 99        " 초기 foldlevel (99 = 모두 열기)
let g:wplus_fold_column   = 0         " foldcolumn 너비
```

---

## run — 코드 실행 및 빌드

파일타입별 실행 명령과 프로젝트 빌드 시스템을 자동 감지합니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>rr` / `:Wrun` | 현재 파일 실행 |
| `<leader>rb` / `:Wbuild` | 프로젝트 빌드 |
| `<leader>rt` / `:Wtest` | 프로젝트 테스트 |

**기본 지원 파일타입:** python, go, javascript, typescript, lua, sh, bash, ruby, rust, c, cpp

**커스터마이즈:**

```vim
" %s = 파일 경로, %r = 확장자 없는 파일명
let g:wplus_run_commands = {
    \ 'python': 'python3 -u %s',
    \ 'go':     'go run ./cmd/main.go',
    \ }
let g:wplus_build_commands = {'Makefile': 'make release'}
let g:wplus_run_use_terminal = 1   " 1=터미널, 0=quickfix
```

---

## terminal — 터미널 토글

하단 스플릿 창으로 터미널을 빠르게 열고 닫습니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>tt` / `:WplusTerminalToggle` | 터미널 토글 |
| `<Esc><Esc>` | 터미널 모드 탈출 (Normal 모드로) |

---

## root — 프로젝트 루트 자동 인식

파일을 열 때 `.git`, `go.mod`, `Makefile` 등을 찾아 자동으로 작업 디렉토리(`lcd`)를 변경합니다.  
별도 설정 없이 자동으로 동작하며, `run`, `grep`, `session` 등 다른 모듈의 기반이 됩니다.

---

## session — 세션 관리

프로젝트 루트 단위로 편집 세션을 저장하고 Vim 시작 시 자동 복원합니다.

| 명령 | 동작 |
|------|------|
| `:WsessionSave` | 현재 세션 수동 저장 |
| `:WsessionLoad` | 현재 세션 수동 로드 |
| `:WsessionDelete` | 현재 프로젝트의 세션 파일 삭제 |

```vim
let g:wplus_session_autoload  = 1
let g:wplus_session_autosave  = 1
let g:wplus_session_max_files = 50
```

---

## project — 프로젝트별 설정

프로젝트 루트에 `.wplus.vim` 파일을 두면 해당 프로젝트 진입 시 자동 소스됩니다.

| 명령 | 동작 |
|------|------|
| `<leader>pe` / `:WprojectEdit` | 프로젝트 설정 파일 편집 (없으면 생성) |
| `<leader>pr` / `:WprojectReload` | 설정 파일 재로드 |

**`.wplus.vim` 예시:**

```vim
set tabstop=2 shiftwidth=2
let g:wplus_run_commands = {'go': 'go run ./cmd/server.go'}
```

```vim
let g:wplus_project_config  = '.wplus.vim'
let g:wplus_project_verbose = 0           " 1이면 로드 시 메시지 출력
```

---

## scratch — 스크래치 버퍼

`~/.vim/scratch.txt`에 저장되는 영구 스크래치 버퍼입니다.  
창을 닫아도 내용이 자동 저장됩니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>sc` / `:WscratchToggle` | 하단 스플릿으로 토글 |
| `<leader>sv` / `:WscratchVertical` | 수직 분할로 열기 |

```vim
let g:wplus_scratch_file   = expand('~/.vim/scratch.txt')
let g:wplus_scratch_height = 15
let g:wplus_scratch_ft     = 'markdown'
```

---

## marks — 마크 시각화

Vim 내장 마크(a–z)를 Sign 컬럼에 노란 알파벳으로 표시합니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>ml` / `:WmarksList` | 설정된 마크 목록 팝업 |
| `<leader>md` / `:WmarksDelete` | 커서 줄의 마크 삭제 |
| `:WmarksRefresh` | Sign 컬럼 마크 수동 새로고침 |

```vim
let g:wplus_marks_sign_prefix = ''   " Sign 텍스트 앞 접두어
```

---

## todo — TODO 관리

코드 내 TODO/FIXME/HACK 주석을 자동으로 수집합니다.

| 명령 | 동작 |
|------|------|
| `<leader>ft` / `:WtodoFind` | TODO 목록을 finder 팝업으로 |
| `<leader>tq` / `:WtodoQuickfix` | TODO 목록을 Quickfix에 표시 |

```vim
let g:wplus_todo_keywords = ['TODO', 'FIXME', 'HACK', 'BUG', 'XXX']
```

---

## grep — 고속 검색

`ripgrep`(rg) 또는 `git grep`을 활용하여 프로젝트 전체를 검색합니다.

| 키 / 명령 | 모드 | 동작 |
|-----------|------|------|
| `:Wgrep {pattern}` | Normal | 패턴 검색 후 Quickfix 오픈 |
| `<leader>fg` | Normal | 커서 아래 단어로 검색 |
| `<leader>fg` | Visual | 선택 영역으로 검색 |
