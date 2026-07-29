# 변경 이력 (CHANGE LOG)

## [Unreleased] - 2026-07-29

### 신규 모듈 추가 (8개)

1. **Harpoon — 파일 북마크 (`autoload/wplus/harpoon.vim`)**
   - 최대 4개의 슬롯에 파일을 등록하고 `<leader>h1~4`로 즉시 이동.
   - 슬롯 데이터는 프로젝트 루트별 `~/.vim/harpoon/*.json`에 저장.
   - `<leader>ha` 추가, `<leader>hd` 제거, `<leader>hl` 팝업 목록.

2. **Marks — 마크 시각화 (`autoload/wplus/marks.vim`)**
   - Vim 내장 마크(a–z)를 Sign 컬럼에 노란 알파벳으로 표시.
   - `<leader>ml` 팝업 목록, `<leader>md` 커서 줄 마크 삭제.
   - `CmdlineLeave`/`BufEnter` 이벤트로 150ms 디바운스 자동 갱신.

3. **Scratch — 스크래치 버퍼 (`autoload/wplus/scratch.vim`)**
   - `~/.vim/scratch.txt`에 지속 저장되는 임시 버퍼.
   - `<leader>sc` 하단 토글, `<leader>sv` 수직 분할.
   - `BufLeave`, `VimLeavePre`에 자동 저장.

4. **Run — 코드 실행/빌드 (`autoload/wplus/run.vim`)**
   - 파일타입별 실행 명령(`g:wplus_run_commands`)으로 `<leader>rr` 실행.
   - `Makefile`, `package.json`, `Cargo.toml`, `go.mod` 등 빌드 시스템 자동 감지 (`<leader>rb`).
   - `<leader>rt` 테스트 실행. 터미널 또는 quickfix 출력 선택 가능.

5. **Project — 프로젝트별 설정 (`autoload/wplus/project.vim`)**
   - 프로젝트 루트의 `.wplus.vim` 자동 소스 (첫 진입 시 1회).
   - `<leader>pe` 설정 파일 편집, `<leader>pr` 재로드.
   - `.wplus.vim` 저장 시 자동 재로드.

6. **History — 최근 파일 브라우저 (`autoload/wplus/history.vim`)**
   - 세션 MRU + `v:oldfiles` 통합, finder 팝업으로 표시.
   - `<leader>fh` 전체, `<leader>fH` 프로젝트 내 파일만.

7. **Scrollbar — 미니맵 스크롤바 (`autoload/wplus/scrollbar.vim`)**
   - Sign 컬럼에 `▐`/`█` 트랙·썸 렌더링 (80ms 디바운스).
   - LSP 진단(에러/경고)을 `●`로 오버레이.
   - `<leader>sb` 토글, `WinScrolled`/`CursorMoved` 자동 갱신.

8. **Fold — 스마트 폴드 (`autoload/wplus/fold.vim`)**
   - 들여쓰기 기반 기본 폴드; `g:wplus_fold_method='lsp'`로 LSP foldingRange 연동.
   - `▶ 첫 줄 [N lines]` 형식의 커스텀 폴드 텍스트.
   - `<leader>zz/za/zc/zo` 단축키.

### AI 모듈 기능 추가 (`autoload/wplus/ai.vim`)

- **`:WaiReview`** — Visual 선택 코드를 리뷰 (버그·보안·개선점). 결과를 하단 분할창에 markdown으로 표시.
- **`:WaiExplain`** — Visual 선택 코드를 단계별로 설명.
- 리뷰/설명 결과창은 `q`로 닫히고 재호출 시 재사용됨.

---

## [Unreleased] - 2026-07-24

### 신규 기능 추가 (Features Added)
1. **LSP Inlay Hints 연동 (`autoload/wplus/lsp.vim`)**
   - `textDocument/inlayHint` capability 및 가상 텍스트(`WplusLspInlay` textprop) 렌더링 구현.
   - 변수 타입 및 파라미터 힌트를 에디터 라인 내에 실시간 표출 (`:WplusLspInlayHints` 및 자동 갱신).
2. **Ctags / Opened Buffer 기반 프로젝트 Sym-Cache 확장 (`autoload/wplus/ai/context.vim`)**
   - 열려 있는 동일 언어 버퍼들의 주요 클래스/함수 선언부 및 Ctags 파일 기반 심볼 추출 로직 구현.
   - AI 제안 컨텍스트 확장으로 코드 완료 품질 향상.
3. **Interactive Hunk Revert 기능 (`autoload/wplus/gitgutter.vim`)**
   - `:WplusGitRevertHunk` (`<leader>hr`) 명령 추가로 커서 위치의 Git diff 변경 조각을 즉시 원복 기능 제공.
4. **Async Streaming Grep 연동 (`autoload/wplus/grep.vim`)**
   - `wplus#grep#search_async` 구현으로 `rg`, `git grep` 등의 비동기 Job 실행 및 Quickfix 실시간 추가 지원.
5. **AI 추론 요청 Cancelation & Throttling 강화 (`autoload/wplus/ai.vim`)**
   - 연속 타이핑 시 진행 중이던 백그라운드 `curl` 스트리밍 잡을 `s:dismiss_suggestion` 호출 시 즉시 cancellation (`job_stop`) 처리하여 CPU/네트워크 자원 절약.

---

### 1단계: 핵심 오류 수정 및 안정성 강화
- **AI 모듈 (`autoload/wplus/ai.vim`)**
  - 스트리밍 수신 시 불완전한 JSON 청크 유실 문제 해결 (`out_mode: 'raw'` 설정 및 완성된 개행 단위 버퍼 파싱 적용).
  - `<expr>` 매핑 기반 수락 시 특수 키 입력 평가 재평가 위험 방지 (`feedkeys(..., 'n')` 대입 방식 적용).
  - 비동기 요청 오류 발생 시 `s:command_requests` 및 `s:command_channels` 메모리 해제 처리.
- **LSP 모듈 (`autoload/wplus/lsp.vim`)**
  - `s:apply_text_edits`의 라인 대체 알고리즘 수정 (단일 라인 범위 수정 시 라인 유실 방지).
- **GitGutter 모듈 (`autoload/wplus/gitgutter.vim`)**
  - `s:channel_key` 헬퍼 도입으로 채널 ID 기반 딕셔너리 조회를 통일하고 잡 데이터 누수 방지.

### 2단계: 성능 최우선 & UTF-8 바이트 처리 정비
- **LSP 모듈 (`autoload/wplus/lsp.vim`)**
  - RFC 3986 표준 기반 `s:url_encode` 및 `s:decode_uri_path` 작성 (한글/특수문자 파일 경로 URI 인코딩/디코딩 안정화).
  - `s:on_stdout` 패킷 분리 시 `strpart(..., ..., ..., 1)` 바이트 모드 적용 (LSP `Content-Length` 패킷 바이트 단위 정확 슬라이싱으로 `JSON_ERR` 차단).
- **AI 컨텍스트 모듈 (`autoload/wplus/ai/context.vim`)**
  - `get_prefix` 및 `get_suffix`의 커서 오프셋 슬라이싱 시 바이트 단위 `strpart` 적용 (다국어 문서 편집 중 제안 컨텍스트 추출 안정화).

### 3단계: 호환성 확대 및 예외 가드 정비
- **플러그인 진입점 (`plugin/wplus.vim`)**
  - `prop_type_get` 호출부 `has('textprop')` 예외 가드 추가.
