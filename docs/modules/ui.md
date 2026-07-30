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

## theme — 테마 및 통합 하이라이트 관리

`&background` (dark/light)를 자동으로 감지하여 모든 `Wplus*` 하이라이트 그룹의 팔레트를 조율합니다.
사용자가 정의한 `highlight` 설정 및 `:colorscheme` 변경 시에도 하이라이트가 안전하게 유지됩니다.

```vim
let g:wplus_theme_auto = 1
```
