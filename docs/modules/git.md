# Git 연동 모듈

> [← README](../../README.md) · [전체 단축키](../keymaps.md) · [설정 레퍼런스](../config.md)

---

## gitgutter — Sign 컬럼 diff

git 변경사항을 sign 컬럼에 실시간 표시 (비동기).

| 기호 | 의미 |
| ------ | ------ |
| `┃` (녹색) | 추가된 줄 |
| `┃` (노란색) | 수정된 줄 |
| `▁` (빨간색) | 삭제된 줄 |

파일 저장 및 `CursorHold` 이벤트에 자동 갱신됩니다.

| 키 / 명령 | 동작 |
| ----------- | ------ |
| `]h` / `[h` | 다음/이전 hunk 이동 |
| `<leader>hp` | 커서 위치 hunk 미리보기 |
| `<leader>hs` | 커서 위치 hunk 스테이징 |
| `<leader>hr` / `:WplusGitRevertHunk` | 커서 위치 hunk 원복 |

```vim
let g:wplus_gitgutter_sign_add    = '┃'
let g:wplus_gitgutter_sign_change = '┃'
let g:wplus_gitgutter_sign_delete = '▁'
```

---

## blame — 인라인 Git Blame

커서가 있는 줄 끝에 커밋 정보를 흐린 색으로 표시합니다 (text-property 기반, 비동기).

| 키 / 명령 | 동작 |
|-----------|------|
| `:BlamerToggle` | blame 표시 켜기/끄기 |

```vim
let g:wplus_blame_delay       = 500                      " 표시까지 지연 (ms)
let g:wplus_blame_prefix      = '   '                    " 줄 끝 앞 여백
let g:wplus_blame_template    = '<author>, <date> • <summary>'
let g:wplus_blame_date_format = '%y/%m/%d'
```

템플릿 변수: `<author>`, `<date>`, `<summary>`, `<hash>`

---

## diffview — Git Diff 뷰어

현재 파일 또는 저장소 전체의 Git 변경사항을 시각적으로 확인합니다.

| 키 / 명령 | 동작 |
| ----------- | ------ |
| `<leader>gd` | 현재 파일의 Git Diff 열기 |
| `<leader>gD` | 저장소 전체의 Git Diff 열기 |
| `q` | Diff 뷰어 닫기 |

> `]h` / `[h` hunk 이동은 gitgutter 모듈이 담당합니다 (diffview는 순수 뷰어).

---

## conflict — Git 충돌 해결

Git merge 충돌(`<<<<<<<`, `=======`, `>>>>>>>`)을 시각적으로 감지하고 해결합니다.

| 명령 | 동작 |
| ------ | ------ |
| `:WconflictNext` | 다음 충돌로 이동 |
| `:WconflictPrev` | 이전 충돌로 이동 |
| `:WconflictOurs` | ours(HEAD) 버전 선택 |
| `:WconflictTheirs` | theirs(incoming) 버전 선택 |
| `:WconflictBoth` | 둘 다 선택 (ours + theirs) |

```vim
let g:wplus_conflict_auto_highlight = 1   " 충돌 영역 자동 강조
```

**키 매핑 예시:**

```vim
nnoremap <leader>cn :WconflictNext<CR>
nnoremap <leader>co :WconflictOurs<CR>
nnoremap <leader>ct :WconflictTheirs<CR>
nnoremap <leader>cb :WconflictBoth<CR>
```
