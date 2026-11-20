# 단축키 확인 가이드

> [← README](../README.md) · [설정 레퍼런스](config.md) · [AI 가이드](ai.md)

키맵 표는 이 문서에 중복해서 두지 않습니다. 표를 손으로 관리하면 실제 등록된
키맵과 어긋나기 때문입니다(과거 문서에 있던 `<leader>ar/ae/af/am`은 플러그인
기본값이 아니라 `.vimrc.example` 예시였고, 반대로 런타임에만 있던
`<leader>i`, `<leader>bl`, `<leader>h2~h4`는 문서에 없었습니다).

**정본은 두 곳입니다.**

1. Vim 안에서 실행 중인 실제 상태 → `:WplusKeys` (또는 `<leader>?`)
2. 오프라인 문서 → `:help wplus-keymaps`

---

## 1. 실행 중인 키맵 보기 — `:WplusKeys`

```vim
:WplusKeys              " 전체 키맵
:WplusKeys lsp          " 필터를 미리 적용해서 열기
:WplusCommands          " 명령 화면으로 바로 열기
:WplusModules           " 모듈 화면으로 바로 열기
```

`<leader>?` 를 눌러도 같은 팝업이 열립니다. 목록은 `maplist()`와 `:command`를
매번 다시 읽어 만들기 때문에, 다음 항목까지 **현재 설정 그대로** 반영됩니다.

- 비활성화한 모듈(`g:wplus_<module>_enabled = 0`)
- opt-in 키맵(`g:wplus_vscode_keymaps`, `g:wplus_lsp_native_keymaps`)
- 사용자가 덮어쓴 매핑

### 팝업 조작

| 키 | 동작 |
| ---- | ------ |
| `Tab` | Keys → Commands → Modules 화면 전환 |
| `Enter` | 해당 항목의 명령을 커맨드라인에 채움 (모듈 화면: `:help wplus-<module>`) |
| `C-n` / `C-p` (`C-j`/`C-k`, 방향키) | 다음 / 이전 항목 |
| 타이핑 | 대소문자 무시 부분 문자열 필터 |
| `q` / `Esc` | 닫기 |

`Enter`는 매핑을 **실행하지 않습니다.** `<leader>rr`처럼 부작용이 있는 명령을
목록에서 실수로 촉발하지 않도록, 뒤에 있는 `:명령`을 커맨드라인에 채우기만
합니다. 검토 후 직접 Enter를 누르세요.

### 화면별 표시 내용

| 화면 | 한 줄 형식 |
| ---- | ---------- |
| Keys | `모드  <leader>ld  :WlspDefinition  [lsp]` |
| Commands | `:WlspHover  <leader>lh  [lsp]` — 어떤 키가 이 명령을 부르는지(역인덱스) |
| Modules | `[on] lsp  12 keys  22 cmds  n` — 활성 상태와 키맵/명령 개수 |

`+popupwin`이 없는 Vim에서는 같은 내용이 `__WplusKeys__` 버퍼에 기록됩니다.

---

## 2. 오프라인 문서 — `:help wplus-keymaps`

`:help wplus-keymaps` 또는 `:help wplus-<module>`(예: `:help wplus-lsp`)로
모듈별 키맵·명령·설정을 볼 수 있습니다. 이 문서는 `test/test_keys.vim`이
검사합니다 — 런타임에 등록된 `<leader>` 매핑이 문서에 없으면 테스트가
실패하므로, 문서와 동작이 다시 어긋날 수 없습니다.

---

## 3. 기본값이 없는 매핑

`<leader>ar/ae/af/am`(AI 리뷰·설명·리팩토링·커밋 메시지)처럼 **사용자가 직접
바인딩해야 하는** 키는 `.vimrc.example`에 예시로 들어 있습니다. 플러그인 기본
제공 여부는 `:WplusKeys`에서 바로 확인할 수 있습니다.

```vim
" 직접 바인딩 예시
vnoremap <leader>ar :WaiReview<CR>
vnoremap <leader>ae :WaiExplain<CR>
vnoremap <leader>af :WaiRefactor<CR>
nnoremap <leader>am :WaiCommitMsg<CR>
```

> 플러그인은 네이티브 `<Tab>`이나 일반 Vim 기본 키를 덮어쓰지 않습니다. AI 제안
> 수락을 원하면 `imap <Tab> <Plug>WaiSmartTab`처럼 사용자 설정에서 직접 연결하세요.

VS Code 단축키 정렬은 `let g:wplus_vscode_keymaps = 1`로 opt-in합니다(기본 `0`).
켠 상태의 키 목록은 `:WplusKeys`에서 바로 확인하세요.

---

## 4. VS Code 단축키 정렬 (opt-in)

`let g:wplus_vscode_keymaps = 1`로 켜면 VS Code 단축키가 그대로 동작합니다.
기본값은 `0`(꺼짐)이라 기존 사용자에게 영향을 주지 않습니다.

| VS Code | 동작 |
| --------- | ------ |
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

---

## 5. 창 이동 매핑 (직접 추가)

플러그인 기본값에 없는 항목입니다.

```vim
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l
```

LSP의 기존 `K`, `gd`, `gy`, `gr`, `[d`/`]d`, Insert `<C-s>` 키맵은
`let g:wplus_lsp_native_keymaps = 1`로 opt-in할 수 있습니다. 기본값은 `0`입니다.
