#!/usr/bin/env bash
# =============================================================================
#  vim-wplus 설치 스크립트 (매니저 없이 pack/ 직접 설치)
#
#  용도: vim-plug / dein / packer 등 플러그인 매니저 없이
#        Vim 8+ / NeoVim 내장 pack 디렉토리로 vim-wplus 를 설치/업데이트 합니다.
#
#  지원: Vim, NeoVim  |  Linux / macOS / WSL / Windows(Git Bash)
#
#  사용법 (3가지 방식):
#    1) curl 원라이너 (파이프 실행)          ← 가장 간편, 요즘 표준
#       curl -fsSL https://raw.githubusercontent.com/wkqco33/vim-wplus/master/install.sh | bash
#       # 옵션 포함 예:
#       curl -fsSL https://raw.githubusercontent.com/wkqco33/vim-wplus/master/install.sh | bash -s -- --with-rc
#
#    2) 다운로드 후 실행
#       curl -fsSL -o install.sh https://raw.githubusercontent.com/wkqco33/vim-wplus/master/install.sh
#       bash install.sh
#
#    3) 로컬 복제본에서 실행
#       git clone https://github.com/wkqco33/vim-wplus.git && cd vim-wplus
#       ./install.sh
#
#  옵션:
#    --vim       Vim 강제
#    --nvim      NeoVim 강제
#    --update    이미 설치된 것을 업데이트(git pull)
#    --with-rc   .vimrc.example 을 사용자 설정에 복사(백업 후)
#    --help
#
#  ⚠ 보안: curl | bash 는 원격 스크립트를 즉시 실행합니다.
#  실행 전에 스크립트 내용을 확인하고 싶다면 먼저 다운로드해 검토하세요:
#    curl -fsSL https://raw.githubusercontent.com/wkqco33/vim-wplus/master/install.sh | less
# =============================================================================

set -euo pipefail

REPO_URL="https://github.com/wkqco33/vim-wplus.git"
PLUGIN_NAME="vim-wplus"

# ── 기본값 ────────────────────────────────────────────────────────────────
MODE="install"        # install | update
TARGET=""             # vim | nvim  (비어 있으면 자동 감지)
WITH_RC=0

# ── 색상 ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_G="\033[0;32m"; C_Y="\033[0;33m"; C_R="\033[0;31m"; C_B="\033[1;34m"; C_N="\033[0m"
else
    C_G=""; C_Y=""; C_R=""; C_B=""; C_N=""
fi
info()  { echo -e "${C_G}[wplus]${C_N} $*"; }
warn()  { echo -e "${C_Y}[wplus]${C_N} $*" >&2; }
error() { echo -e "${C_R}[wplus]${C_N} $*" >&2; }
die()   { error "$*"; exit 1; }

# ── 인자 파싱 ─────────────────────────────────────────────────────────────
# curl | bash 처럼 파이프로 실행되면 $0 이 bash 가 되므로, 표시용 이름을 고정.
SELF="install.sh"

usage() {
    cat <<EOF
vim-wplus 직접 설치 스크립트

사용법: ${SELF} [옵션]
  (curl | bash 로 실행할 때는: curl -fsSL <URL> | bash -s -- [옵션])

옵션:
  --vim       Vim 을 대상으로 설치
  --nvim      NeoVim 을 대상으로 설치
  --update    이미 설치된 vim-wplus 를 최신으로 업데이트(git pull)
  --with-rc   .vimrc.example 을 사용자 설정 파일로 복사(기존 파일은 백업)
  --help      이 도움말 표시

대상 지정이 없으면 Vim/NeoVim 설치 여부를 자동 감지합니다.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vim)   TARGET="vim" ;;
        --nvim)  TARGET="nvim" ;;
        --update) MODE="update" ;;
        --with-rc) WITH_RC=1 ;;
        --help|-h) usage; exit 0 ;;
        *) die "알 수 없는 옵션: $1  ($0 --help 로 도움말 확인)" ;;
    esac
    shift
done

# ── 사전 조건 확인 ─────────────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || die "git 이 필요합니다. 먼저 설치해 주세요."

detect_editor() {
    if [[ -n "$TARGET" ]]; then
        return
    fi
    if command -v nvim >/dev/null 2>&1; then
        TARGET="nvim"
    elif command -v vim >/dev/null 2>&1; then
        TARGET="vim"
    else
        die "Vim 과 NeoVim 을 모두 찾을 수 없습니다. --vim 또는 --nvim 으로 지정해 주세요."
    fi
}
detect_editor

# ── 대상별 경로 결정 ───────────────────────────────────────────────────────
if [[ "$TARGET" == "nvim" ]]; then
    PACK_DIR="${NVIM_PACK_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack}"
    RC_FILE="${NVIM_RC:-${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.vim}"
    RC_EXAMPLE=".vimrc.example"
else
    PACK_DIR="${VIM_PACK_DIR:-$HOME/.vim/pack}"
    RC_FILE="${VIMRC:-$HOME/.vimrc}"
    RC_EXAMPLE=".vimrc.example"
fi

DEST="$PACK_DIR/user/start/$PLUGIN_NAME"

info "대상 편집기  : ${C_B}$TARGET${C_N}"
info "설치 위치    : ${C_B}$DEST${C_N}"
info "모드         : ${C_B}$MODE${C_N}"

# ── 설치 / 업데이트 ────────────────────────────────────────────────────────
if [[ "$MODE" == "update" ]]; then
    if [[ ! -d "$DEST/.git" ]]; then
        die "업데이트 대상이 없습니다: $DEST  (--update 없이 실행해 먼저 설치해 주세요.)"
    fi
    info "업데이트 진행 중..."
    git -C "$DEST" pull --ff-only --rebase || \
        die "git pull 실패. 로컬 변경 사항이 있는지 확인해 주세요."
    info "업데이트 완료."
else
    mkdir -p "$PACK_DIR/user/start"
    if [[ -d "$DEST/.git" ]]; then
        warn "이미 설치되어 있습니다. 최신 상태로 업데이트합니다."
        git -C "$DEST" pull --ff-only --rebase
    else
        info "복제 진행 중: $REPO_URL"
        git clone --depth 1 "$REPO_URL" "$DEST"
    fi
    info "설치 완료."
fi

# ── 도움말 태그 생성 ───────────────────────────────────────────────────────
install_helptags() {
    # 주의: curl | bash 로 파이프 실행될 때 스크립트의 stdin 은 파이프(스크립트 본문)다.
    # vim -es / nvim --headless 는 stdin 에서 명령을 읽으므로, 남은 스크립트를
    # 삼키지 않도록 반드시 < /dev/null 로 stdin 을 닫는다.
    if command -v nvim >/dev/null 2>&1 && [[ "$TARGET" == "nvim" ]]; then
        nvim --headless "+helptags $DEST/doc" +qa </dev/null >/dev/null 2>&1 || true
    elif command -v vim >/dev/null 2>&1; then
        vim -es "+helptags $DEST/doc" +qall </dev/null >/dev/null 2>&1 || true
    fi
    info "도움말 태그(helptags)를 생성했습니다.  :help wplus"
}
install_helptags

# ── .vimrc 복사 (선택) ────────────────────────────────────────────────────
copy_rc() {
    local src="$DEST/$RC_EXAMPLE"
    [[ -f "$src" ]] || die "예시 설정 파일을 찾을 수 없습니다: $src"

    if [[ -f "$RC_FILE" ]]; then
        local backup="$RC_FILE.wplus.bak.$(date +%Y%m%d%H%M%S)"
        cp "$RC_FILE" "$backup"
        warn "기존 설정 백업: $backup"
    fi
    cp "$src" "$RC_FILE"
    info "예시 설정 복사 완료: $RC_FILE"
    warn "기존 설정을 덮어썼습니다. 기존 .vimrc 의 설정이 사라질 수 있으니 확인하세요."
}

if [[ "$WITH_RC" == "1" ]]; then
    copy_rc
fi

# ── 완료 안내 ─────────────────────────────────────────────────────────────
echo
info "────────────────────────────────────────────────────────"
info " 설치가 완료되었습니다!"
info "  대상   : $TARGET"
info "  경로   : $DEST"
echo
if [[ "$TARGET" == "vim" ]]; then
    info "  다음 줄을 ~/.vimrc 에 추가하세요(이미 있으면 생략):"
    info '    set runtimepath+=~/.vim/pack/user/start/vim-wplus'
else
    info "  다음 줄을 ~/.config/nvim/init.vim 에 추가하세요:"
    info '    set runtimepath+=~/.local/share/nvim/site/pack/user/start/vim-wplus'
fi
echo
info "  Vim 을 재시작한 뒤 확인:"
info "    :WplusHealth   (건강 검사 / 키맵 충돌 확인)"
info "    :help wplus    (도움말)"
info "────────────────────────────────────────────────────────"
echo
