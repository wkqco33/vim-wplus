# wplus 테스트

```sh
./test/run.sh            # 전체
./test/run.sh pairs      # test_pairs.vim 만
VIM_BIN=/usr/bin/vim ./test/run.sh
```

## 왜 vim-themis 를 쓰지 않는가

vim-wplus 는 "의존성 없는 대체"를 표방하는 플러그인이다. 테스트 의존성을
벤더링하거나 `themis` 를 PATH 에 요구하는 것은 그 전제와 모순된다.
Vim 8+ 내장 `assert_equal` / `assert_true` / `assert_report` 와 `v:errors` 가
필요한 기능의 대부분을 제공하므로, `run.sh` 는 그 위에 얹은 40줄 러너다.

각 `test_*.vim` 은 독립된 Vim 프로세스에서 `test/vimrc` 로 실행된다.
`v:errors` 가 비어 있으면 통과, 하나라도 있으면 실패다. Vim 이 결과를 쓰기
전에 죽으면 그것도 실패로 처리한다 (이전 CI 는 `2>&1 || true` 로 크래시를
삼켜 통과했다).

## Phase 0 기준선: 의도적으로 RED

이 스위트는 **실패하는 상태로 커밋되었다.** 아래 16건은 감사에서 확인된
실제 결함이며, 각 Phase 가 동작했다는 증거는 해당 항목이 GREEN 으로
바뀌는 것이다.

| 실패 | 원인 | 해소 Phase |
|---|---|---|
| `.` / `<C-a>` / `<C-x>` 가 전역 매핑됨 | `repeat.vim:12`, `multicursor.vim:236-237` | 1, 2 |
| `]h` / `[h` 가 diffview 소유 | `gitgutter.vim:350` 과 `diffview.vim:130` 이중 정의, 로드 순서로 diffview 승 | 2 |
| `<Space>` 가 46개 매핑의 접두 | `whichkey.vim:142` 가 `<leader>` 자체를 완전 매핑으로 | 1 |
| `<Space>b` / `<Space>p` / `<Space>m` 접두 그림자 | `finder.vim:174-176` vs bufdelete/blame/project/marks | 2 |
| `ys` / `gc` 접두 그림자 | `surround.vim:158` vs `:160`, `commentary.vim:96` vs `:94` | 2 |
| `:WharpoonAdd/Remove/List` 미정의 | `harpoon.vim:134-136` 이 `:Wharoon*` 로 오타 | 4 |
| `i(<BS>` 가 `)` 를 남김 (2건) | `pairs.vim:19-22` off-by-one — `line[col('.')-3]` 을 읽음 | 4 |
| `don'` → `don''` (2건) | `pairs.vim:51-52` 가 커서 뒤 문자만 검사 | 4 |

## 테스트 추가

`test/test_<name>.vim` 를 만들고 `assert_*` 를 쓰면 된다. 러너가 자동으로 집는다.

- 네트워크 호출 금지 — AI provider 테스트는 payload 를 만들어 `json_decode` 로 검증한다
- 버퍼를 쓰면 `enew!` + `setlocal buftype=nofile` 로 시작하고 끝에 `bwipeout!`
- 내부 구현(`s:` 함수, 스크립트 변수)이 아니라 관찰 가능한 동작을 단정한다.
  그래야 리팩터를 견딘다
- 키맵 충돌 검사는 `wplus#health#*` 를 쓴다. `:WplusHealth` 와 동일한 구현을
  공유하므로 탐지 로직이 두 벌로 갈라지지 않는다
