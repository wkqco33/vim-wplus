# 전체 설정 레퍼런스

> [← README](../README.md) · [단축키](keymaps.md) · [AI 가이드](ai.md)

모든 설정 변수는 `plugin/wplus.vim` 로드 **전**에 선언해야 합니다.

---

## 모듈 활성화/비활성화

```vim
" 패턴: g:wplus_<모듈명>_enabled = 0 (기본값 1)
let g:wplus_blame_enabled         = 0
let g:wplus_indent_enabled        = 0
let g:wplus_yankhighlight_enabled = 0
let g:wplus_fold_enabled          = 0
```

---

## 편집 모듈

```vim
" ── yankhighlight ────────────────────────────────────────────────────────
let g:wplus_yank_duration = 250            " 복사 강조 지속 시간 (ms)
```

---

## 탐색 모듈

```vim
" ── finder ───────────────────────────────────────────────────────────────
let g:wplus_finder_width_ratio  = 0.7     " 팝업 너비 비율 (0.0–1.0)
let g:wplus_finder_height_ratio = 0.4     " 팝업 높이 비율 (0.0–1.0)
let g:wplus_finder_fuzzy_limit  = 10000   " matchfuzzy 최대 항목 수

" ── explorer ─────────────────────────────────────────────────────────────
let g:wplus_explorer_max_entries = 1000   " 최대 표시 항목 수
let g:wplus_explorer_max_depth   = 8      " 최대 재귀 깊이

" ── harpoon ──────────────────────────────────────────────────────────────
let g:wplus_harpoon_max_slots = 4         " 파일 슬롯 수

" ── history ──────────────────────────────────────────────────────────────
let g:wplus_history_max          = 50     " 표시할 최대 파일 수
let g:wplus_history_project_only = 0      " 1이면 기본으로 프로젝트 내 파일만
```

---

## Git 모듈

```vim
" ── gitgutter ────────────────────────────────────────────────────────────
let g:wplus_gitgutter_sign_add    = '┃'
let g:wplus_gitgutter_sign_change = '┃'
let g:wplus_gitgutter_sign_delete = '▁'

" ── blame ────────────────────────────────────────────────────────────────
let g:wplus_blame_delay       = 500       " 표시 지연 (ms)
let g:wplus_blame_prefix      = '   '
let g:wplus_blame_template    = '<author>, <date> • <summary>'
let g:wplus_blame_date_format = '%y/%m/%d'

" ── conflict ─────────────────────────────────────────────────────────────
let g:wplus_conflict_auto_highlight = 1
```

---

## UI 모듈

```vim
" ── indent ───────────────────────────────────────────────────────────────
let g:wplus_indent_char       = '▏'
let g:wplus_indent_ft_exclude = ['help', 'nerdtree', 'undotree', 'tagbar']

" ── illuminate ───────────────────────────────────────────────────────────
let g:wplus_illuminate_delay    = 200     " 하이라이트 지연 (ms)
let g:wplus_illuminate_ft_block = ['help', 'nerdtree']

" ── theme ────────────────────────────────────────────────────────────────
let g:wplus_theme_auto = 1                 " 배경 자동 감지 및 통합 테마 적용
```

---

## 코드 도구 모듈

```vim
" ── lsp ──────────────────────────────────────────────────────────────────
let g:wplus_lsp_log_enabled  = 0          " 디버그 로그 (lsp.log)
let g:wplus_lsp_signcolumn   = 'yes'      " signcolumn 기본값
let g:wplus_lsp_cache_ttl    = 300        " definition/reference 캐시 TTL (초)
let g:wplus_lsp_sig_delay    = 100        " 시그니처 힌트 지연 (ms)
let g:wplus_lsp_change_delay = 800        " 텍스트 변경 → didChange 지연 (ms)
let g:wplus_lsp_diag_delay   = 300        " 진단 갱신 지연 (ms)

" ── fold ─────────────────────────────────────────────────────────────────
let g:wplus_fold_method     = 'indent'    " 'indent' | 'lsp' | 'syntax'
let g:wplus_fold_level      = 99          " 초기 foldlevel
let g:wplus_fold_min_lines  = 1
let g:wplus_fold_column     = 0           " foldcolumn 너비 (0=숨김)
let g:wplus_fold_ft_exclude = ['help', 'quickfix', 'qf', 'undotree']

" ── run ──────────────────────────────────────────────────────────────────
" %s = 파일 경로, %r = 확장자 없는 파일명
let g:wplus_run_commands     = {}         " 파일타입별 실행 명령 오버라이드
let g:wplus_build_commands   = {}         " 빌드 마커별 명령 오버라이드
let g:wplus_run_use_terminal = 1          " 1=터미널, 0=quickfix

" ── session ──────────────────────────────────────────────────────────────
let g:wplus_session_autoload  = 1
let g:wplus_session_autosave  = 1
let g:wplus_session_max_files = 50

" ── project ──────────────────────────────────────────────────────────────
let g:wplus_project_config    = '.wplus.vim'
let g:wplus_project_verbose   = 0
let g:wplus_project_trust_all = 0            " 1이면 보안 프롬프트 건너뛰고 모든 .wplus.vim 신뢰

" ── scratch ──────────────────────────────────────────────────────────────
let g:wplus_scratch_file   = expand('~/.vim/scratch.txt')
let g:wplus_scratch_height = 15            " 수평 분할 높이
let g:wplus_scratch_ft     = 'markdown'    " 스크래치 파일타입

" ── marks ────────────────────────────────────────────────────────────────
let g:wplus_marks_sign_prefix = ''         " Sign 텍스트 앞 접두어

" ── todo ─────────────────────────────────────────────────────────────────
let g:wplus_todo_keywords = ['TODO', 'FIXME', 'HACK', 'BUG', 'XXX']
```

---

## AI 모듈

> 상세 내용 → **[docs/ai.md](ai.md)**

```vim
" ── 공통 ─────────────────────────────────────────────────────────────────
let g:wplus_ai_provider    = 'openai'     " 'openai' | 'claude' | 'azure' | 'ollama'
let g:wplus_ai_api_key     = ''           " API 키 (환경변수 권장: $OPENAI_API_KEY)
let g:wplus_ai_model       = ''           " 모델명 (필수)
let g:wplus_ai_temperature = 0.7
let g:wplus_ai_max_tokens  = 2000
let g:wplus_ai_commit_diff_max_bytes = 32768  " 커밋 메시지 diff 최대 바이트 (32KB)
let g:wplus_ai_commit_max_tokens = 2048       " 커밋 메시지 최대 토큰 수
let g:wplus_ai_commit_prompt = ''             " 커스텀 커밋 프롬프트 ({stat}, {diff} 치환)
let g:wplus_ai_tab_complete = 1               " 스마트 탭 활성화 (Ghost text -> 팝업 -> 인덴트)
let g:wplus_ai_timeout     = 30           " 명령어 타임아웃 (초)

" ── Azure ────────────────────────────────────────────────────────────────
let g:wplus_ai_azure_resource    = ''
let g:wplus_ai_azure_deployment  = ''
let g:wplus_ai_azure_api_version = '2024-02-15-preview'

" ── Ollama ───────────────────────────────────────────────────────────────
let g:wplus_ai_ollama_host       = 'http://localhost:11434'
let g:wplus_ai_ollama_keep_alive = '30m'
let g:wplus_ai_ollama_fim        = 0      " FIM 활성화
let g:wplus_ai_ollama_think      = 0      " 추론 모델 think 활성화 (Ghost Text에도 적용)
let g:wplus_ai_ollama_options    = {}     " 샘플링 옵션 오버라이드

" ── Ghost Text ───────────────────────────────────────────────────────────
let g:wplus_ai_suggest_enabled       = 1
let g:wplus_ai_suggest_delay         = 500
let g:wplus_ai_suggest_context_lines = 50
let g:wplus_ai_suggest_suffix_lines  = 20
let g:wplus_ai_suggest_max_tokens    = 500
let g:wplus_ai_suggest_max_lines     = 3
let g:wplus_ai_suggest_temperature   = 0.2
let g:wplus_ai_suggest_timeout       = 10
let g:wplus_ai_suggest_debug         = 0
let g:wplus_ai_response_max_bytes    = 1048576  " AI 응답 최대 크기
let g:wplus_ai_request_max_bytes     = 262144   " AI 요청 최대 크기 (pipe 정체 방지)
let g:wplus_ai_block_sensitive_context = 1      " 민감 파일/비밀 패턴 전송 차단
let g:wplus_ai_sensitive_files       = ['.env', '.env.*', '*.pem', '*.key', '*.p12', '*.pfx', '*credential*', '*secret*', '*password*', '*token*']
" 정말 필요한 경우에만 일시적으로 사용. cloud provider로 비밀이 전송될 수 있음.
let g:wplus_ai_allow_sensitive_context = 0
```
