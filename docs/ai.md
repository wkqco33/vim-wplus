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
" <Tab>은 기본 내장 스마트 탭으로 자동 지원됩니다. (g:wplus_ai_tab_complete=1)
```

---

## 명령어 목록

| 명령 | 모드 | 동작 |
| ------ | ------ | ------ |
| `:WaiComment` (또는 `:'<,'>WaiComment`) | Normal / Visual / Range | 현재 코드(또는 지정 범위)에 주석 생성 |
| `:WaiComplete` | Normal | 다음 줄 코드 완성 제안 |
| `:'<,'>WaiRefactor` (또는 `:WaiRefactor`) | Visual / Range | 선택 범위(또는 지정 범위) 리팩토링 제안 |
| `:'<,'>WaiReview` (또는 `:WaiReview`) | Visual / Range | 선택 코드 리뷰 (버그·보안·개선점) |
| `:'<,'>WaiExplain` (또는 `:WaiExplain`) | Visual / Range | 선택 코드 단계별 설명 |
| `:WaiCommitMsg` | Normal | 스테이징된 변경으로 커밋 메시지 생성 |
| `:WaiFixDiag` | Normal | 현재 줄 LSP 진단 자동 수정 |
| `:WaiToggleSuggest` | Normal | Ghost Text 자동완성 토글 |
| `:WaiCancel` | Normal | 진행 중인 AI 요청 및 Git 작업 모두 취소 (`<leader>ac`) |

`:WaiComplete`와 Ghost Text는 `g:wplus_ai_completion_model`을 사용하고, 리뷰·리팩토링·커밋 같은 명령은 `g:wplus_ai_model`을 사용합니다.

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

> **커밋 메시지 길이 자동 조절**: 변경 규모에 따라 프롬프트가 달라집니다. 변경이 적으면
> 한 줄 요약을 선호하고, 변경이 많으면(파일 5개 이상 또는 변경량 200줄 이상) 본문에
> 영역/모듈별 불릿으로 전체 범위를 반영하도록 요청합니다. diff가
> `g:wplus_ai_commit_diff_max_bytes`(기본 32KB)를 넘으면 파일 경계에서 잘라
> 중간에 잘린 파일이 생기지 않도록 합니다.

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

기본적으로 `g:wplus_ai_tab_complete = 1`이 설정되어 있어 `<Tab>`을 누르면:

1. Ghost Text가 표시 중이면 제안을 즉시 수락합니다.
2. 팝업 메뉴가 열려 있으면 다음 항목을 선택합니다 (`<C-n>`).
3. 그 외에는 일반 탭/들여쓰기를 수행합니다.

수동으로 매핑하거나 다른 키를 사용하려면:

```vim
" 스마트 탭 수락
inoremap <expr> <Tab> wplus#ai#smart_tab()

" Ghost Text 전체 수락 (<Plug> 매핑)
imap <Tab> <Plug>WaiSmartTab
" 또는: inoremap <expr> <Tab> wplus#ai#accept_suggestion()

" 단어 단위 수락
inoremap <expr> <C-Right> wplus#ai#accept_word_suggestion()

" 명시적 취소
inoremap <C-e> <Cmd>WaiDismissSuggest<CR>
```

### Ghost Text 설정

```vim
let g:wplus_ai_suggest_enabled       = 1     " 활성화
let g:wplus_ai_suggest_delay         = 500   " 제안 지연 (ms)
let g:wplus_ai_suggest_context_lines = 50    " 커서 앞 컨텍스트 줄 수
let g:wplus_ai_suggest_suffix_lines  = 20    " 커서 뒤 컨텍스트 줄 수
let g:wplus_ai_suggest_max_tokens    = 256   " 제안 최대 토큰 (3줄 UI에 맞춘 빠른 기본값)
let g:wplus_ai_suggest_max_lines     = 3     " 제안 최대 줄 수
let g:wplus_ai_suggest_temperature   = 0.2   " 코드 완성 온도 (낮을수록 정확)
let g:wplus_ai_suggest_timeout       = 10    " 자동완성 타임아웃 (초)
let g:wplus_ai_suggest_debug         = 0     " 디버그 로그
```

### 완성 전용 모델 분리

코드 완성(ghost text)은 커맨드(commit/comment/refactor 등)와 모델을 따로 지정할 수 있습니다.
`g:wplus_ai_completion_model`을 설정하면 완성만 해당 모델로, 그 외 명령은 `g:wplus_ai_model`로 실행됩니다.
미설정 시 `g:wplus_ai_model`을 그대로 사용하므로 단일 모델 구성은 변경 없이 동작합니다.

```vim
let g:wplus_ai_model             = 'deepseek-v4-flash'  " 커맨드(commit/comment/refactor/review)용
let g:wplus_ai_completion_model  = 'kimi-k2.7-code:cloud'   " 코드 완성(ghost text)용
```

클라우드 chat 완성 모델(예: `kimi-k2.7-code:cloud`)은 추론을 비활성화하고 FIM을 끄는 것이 안정적입니다:

```vim
let g:wplus_ai_ollama_think = 0   " 완성 속도 극대화
let g:wplus_ai_ollama_fim = 0     " chat 방식 (클라우드/chat 완성 모델)
```

로컬 FIM 지원 모델(예: `qwen2.5-coder`)을 완성 전용으로 쓰면:

- 완성 요청이 로컬에서 저지연 처리되고, 커맨드는 큰 클라우드 모델로 품질을 유지합니다.
- `g:wplus_ai_completion_model`이 FIM을 지원하면 `g:wplus_ai_ollama_fim = 1`일 때 자동으로 FIM 방식이 적용됩니다.

### Adaptive Delay

빠르게 타이핑할 때 불필요한 API 호출을 줄이기 위해 연속 입력 중에는 `delay`가 자동으로 2배로 늘어납니다. 입력을 잠시 멈추거나 Insert 모드를 다시 시작하면 카운터가 초기화됩니다.

### FIM (Fill-In-Middle) — Ollama 전용

코드 전용 모델(`qwen2.5-coder` 등)에서 커서 앞뒤 컨텍스트를 모두 활용하여 중간을 채웁니다.  
일반 chat 방식보다 코드 완성 품질이 크게 향상됩니다.

```vim
let g:wplus_ai_ollama_fim = 1
```

모델이 FIM을 지원하지 않으면 첫 오류 응답을 기준으로 해당 모델만 capability를 기억하고 chat 방식으로 폴백합니다. 설정한 FIM 옵션 자체는 유지되므로 다른 모델로 바꾸면 다시 FIM을 시도합니다. Ollama 모델 이름만으로 FIM 지원 여부를 확정할 수 없기 때문에 실제 `/api/generate` 응답을 사용합니다.

---

## 타임아웃 설정

```vim
let g:wplus_ai_timeout          = 30  " 명령어 타임아웃 (초)
let g:wplus_ai_suggest_timeout  = 10  " 자동완성 타임아웃 (초)
```

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
- `.env`, 인증서, 키/credential 파일 및 credential-like 패턴이 포함된 컨텍스트는 기본적으로 AI 전송이 차단됩니다. 특히 `WaiCommitMsg` 실행 시 스테이징된 파일 목록에 민감 파일(`.env`, `*.key`, `*.pem` 등)이 포함되어 있으면 diff 전송이 원천 차단됩니다.
- `WaiCancel`(`<leader>ac`) 실행 시 진행 중인 HTTP 요청뿐만 아니라 백그라운드 Git diff 수집 작업까지 즉시 종료됩니다.
- `ollama` provider라도 `*-cloud` 모델은 원격 서비스로 코드가 전송될 수 있습니다. 민감한 프로젝트에서는 로컬 모델을 사용하거나 자동 제안을 끄십시오.
- 응답에는 제어문자를 허용하지 않으며, 최대 응답 크기(`g:wplus_ai_response_max_bytes`)를 초과하면 요청을 중단합니다.
- API 키는 `.vimrc`에 직접 쓰지 않고 환경 변수를 읽어오는 방식을 권장합니다:

```vim
let g:wplus_ai_api_key = $OPENAI_API_KEY
```
