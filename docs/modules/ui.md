# UI·시각화 모듈

> [← README](../../README.md) · [전체 단축키](../keymaps.md) · [설정 레퍼런스](../config.md)

---

## statusline — 상태바

```
 NORMAL  main  src/main.go  [+]      E:1 W:2   go  UTF-8   42:10  85%
```

표시 항목: 모드 · git 브랜치 · 파일명 · 수정/RO 플래그 · LSP 진단 수 · filetype · 인코딩 · 커서 위치 · 스크롤 %

별도 설정 없이 자동으로 활성화됩니다.

---

## tabline — 버퍼 탭라인

열려 있는 버퍼를 상단 탭라인에 번호와 함께 표시합니다.

```
  1 init.vim   2 wplus.vim ● 3 README.md
```

`●` 표시: 저장되지 않은 버퍼

---

## indent — 들여쓰기 가이드

들여쓰기 레벨마다 세로선을 표시합니다 (conceal 기반).

```vim
let g:wplus_indent_char       = '▏'
let g:wplus_indent_ft_exclude = ['help', 'nerdtree', 'undotree', 'tagbar']
```

---

## illuminate — 심볼 하이라이트

커서 아래 단어와 동일한 심볼을 버퍼 내에서 자동으로 하이라이트합니다.

```vim
let g:wplus_illuminate_delay    = 200
let g:wplus_illuminate_ft_block = ['help', 'nerdtree']
```

---

## undotree — Undo 히스토리

| 키 | 동작 |
|----|------|
| `<leader>u` | 사이드바 토글 |

**사이드바 내 키:**

| 키 | 동작 |
|----|------|
| `j` / `k` | 이전/다음 undo 상태로 이동 |
| `<CR>` | 해당 상태로 undo/redo |
| `q` | 닫기 |

```vim
let g:wplus_undotree_width = 30   " 사이드바 너비
```

---

## scrollbar — 미니맵 스크롤바

Sign 컬럼에 텍스트 기반 스크롤바를 렌더링합니다. LSP 진단 위치를 `●`로 오버레이합니다.

| 키 / 명령 | 동작 |
|-----------|------|
| `<leader>sb` / `:WscrollbarToggle` | 스크롤바 켜기/끄기 |

**기호 의미:**

| 기호 | 색상 | 의미 |
|------|------|------|
| `▐` | 회색 | 트랙 (현재 뷰 밖) |
| `█` | 밝은 회색 | 썸 (현재 뷰포트) |
| `●` | 빨간색 | LSP 에러 위치 |
| `●` | 노란색 | LSP 경고 위치 |

파일 길이가 `wplus_scrollbar_min_lines` 미만이면 자동으로 숨겨집니다.

```vim
let g:wplus_scrollbar_enabled   = 1    " 기본 활성화
let g:wplus_scrollbar_char      = '▐'  " 트랙 문자
let g:wplus_scrollbar_thumb     = '█'  " 썸 문자
let g:wplus_scrollbar_min_lines = 50   " 표시 최소 줄 수
```

---

## colorscheme — 배경색 자동 감지

터미널의 밝기(dark/light)를 자동으로 감지하여 컬러스킴을 조정합니다.

```vim
let g:wplus_colorscheme_auto_detect = 1
```
