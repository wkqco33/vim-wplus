# 편집 강화 모듈

> [← README](../../README.md) · [전체 단축키](../keymaps.md) · [설정 레퍼런스](../config.md)

---

## commentary — 주석 토글

`&commentstring`에서 언어별 주석 기호를 자동으로 읽습니다.

| 키 | 모드 | 동작 |
|----|------|------|
| `gcc` | Normal | 현재 줄 주석 토글 |
| `gc{motion}` | Normal | motion 범위 주석 토글 (예: `gc3j`, `gcip`) |
| `gc` | Visual | 선택 범위 주석 토글 |

---

## surround — 괄호·따옴표 조작

| 키 | 동작 | 예시 |
|----|------|------|
| `ys{motion}{char}` | 감싸기 | `ysiw"` → `hello` → `"hello"` |
| `yss{char}` | 현재 줄 감싸기 | `yss(` → `( line )` |
| `cs{old}{new}` | 변경 | `cs"'` → `"hello"` → `'hello'` |
| `ds{char}` | 제거 | `ds"` → `"hello"` → `hello` |
| `S{char}` | Visual 선택 감싸기 | `viwS(` → `(hello)` |

**지원 문자**: `( ) [ ] { } < > " ' \`` 및 HTML 태그 (`t`)

---

## pairs — 자동 괄호 완성

| 동작 | 설명 |
|------|------|
| `(` 입력 | `()` 자동 완성, 커서를 안에 위치 |
| `"` 입력 | `""` 자동 완성 |
| `<BS>` | 빈 쌍 `()` 안에서 backspace → 양쪽 모두 삭제 |
| `)` 입력 | 닫는 괄호가 이미 있으면 skip |

지원: `( ) [ ] { } " ' \``

---

## textobj — 텍스트 오브젝트

### 들여쓰기 블록 (`ii` / `ai`)

| 키 | 동작 |
|----|------|
| `ii` | 현재 들여쓰기 수준의 블록 선택 (Python 함수 바디 등) |
| `ai` | 들여쓰기 블록 + 위 헤더 줄 포함 (`def foo():` 포함) |

`dii`, `vii`, `cii`, `yii`, `>ii` 등 모든 operator와 조합 가능.

### 함수 인자 (`ia` / `aa`)

```
function(arg1, arg2, arg3)
               ^^^^
               ia (inner argument)
```

| 키 | 동작 |
|----|------|
| `ia` | 인자 안쪽 (공백 제외) |
| `aa` | 인자 + 인접 쉼표 포함 |

중첩 괄호를 인식하므로 `f(a, g(b, c), d)`에서도 올바르게 동작합니다.

---

## multicursor — 다중 커서

| 키 | 모드 | 동작 |
|----|------|------|
| `<C-n>` | Normal | 커서 아래 단어의 다음 일치 항목을 다중 선택에 추가 |
| `<C-x>` | Normal | 현재 다중 선택 항목 중 가장 최근 것을 취소하고 다음 항목 선택 |
| `<C-a>` | Normal | 현재 버퍼 내 모든 동일 단어 한 번에 다중 선택 |
| `c` | Normal | 선택된 모든 항목 치환 (입력 프롬프트 팝업) |
| `d` | Normal | 선택된 모든 항목 삭제 |
| `<Esc>` | Normal | 멀티커서 모드 종료 및 다중 선택 해제 |

---

## register — 레지스터 미리보기

Vim 레지스터 내용을 사용하기 전에 팝업 윈도우로 미리보기합니다.

| 키 | 모드 | 동작 |
|----|------|------|
| `"` | Normal | 레지스터 선택용 팝업 표시 (이후 레지스터 키 입력 시 원래 동작 수행) |
| `@` | Normal | 매크로 실행용 레지스터 팝업 표시 |

---

## yankhighlight — 복사 피드백

`y` 계열 명령으로 복사할 때 선택 영역이 잠시 강조됩니다.

```vim
let g:wplus_yank_duration = 250   " 강조 지속 시간 (ms)
```

하이라이트 색상 변경:

```vim
highlight WplusYankHL guibg=#fabd2f guifg=#282828
```
