# AGENTS.md — vim-wplus 개발 가이드라인

이 문서는 **vim-wplus** 프로젝트를 개발, 수정, 유지보수하는 개발자와 AI 에이전트를 위한 가이드라인입니다.
이 프로젝트의 모든 기능 추가 및 버그 수정은 **TDD(Test-Driven Development, 테스트 주도 개발)** 방식을 따릅니다.

---

## 1. 프로젝트 철학과 핵심 원칙

1. **Zero External Dependencies (의존성 없는 순수 Vim)**
   - 외부 플러그인(fzf, coc.nvim, vim-themis 등)이나 외부 바이너리 의존성 없이, **Vim 9.1+ 내장 기능**(`+job`, `+channel`, `+popupwin`, `+signs`, `+textprop`, `assert_*`)만으로 동작해야 합니다.
2. **Keymap Hygiene (키맵 위생과 비간섭성)**
   - **네이티브 키 탈취 금지**: Vim의 기본 키(`.`, `<C-a>`, `<C-x>`, `<Tab>` 등)를 전역에서 덮어쓰지 않습니다.
   - **접두 그림자(Prefix Shadow) 금지**: 짧은 매핑이 더 긴 매핑의 접두어가 되어 `timeoutlen` 지연을 유발해서는 안 됩니다. (예: `<leader>ff`, `<leader>fb` 등 2글자 이상 네임스페이스 접두어 사용).
   - 모든 키맵 변경은 `autoload/wplus/health.vim`의 검사를 통과해야 합니다.
3. **Fail-Closed Security & Privacy (보안 및 민감 정보 보호)**
   - AI 전송 시 `.env`, `private key`, 실제 비밀값 리터럴(`api_key = '...'`)은 자동 차단되어야 합니다.
   - 단, `$ENV_VAR`, `cfg.key`, 빈 따옴표(`''`), 플레이스홀더 등 안전한 참조는 오탐(False-Positive) 없이 통과해야 합니다.

---

## 2. TDD 개발 사이클 (Red-Green-Refactor)

새로운 기능을 추가하거나 버그를 수정할 때 **반드시 아래 순서를 준수**합니다.

```
[1. 실패하는 테스트 작성 (RED)] ──> [2. 최소 구현 (GREEN)] ──> [3. 전체 검증 및 리팩토링 (REFACTOR)]
```

### 단계 1: 실패하는 테스트 작성 (RED)
* `test/test_<feature>.vim` 파일에 요구사항 또는 버그 재현 테스트를 작성합니다.
* 특정 테스트만 격리 실행하여 의도대로 **실패(RED)**하는지 확인합니다:
  ```bash
  ./test/run.sh <feature_name>
  # 예: ./test/run.sh ai_providers
  ```

### 단계 2: 최소 코드 구현 (GREEN)
* `autoload/wplus/<module>.vim` 및 관련 모듈에 기능을 구현합니다.
* 테스트가 **통과(GREEN)**하는지 확인합니다:
  ```bash
  ./test/run.sh <feature_name>
  ```

### 단계 3: 전체 회귀 테스트 및 Health 검증 (REFACTOR)
* 전체 테스트 스위트를 실행하여 기존 기능이 깨지지 않았는지 확인합니다:
  ```bash
  ./test/run.sh
  ```
* `:WplusHealth` 검사를 통해 키맵 충돌이나 미등록 옵션이 없는지 확인합니다:
  ```bash
  vim -es -u test/vimrc -c "call wplus#health#check()" -c "qall!"
  ```

---

## 3. 테스트 작성 규칙 및 패턴

테스트 러너는 `test/run.sh`이며, Vim 8+ 내장 `assert_*` 함수와 `v:errors`를 기반으로 실행됩니다.

### 1) 기본 테스트 템플릿
```vim
function! Test_my_feature_behavior() abort
    " 1. 모듈 초기화
    call wplus#my_module#setup()

    " 2. 버퍼 격리 (필요한 경우)
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile

    " 3. 실행 및 단정 (Assertion)
    call setline(1, ['line 1', 'line 2'])
    call assert_equal('expected', wplus#my_module#do_something())
    call assert_true(wplus#my_module#is_valid())
    call assert_false(wplus#my_module#has_error())

    " 4. 정리 (Teardown)
    bwipeout!
endfunction
```

### 2) 테스트 작성 시 주의사항
* **네트워크 I/O 절대 금지**: AI 모듈 등 외부 통신이 필요한 기능은 실제 HTTP 요청을 보내지 않고, 생성된 payload 딕셔너리/JSON 구조를 `json_decode()`로 검증합니다.
* **내부 함수 테스트 패턴**: `s:` 스크립트 로컬 함수를 직접 테스트해야 하는 경우, 모듈 하단에 `wplus#<module>#_test_<func>()` 형태의 테스트용 공개 브릿지를 제공합니다.
* **버퍼 정리 필수**: 테스트 중 버퍼를 생성한 경우 `bwipeout!`으로 반드시 정리하여 다른 테스트에 영향을 주지 않도록 합니다.

---

## 4. 새 모듈 / 옵션 / 키맵 추가 시 체크리스트

1. **설정 변수(`g:wplus_*`) 추가 시**:
   - `autoload/wplus/health.vim`의 `s:known_options` 리스트에 반드시 등록해야 합니다. (미등록 시 `:WplusHealth`에서 경고 발생)
   - `.vimrc.example` 및 `docs/config.md`에 기본값과 설명을 동기화합니다.
2. **키 매핑 추가 시**:
   - 접두 그림자가 발생하는지 확인 (`wplus#health#shadowed_maps()` 검사).
   - `.vimrc.example` 및 `docs/keymaps.md`에 문서화합니다.
3. **모듈 등록**:
   - `plugin/wplus.vim`의 `s:modules` 로드 순서 배열에 새 모듈을 등록합니다.

---

## 5. Vimscript 코딩 컨벤션

* 모든 함수는 예외 발생 시 즉시 중단되도록 **`abort` 속성을 필수**로 붙입니다:
  ```vim
  function! s:my_function(arg1, arg2) abort
  ```
* 변수 스코프를 명확하게 접두어로 표기합니다:
  - `l:` — 함수 로컬 변수
  - `a:` — 함수 인자
  - `s:` — 스크립트 파일 로컬 변수/함수
  - `g:` — 전역 변수
  - `b:` — 버퍼 로컬 변수
* 정규식 사용 시 검색 모드(`\v`, `\m`, `\c`, `\C`)를 명시하여 사용자의 `&magic`, `&ignorecase` 설정에 영향을 받지 않도록 합니다.
