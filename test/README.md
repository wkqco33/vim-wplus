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

## 핵심 회귀 방지 검증 항목

본 테스트 스위트는 아래 핵심 결함 및 회귀 시나리오를 지속적으로 검증합니다.

| 검증 항목 | 대상 모듈 | 해결 및 검증 내용 |
|---|---|---|
| 네이티브 키 (`.`, `<C-a>`, `<C-x>`) 보존 | `repeat.vim`, `multicursor.vim` | 전역 탈취 방지 및 전용 키맵 격리 검증 |
| `]h` / `[h` Hunk 이동 키맵 소유권 | `gitgutter.vim`, `diffview.vim` | gitgutter 단독 소유 및 이중 정의 방지 |
| 접두 그림자(Prefix Shadow) 방지 | `finder.vim`, `project.vim` 등 | 2글자 이상 네임스페이스 키맵으로 지연 방지 |
| 오퍼레이터 접두어 예외 정상성 | `surround.vim`, `commentary.vim` | `ys`, `gc` 등 모션 대기 오퍼레이터 정상 동작 |
| 명령어 명칭 정합성 | `harpoon.vim` | `:WharpoonAdd/Remove/List` 명령 정상 등록 |
| 자동 괄호 완성 및 백스페이스 엣지 케이스 | `pairs.vim` | `i(<BS>` 시 닫는 괄호 동시 삭제 및 따옴표 중복 방지 |

## 테스트 추가

`test/test_<name>.vim` 를 만들고 `assert_*` 를 쓰면 된다. 러너가 자동으로 집는다.

- 네트워크 호출 금지 — AI provider 테스트는 payload 를 만들어 `json_decode` 로 검증한다
- 버퍼를 쓰면 `enew!` + `setlocal buftype=nofile` 로 시작하고 끝에 `bwipeout!`
- 내부 구현(`s:` 함수, 스크립트 변수)이 아니라 관찰 가능한 동작을 단정한다.
  그래야 리팩터를 견딘다
- 키맵 충돌 검사는 `wplus#health#*` 를 쓴다. `:WplusHealth` 와 동일한 구현을
  공유하므로 탐지 로직이 두 벌로 갈라지지 않는다
