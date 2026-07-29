# AI 어시스턴트 가이드

> [← README](../README.md) · [전체 단축키](keymaps.md) · [설정 레퍼런스](config.md)

vim-wplus의 `ai` 모듈은 OpenAI, Claude, Azure OpenAI, Ollama(로컬)를 지원하는 통합 AI 코드 어시스턴트입니다.

---

## 빠른 시작

```vim
" ~/.vimrc
let g:wplus_ai_provider = 'openai'
let g:wplus_ai_api_key  = 'sk-...'
let g:wplus_ai_model    = 'gpt-4o'
```

```vim
" 기본 키 매핑 예시
vnoremap <leader>ar :WaiReview<CR>
vnoremap <leader>ae :WaiExplain<CR>
vnoremap <leader>af :WaiRefactor<CR>
nnoremap <leader>am :WaiCommitMsg<CR>
inoremap <expr> <Tab> wplus#ai#accept_suggestion()
```

---

## 명령어 목록

| 명령 | 모드 | 동작 |
|------|------|------|
| `:WaiComment` | Normal / Visual | 현재 코드에 주석 생성 |
| `:WaiComplete` | Normal | 다음 줄 코드 완성 제안 |
| `:'<,'>WaiRefactor` | Visual | 선택 범위 리팩토링 제안 |
| `:'<,'>WaiReview` | Visual | 선택 코드 리뷰 (버그·보안·개선점) |
| `:'<,'>WaiExplain` | Visual | 선택 코드 단계별 설명 |
| `:WaiCommitMsg` | Normal | 스테이징된 변경으로 커밋 메시지 생성 |
| `:WaiFixDiag` | Normal | 현재 줄 LSP 진단 자동 수정 |
| `:WaiToggleSuggest` | Normal | Ghost Text 자동완성 토글 |

---

## 응답 미리보기 팝업

모든 명령은 AI 응답을 즉시 버퍼에 쓰지 않고 **중앙 팝업**으로 먼저 보여줍니다.

| 키 | 동작 |
|----|------|
| `<CR>` 또는 `a` | 수락 — 버퍼에 적용 |
| `<Esc>` · `q` · 기타 | 취소 — 버퍼 변경 없음 |

- **Comment / Complete** → 커서 아래에 삽입
- **Refactor / FixDiag** → 선택 범위를 결과로 교체
- **CommitMsg** → 레지스터 `"`, `+`에 복사 (gitcommit 버퍼면 1번째 줄에 삽입)
- **Review / Explain** → 하단 분할창에 markdown으로 표시 (`q` 닫기)

---

## 프로바이더 설정

### OpenAI

```vim
let g:wplus_ai_provider    = 'openai'
let g:wplus_ai_api_key     = 'sk-...'
let g:wplus_ai_model       = 'gpt-4o'        " 또는 'gpt-3.5-turbo'
let g:wplus_ai_temperature = 0.7
let g:wplus_ai_max_tokens  = 2000
```

### Claude (Anthropic)

```vim
let g:wplus_ai_provider = 'claude'
let g:wplus_ai_api_key  = 'sk-ant-...'
let g:wplus_ai_model    = 'claude-3-5-sonnet-20241022'
```

### Azure OpenAI

```vim
let g:wplus_ai_provider            = 'azure'
let g:wplus_ai_api_key             = 'your-azure-key'
let g:wplus_ai_model               = 'gpt-4'
let g:wplus_ai_azure_resource      = 'your-resource'       " 리소스 이름
let g:wplus_ai_azure_deployment    = 'gpt-4-deployment'    " 배포명
let g:wplus_ai_azure_api_version   = '2024-02-15-preview'
```

### Ollama (로컬)

```vim
let g:wplus_ai_provider          = 'ollama'
let g:wplus_ai_model             = 'qwen2.5-coder:7b'  " 또는 codellama 등
let g:wplus_ai_ollama_host       = 'http://localhost:11434'
let g:wplus_ai_ollama_keep_alive = '30m'   " 모델을 메모리에 유지 (재로딩 방지)
let g:wplus_ai_ollama_fim        = 1       " FIM(Fill-In-Middle) 활성화 (코드 완성 품질 향상)
let g:wplus_ai_ollama_think      = 0       " 추론 모델 사용 여부 (기본 off)
```

> **Ollama 팁**: `keep_alive = '30m'`이면 코드를 읽다가 돌아와도 모델이 내려가지 않아 첫 응답 지연을 방지합니다. 무한 유지는 `'-1'`, 즉시 해제는 `'0'`.

---

## Ghost Text 자동완성

InsertMode에서 타이핑을 멈추면 AI가 다음 코드를 회색 ghost text로 제안합니다.

### 동작 방식

1. 타이핑 후 `suggest_delay` ms 경과 → API 요청
2. 응답 도착 → 커서 뒤에 회색 ghost text 표시
3. `<Tab>` → 제안 수락 (전체 또는 단어 단위)
4. 다른 키 / `<Esc>` → 제안 취소

### 수락 키 설정

```vim
" Ghost Text 전체 수락
inoremap <expr> <Tab> wplus#ai#accept_suggestion()

" 단어 단위 수락
inoremap <expr> <C-Right> wplus#ai#accept_word_suggestion()

" 명시적 취소
inoremap <C-e> <Cmd>WaiDismissSuggest<CR>
```

> `<Tab>`을 snippet 점프나 LSP 완성에 이미 사용 중이면 `<C-g>` 등 다른 키를 사용하세요.

### Ghost Text 설정

```vim
let g:wplus_ai_suggest_enabled       = 1     " 활성화
let g:wplus_ai_suggest_delay         = 500   " 제안 지연 (ms)
let g:wplus_ai_suggest_context_lines = 50    " 커서 앞 컨텍스트 줄 수
let g:wplus_ai_suggest_suffix_lines  = 20    " 커서 뒤 컨텍스트 줄 수
let g:wplus_ai_suggest_max_tokens    = 500   " 제안 최대 토큰
let g:wplus_ai_suggest_max_lines     = 3     " 제안 최대 줄 수
let g:wplus_ai_suggest_temperature   = 0.2   " 코드 완성 온도 (낮을수록 정확)
let g:wplus_ai_suggest_timeout       = 10    " 자동완성 타임아웃 (초)
let g:wplus_ai_suggest_debug         = 0     " 디버그 로그
```

### Adaptive Delay

빠르게 타이핑할 때 불필요한 API 호출을 줄이기 위해 5회 연속 타이핑 이후 `delay`가 자동으로 2배로 늘어납니다.

### FIM (Fill-In-Middle) — Ollama 전용

코드 전용 모델(`qwen2.5-coder` 등)에서 커서 앞뒤 컨텍스트를 모두 활용하여 중간을 채웁니다.  
일반 chat 방식보다 코드 완성 품질이 크게 향상됩니다.

```vim
let g:wplus_ai_ollama_fim = 1
```

모델이 FIM을 지원하지 않으면 자동으로 chat 방식으로 폴백합니다.

---

## 스트리밍 설정

```vim
let g:wplus_ai_stream           = 1   " 스트리밍 응답 (기본 활성화)
let g:wplus_ai_stream_min_chars = 20  " 첫 ghost text 렌더링 최소 누적 문자
let g:wplus_ai_timeout          = 30  " 명령어 타임아웃 (초)
let g:wplus_ai_suggest_timeout  = 10  " 자동완성 타임아웃 (초)
```

> SSE를 버퍼링하는 프록시를 사용하는 경우 `let g:wplus_ai_stream = 0`으로 비활성화하세요.

---

## 컨텍스트 추출 (`ai/context.vim`)

Ghost Text와 명령어는 다음 컨텍스트를 자동으로 수집합니다:

- **prefix** — 커서 앞 `suggest_context_lines` 줄
- **suffix** — 커서 뒤 `suggest_suffix_lines` 줄
- **scope** — 현재 함수/클래스 선언부
- **symbols** — 열린 동일 언어 버퍼의 주요 심볼 (ctags 연동)

지원 언어: Go, Python, TypeScript, JavaScript, Rust, Java, Kotlin, Ruby, Lua, C/C++

---

## 주의사항

- `WaiFixDiag`는 `lsp.vim`이 해당 파일타입에 대해 LSP 서버가 실행 중이어야 합니다.
- `WaiCommitMsg`는 git 저장소 안에서 실행해야 하며 스테이징된 변경이 있어야 합니다 (`git add` 먼저).
- API 키는 `.vimrc`에 직접 쓰지 않고 환경 변수를 읽어오는 방식을 권장합니다:

```vim
let g:wplus_ai_api_key = $OPENAI_API_KEY
```
