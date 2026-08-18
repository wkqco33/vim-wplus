# vim-wplus

외부 의존성 없는 Vim 올인원 플러그인 — 모듈형 구성의 완전한 Vim IDE.

**요구사항**: Vim 9.1+ (`+job +channel +popupwin +signs +textprop`)

---

## 설치

```vim
" vim-plug
Plug 'wkqco33/vim-wplus'
```

```bash
# pack 직접 설치
git clone https://github.com/wkqco33/vim-wplus.git ~/.vim/pack/user/start/vim-wplus
```

```vim
" 수동
set runtimepath+=~/.vim/pack/user/start/vim-wplus
source ~/.vim/pack/user/start/vim-wplus/plugin/wplus.vim
```

**빠른 시작**: `.vimrc.example`을 `~/.vimrc`로 복사하면 기본 키 매핑이 모두 설정됩니다.

> 설치 상세 · 문제 해결 → **[SETUP.md](SETUP.md)**

---

## 문서

| 문서 | 내용 |
|------|------|
| [SETUP.md](SETUP.md) | 설치, 외부 도구, 문제 해결 |
| [docs/modules/editing.md](docs/modules/editing.md) | 편집 강화 모듈 (commentary, surround, pairs …) |
| [docs/modules/navigation.md](docs/modules/navigation.md) | 탐색·파인더 모듈 (finder, explorer, harpoon …) |
| [docs/modules/git.md](docs/modules/git.md) | Git 연동 모듈 (gitgutter, blame, diffview …) |
| [docs/modules/ui.md](docs/modules/ui.md) | UI·시각화 모듈 (statusline, tabline, indent …) |
| [docs/modules/code.md](docs/modules/code.md) | 코드 도구 모듈 (lsp, run, fold, format …) |
| [docs/ai.md](docs/ai.md) | AI 어시스턴트 심화 가이드 |
| [docs/config.md](docs/config.md) | 전체 설정 레퍼런스 |
| [docs/keymaps.md](docs/keymaps.md) | 기본 단축키 치트시트 |
| [CHANGE_LOG.md](CHANGE_LOG.md) | 변경 이력 |

---

## 모듈 목록

### ✏️ 편집 강화

| 모듈 | 기능 | 핵심 키 |
|------|------|---------|
| `commentary` | 주석 토글 | `gcc`, `gc{motion}` |
| `surround` | 괄호·따옴표 조작 | `ys`, `cs`, `ds` |
| `pairs` | 자동 괄호 완성 | 입력 시 자동 |
| `textobj` | 들여쓰기/인자 텍스트 오브젝트 | `ii`, `ia`, `aa` |
| `multicursor` | 다중 커서 | `<C-n>` |
| `register` | 레지스터 미리보기 | `"`, `@` |
| `yankhighlight` | 복사 시각 피드백 | 자동 |

### 🧭 탐색

| 모듈 | 기능 | 핵심 키 |
|------|------|---------|
| `finder` | 퍼지 파일/버퍼 파인더 | `<leader>ff`, `<leader>fb` |
| `explorer` | 사이드바 파일 탐색기 | `<leader>e` |
| `harpoon` | 파일 북마크 (최대 4슬롯) | `<leader>ha`, `<leader>h1~4` |
| `history` | 최근 파일 브라우저 | `<leader>fh` |
| `altfile` | 헤더↔소스 전환 | `:A`, `:AV` |
| `bufdelete` | 창 유지 버퍼 삭제 | `<leader>bd` |
| `quickfix` | Quickfix 강화 | `<leader>xq`, `]q` |

### 🔀 Git

| 모듈 | 기능 | 핵심 키 |
|------|------|---------|
| `gitgutter` | Sign 컬럼 diff | 자동 |
| `blame` | 인라인 Git Blame | `:BlamerToggle` |
| `diffview` | Git Diff 뷰어 | `<leader>gd` |
| `conflict` | Git 충돌 해결 | `:WconflictOurs/Theirs` |

### 🎨 UI

| 모듈 | 기능 | 핵심 키 |
|------|------|---------|
| `statusline` | 상태바 | 자동 |
| `tabline` | 버퍼 탭라인 | 자동 |
| `indent` | 들여쓰기 가이드 | 자동 |
| `illuminate` | 심볼 하이라이트 | 자동 |
| `colorscheme` | 배경 자동 감지 및 하이라이트 통합 | 자동 |

### 🛠 코드 도구

| 모듈 | 기능 | 핵심 키 |
|------|------|---------|
| `lsp` | 경량 LSP 클라이언트 | `gd`, `gr`, `K` |
| `format` | 스마트 포매터 | `<M-F>` |
| `outline` | 코드 아웃라인 | `<leader>o` |
| `fold` | 스마트 폴드 | `<leader>zz` |
| `run` | 코드 실행/빌드/테스트 | `<leader>rr/rb/rt` |
| `terminal` | 터미널 토글 | `<leader>tt` |
| `root` | 프로젝트 루트 감지 | 자동 |
| `session` | 세션 관리 | 자동 저장/복원 |
| `project` | 프로젝트별 설정 | `<leader>pe` |
| `scratch` | 스크래치 버퍼 | `<leader>sc` |
| `marks` | 마크 시각화 | `<leader>ml` |
| `todo` | TODO 관리 | `<leader>ft` |
| `health` | 플러그인·환경 진단 보고서 | `:WplusHealth` |

### 🤖 AI

| 모듈 | 기능 | 핵심 키 |
|------|------|---------|
| `ai` | Ghost Text · 코드 리뷰 · 커밋 메시지 생성 · 요청 취소 | `<leader>am` (커밋), `<leader>ac` (취소), `<leader>ar/ae` |

> AI 상세 설정 → **[docs/ai.md](docs/ai.md)**

---

## 모듈 비활성화

```vim
" plugin/wplus.vim 로드 전에 선언
let g:wplus_blame_enabled   = 0
let g:wplus_indent_enabled  = 0
let g:wplus_ai_enabled      = 0
" 패턴: g:wplus_<모듈명>_enabled = 0
```

---

## 대체 플러그인

| 모듈 | 대체 플러그인 |
|------|--------------|
| `commentary` | tpope/vim-commentary |
| `surround` | tpope/vim-surround |
| `pairs` | jiangmiao/auto-pairs |
| `gitgutter` | airblade/vim-gitgutter |
| `blame` | APZelos/blamer.nvim |
| `statusline` | vim-airline / lightline |
| `finder` | junegunn/fzf.vim |
| `explorer` | preservim/nerdtree |
| `lsp` | yegappan/lsp |
| `multicursor` | mg979/vim-visual-multi |
| `outline` | preservim/tagbar |
| `diffview` | sindrets/diffview.nvim |
| `session` | tpope/vim-obsession |
| `harpoon` | ThePrimeagen/harpoon |
| `marks` | chentoast/marks.nvim |
| `run` | skywind3000/asyncrun.vim |
| `fold` | kevinhwang91/nvim-ufo |

---

## 라이선스

[MIT License](LICENSE) © 2026 wkqco33
