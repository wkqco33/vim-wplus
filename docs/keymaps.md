# 기본 단축키 치트시트

> [← README](../README.md) · [설정 레퍼런스](config.md) · [AI 가이드](ai.md)

모든 단축키는 `.vimrc.example`에 매핑 예시가 포함되어 있습니다.  
`<leader>`는 기본적으로 `\`입니다 — 대부분의 사용자는 `,` 또는 `<Space>`로 변경합니다.

---

## 탐색

| 키 | 모듈 | 동작 |
|----|------|------|
| `<leader>ff` | finder | 파일 찾기 |
| `<leader>fb` | finder | 버퍼 찾기 |
| `<leader>fr` | finder | 최근 파일 찾기 |
| `<leader>fh` | history | 전체 최근 파일 |
| `<leader>fH` | history | 프로젝트 내 최근 파일 |
| `<leader>e` | explorer | 파일 탐색기 토글 |
| `<leader>ha` | harpoon | 현재 파일 슬롯에 추가 |
| `<leader>hd` | harpoon | 현재 파일 슬롯에서 제거 |
| `<leader>hl` | harpoon | 슬롯 목록 팝업 |
| `<leader>h1~4` | harpoon | 슬롯 1~4 파일로 이동 |
| `:A` | altfile | 헤더↔소스 전환 |
| `:AV` / `:AS` | altfile | 수직/수평 분할로 전환 |

---

## 편집

| 키 | 모드 | 모듈 | 동작 |
|----|------|------|------|
| `gcc` | Normal | commentary | 현재 줄 주석 토글 |
| `gc{motion}` | Normal | commentary | motion 범위 주석 토글 |
| `gc` | Visual | commentary | 선택 범위 주석 토글 |
| `ys{motion}{char}` | Normal | surround | 텍스트 감싸기 |
| `cs{old}{new}` | Normal | surround | 감싸기 변경 |
| `ds{char}` | Normal | surround | 감싸기 제거 |
| `S{char}` | Visual | surround | 선택 감싸기 |
| `ii` / `ai` | Visual/Op | textobj | 들여쓰기 블록 |
| `ia` / `aa` | Visual/Op | textobj | 함수 인자 |
| `<C-n>` | Normal | multicursor | 다음 일치 항목 다중 선택 추가 |
| `<leader>vx` | Normal | multicursor | 현재 일치 항목 건너뛰기 |
| `<leader>va` | Normal | multicursor | 모든 일치 항목 다중 선택 |
| `<M-F>` | Normal/Visual | format | 포맷 |
| `.` | Normal | repeat | 마지막 동작 반복 |

---

## Git

| 키 / 명령 | 모듈 | 동작 |
|-----------|------|------|
| `<leader>hr` | gitgutter | 커서 위치 hunk 원복 |
| `]h` / `[h` | gitgutter | 다음/이전 hunk |
| `:BlamerToggle` | blame | 인라인 blame 토글 |
| `<leader>gd` | diffview | 현재 파일 Diff |
| `<leader>gD` | diffview | 저장소 전체 Diff |
| `:WconflictNext` / `:WconflictPrev` | conflict | 다음/이전 충돌 |
| `:WconflictOurs` | conflict | ours 선택 |
| `:WconflictTheirs` | conflict | theirs 선택 |

---

## 코드

| 키 | 모듈 | 동작 |
|----|------|------|
| `gd` | lsp | 정의 이동 |
| `gy` | lsp | 타입 정의 이동 |
| `<leader>gi` | lsp | 구현 이동 |
| `gr` | lsp | 참조 찾기 |
| `K` | lsp | 심볼 정보 (Hover) |
| `<leader>rn` | lsp | 심볼 이름 변경 (미리보기) |
| `<leader>ca` | lsp | Code Action |
| `<leader>ci` | lsp | Organize Imports |
| `<leader>gl` | lsp | Document Link 열기 |
| `]e` / `[e` | lsp | 다음/이전 진단 |
| `<leader>E` | lsp | 현재 줄 진단 팝업 |
| `<leader>o` | outline | 코드 아웃라인 토글 |
| `:WlspSymbols {query}` | lsp | 워크스페이스 심볼 검색 |
| `<leader>fg` | grep | 커서 단어로 프로젝트 검색 |
| `:Wgrep {pat}` | grep | 패턴 검색 |

---

## 실행/빌드

| 키 / 명령 | 모듈 | 동작 |
|-----------|------|------|
| `<leader>rr` / `:Wrun` | run | 현재 파일 실행 |
| `<leader>rb` / `:Wbuild` | run | 프로젝트 빌드 |
| `<leader>rt` / `:Wtest` | run | 프로젝트 테스트 |
| `<leader>tt` | terminal | 터미널 토글 |
| `<Esc><Esc>` (terminal) | terminal | Normal 모드로 탈출 |

---

## AI

| 키 / 명령 | 모드 | 동작 |
|-----------|------|------|
| `:'<,'>WaiReview` | Visual | 선택 코드 리뷰 |
| `:'<,'>WaiExplain` | Visual | 선택 코드 설명 |
| `:'<,'>WaiRefactor` | Visual | 선택 코드 리팩토링 |
| `:WaiComment` | Normal | 주석 생성 |
| `:WaiComplete` | Normal | 코드 완성 |
| `:WaiFixDiag` | Normal | LSP 진단 수정 |
| `:WaiCommitMsg` | Normal | 커밋 메시지 생성 |
| `:WaiToggleSuggest` | Normal | Ghost Text 토글 |
| `<Tab>` (Insert) | Insert | 스마트 탭 (Ghost Text 수락 → 팝업 메뉴 → 인덴트) |
| `<Plug>WaiAcceptSuggest` | Insert | Ghost Text 수락 |
| `<Plug>WaiAcceptWord` | Insert | Ghost Text 다음 단어 수락 |
| `<Plug>WaiSmartTab` | Insert | 스마트 탭 수락/완성 |
| `<Plug>WaiDismissSuggest` | Insert | Ghost Text 닫기 |

---

## 프로젝트·세션

| 키 / 명령 | 모듈 | 동작 |
|-----------|------|------|
| `<leader>pe` | project | 프로젝트 설정 편집 |
| `<leader>pr` | project | 프로젝트 설정 재로드 |
| `<leader>sc` | scratch | 스크래치 버퍼 토글 |
| `<leader>sv` | scratch | 스크래치 버퍼 (수직) |
| `:WsessionSave` | session | 세션 저장 |
| `:WsessionLoad` | session | 세션 로드 |

---

## UI·시각화

| 키 / 명령 | 모듈 | 동작 |
|-----------|------|------|
| `<leader>zz` | fold | 폴드 토글 |
| `<leader>za` | fold | 모든 폴드 열기 |
| `<leader>zc` | fold | 모든 폴드 닫기 |
| `<leader>zo` | fold | 다른 폴드 닫기 |
| `<leader>ml` | marks | 마크 목록 팝업 |
| `<leader>md` | marks | 커서 줄 마크 삭제 |
| `<leader>ft` | todo | TODO 목록 finder |
| `<leader>tq` | todo | TODO Quickfix |

---

## 버퍼·창

| 키 / 명령 | 모듈 | 동작 |
|-----------|------|------|
| `<leader>bd` | bufdelete | 버퍼 삭제 (창 유지) |
| `<leader>bD` | bufdelete | 버퍼 wipeout |
| `<leader>xq` | quickfix | Quickfix 토글 |
| `<leader>xl` | quickfix | Location list 토글 |
| `]q` / `[q` | quickfix | 다음/이전 에러 |
| `<leader>xr` | quickfix | 프로젝트 전체 치환 |
| `"` | register | 레지스터 미리보기 팝업 |
| `@` | register | 매크로 레지스터 팝업 |

---

## 권장 vimrc 추가 매핑

`<leader>ff`, `<leader>fb`, `<leader>fh`, `<leader>e`, `<leader>rr`, `<leader>rb`,
`<leader>gd` 등은 **이미 플러그인 기본값**이다. 아래는 기본값이 없는 것만 추린 것이다.

```vim
" 리더 키 (기본값은 Vim 기본인 '\')
let mapleader = ' '

" AI — ai 모듈은 <Plug> 매핑만 제공하므로 직접 바인딩이 필요하다
vnoremap <leader>ar :WaiReview<CR>
vnoremap <leader>ae :WaiExplain<CR>
vnoremap <leader>af :WaiRefactor<CR>
nnoremap <leader>am :WaiCommitMsg<CR>

" 창 이동
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
```

> **`<Tab>` 동작 방식**: `g:wplus_ai_tab_complete = 1`(기본값) 설정 시, `<Tab>`은
> AI Ghost Text 수락 → 팝업 메뉴 선택(`pumvisible()`) → 일반 탭/들여쓰기 순으로 스마트하게 체이닝됩니다.
> 원치 않을 경우 `let g:wplus_ai_tab_complete = 0`으로 비활성화하거나 `<Plug>WaiSmartTab`을 원하는 키에 매핑할 수 있습니다.

---

## VS Code 단축키 정렬 (opt-in)

`let g:wplus_vscode_keymaps = 1`로 켜면 VS Code 단축키가 그대로 동작합니다.
기본값은 `0`(꺼짐)이라 기존 사용자에게 영향을 주지 않습니다.

| VS Code | 동작 |
|---------|------|
| `F12` | 정의 이동 |
| `Shift+F12` | 참조 찾기 |
| `Alt+F12` | Peek Definition (팝업) |
| `F2` | 심볼 이름 변경 |
| `Ctrl+.` | Quick Fix (Code Action) |
| `Ctrl+Shift+F` | 파일에서 찾기 (grep) |
| `Ctrl+Shift+O` | 파일 내 심볼 (outline) |
| `Ctrl+T` | 워크스페이스 심볼 |
| `Ctrl+Shift+E` | 탐색기 토글 |
| `Ctrl+Shift+M` | Problems (진단 목록) |
| `Ctrl+Shift+H` | 호출 계층 (누가 호출) |
| `Ctrl+Space` | 완성 트리거 |
| `Ctrl+Shift+Space` | 시그니처 힌트 |
| `Ctrl+Shift+K` | 줄 삭제 |
| `Ctrl+Enter` / `Ctrl+Shift+Enter` | 아래/위에 줄 삽입 |
| `Ctrl+Shift+[` / `]` | 접기 / 펼치기 |
| `Ctrl+K Ctrl+0` / `Ctrl+K Ctrl+J` | 모두 접기 / 모두 펼치기 |
| `` Ctrl+` `` / `Ctrl+Shift+C` | 터미널 토글 |
| `Ctrl+P` | 파일 찾기 |
| `Ctrl+Tab` / `Ctrl+PageDown` | 다음 버퍼 |

> **터미널 주의**: 일부 터미널은 `Ctrl+Space`와 `Ctrl+Shift+Space`를 구분하지 못합니다.
> `Ctrl+Space`는 `Ctrl+@`(NUL)에도 함께 매핑되어 있습니다.
