# 탐색·파인더 모듈

> [← README](../../README.md) · [전체 단축키](../keymaps.md) · [설정 레퍼런스](../config.md)

---

## finder — 고속 퍼지 파인더

Vim 9의 `matchfuzzy()`와 팝업 윈도우를 사용하여 파일, 버퍼, 최근 파일을 빠르게 찾습니다.

| 키 | 동작 |
|----|------|
| `<leader>p` | 파일 찾기 |
| `<leader>b` | 버퍼 찾기 |
| `<leader>m` | 최근 파일 찾기 (MRU) |

**팝업 내 키:**

| 키 | 동작 |
|----|------|
| `<C-n>` / `↓` | 다음 항목 |
| `<C-p>` / `↑` | 이전 항목 |
| `<CR>` | 현재 창에서 열기 |
| `<C-v>` | 수직 분할로 열기 |
| `<C-s>` | 수평 분할로 열기 |
| `<C-t>` | 탭에서 열기 |
| `<Esc>` | 닫기 |

```vim
let g:wplus_finder_width_ratio  = 0.7    " 팝업 너비 비율
let g:wplus_finder_height_ratio = 0.4    " 팝업 높이 비율
let g:wplus_finder_fuzzy_limit  = 10000  " 퍼지 매칭 최대 항목 수
```

---

## explorer — 사이드바 탐색기

| 키 | 동작 |
|----|------|
| `<leader>e` / `:WexplorerToggle` | 사이드바 토글 |

**탐색기 내 키:**

| 키 | 동작 |
|----|------|
| `<CR>` | 파일 열기 또는 디렉토리 이동 |
| `a` | 새 파일/디렉토리 생성 (디렉토리는 이름 끝에 `/`) |
| `d` | 삭제 |
| `r` | 이름 변경 |
| `R` | 새로고침 |
| `q` | 닫기 |

```vim
let g:wplus_explorer_max_entries = 1000  " 최대 표시 항목
let g:wplus_explorer_max_depth   = 8     " 최대 재귀 깊이
```

---

## harpoon — 빠른 파일 북마크

자주 오가는 파일 최대 4개를 슬롯에 등록하고 단축키로 즉시 이동합니다.  
슬롯 정보는 프로젝트 루트별로 `~/.vim/harpoon/*.json`에 저장됩니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>ha` / `:WharoonAdd` | 현재 파일을 다음 빈 슬롯에 추가 |
| `<leader>hd` / `:WharoonRemove` | 현재 파일을 슬롯에서 제거 |
| `<leader>hl` / `:WharoonList` | 슬롯 목록 팝업 |
| `<leader>h1` ~ `<leader>h4` | 해당 슬롯 파일로 즉시 이동 |

```vim
let g:wplus_harpoon_max_slots = 4   " 슬롯 수 (기본 4)
```

---

## history — 최근 파일 브라우저

세션 MRU + Vim 내장 `v:oldfiles`를 통합하여 finder 팝업으로 제공합니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>fh` / `:Whistory` | 전체 최근 파일 목록 |
| `<leader>fH` / `:WhistoryProject` | 현재 프로젝트 내 최근 파일만 |

```vim
let g:wplus_history_max          = 50  " 최대 파일 수
let g:wplus_history_project_only = 0   " 1이면 기본으로 프로젝트 내 파일만
```

---

## altfile — 헤더↔소스 전환

| 명령 | 동작 |
|------|------|
| `:A` | 같은 창에서 헤더↔소스 전환 |
| `:AV` | 수직 분할로 열기 |
| `:AS` | 수평 분할로 열기 |

`.h ↔ .c`, `.h ↔ .cpp`, `.hpp ↔ .cpp` 쌍을 지원합니다.

---

## bufdelete — 버퍼 삭제

기본 `:bd`는 창까지 닫히지만, 이 모듈은 **창을 유지**하고 버퍼만 닫습니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>bd` / `:Bdelete` | 현재 버퍼 닫기 (창 유지) |
| `<leader>bD` / `:Bwipeout` | 버퍼 wipeout (히스토리 포함 제거) |
| `:Bdelete!` | 미저장 버퍼 강제 닫기 |

---

## quickfix — Quickfix 강화

| 키 | 동작 |
|----|------|
| `<leader>xq` | Quickfix 패널 토글 |
| `<leader>xl` | Location list 토글 |
| `]q` / `[q` | 다음/이전 에러 (끝에서 wrap) |
| `]Q` / `[Q` | 마지막/첫 번째 에러로 이동 |
| `]l` / `[l` | Location list 다음/이전 |
| `<leader>xr` | 프로젝트 전체 치환 (quickfix 항목 기반) |

**프로젝트 전체 치환 워크플로우:**

```
1. :Wgrep <검색어>    — 검색 후 Quickfix 채우기
2. <leader>xr         — 치환 패턴 입력 → 모든 파일에 자동 적용
```

