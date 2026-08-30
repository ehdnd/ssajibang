#!/usr/bin/env bash
#
# 싸지방 초기 세팅 — 새 PC에서 한 번만 실행
#   cloudflared / IDE(JetBrains Toolbox | VS Code) / PowerToys / ssh config / 헬퍼 스크립트
#
# 사전조건: Git for Windows 설치 완료 (Git Bash에서 실행)
#
#   curl -fsSL https://raw.githubusercontent.com/ehdnd/ssajibang/main/setup-ssh/setup.sh | bash
#
#   설치할 IDE 선택 (기본: toolbox) — connect.sh 와 동일한 이름:
#     ... | bash -s -- toolbox   # JetBrains Toolbox (기본)
#     ... | bash -s -- vscode    # VS Code
#     ... | bash -s -- both      # 둘 다
#

set -eu

# ─────────────────────────────────────────────────────────────
# 설정
# ─────────────────────────────────────────────────────────────
MAC_USER="taeung"
SSH_HOST="ssh.11104002.xyz"
LOCAL_PORT=2222
KEY="$HOME/.ssh/id_ed25519_mac"

GH_OWNER="ehdnd"
GH_REPO="ssajibang"
GH_SUBDIR="setup-ssh"
RAW_BASE="https://raw.githubusercontent.com/${GH_OWNER}/${GH_REPO}/main/${GH_SUBDIR}"

PTB_FILE="settings_134282238737369559.ptb"
PTB_DIR="$HOME/Documents/PowerToys/Backup"

BIN_DIR="$HOME/bin"
TMP="$(mktemp -d)"

# ─────────────────────────────────────────────────────────────
# 헬퍼
# ─────────────────────────────────────────────────────────────
log()  { printf '\033[32m[setup]\033[0m %s\n' "$1"; }
warn() { printf '\033[33m[setup] WARN:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31m[setup] ERROR:\033[0m %s\n' "$1" >&2; exit 1; }

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

win_build() {
  reg query 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' //v CurrentBuild 2>/dev/null \
    | grep -oE '[0-9]{4,}' | tail -1
}

# ─────────────────────────────────────────────────────────────
# 설치할 IDE 선택 (connect.sh 와 동일: toolbox | vscode | both)
#   나머지(cloudflared/PowerToys/ssh config/헬퍼)는 선택과 무관하게 항상 설치
# ─────────────────────────────────────────────────────────────
case "${1:-toolbox}" in
  toolbox|tb)      IDE=toolbox ;;
  vscode|vs|code)  IDE=vscode  ;;
  both|all)        IDE=both    ;;
  -h|--help|help)
    echo "usage: setup.sh [toolbox|vscode|both]"
    exit 0 ;;
  *)
    die "알 수 없는 IDE: $1  (toolbox | vscode | both)" ;;
esac
log "설치할 IDE: $IDE"

mkdir -p "$BIN_DIR"
cd "$TMP"

# ─────────────────────────────────────────────────────────────
# 1) cloudflared  (필수 — 실패 시 중단)
# ─────────────────────────────────────────────────────────────
case "${PROCESSOR_ARCHITECTURE:-AMD64}" in
  x86|X86) CF_ARCH="386"   ;;
  *)       CF_ARCH="amd64" ;;
esac

log "cloudflared 최신 릴리스 확인 (arch: ${CF_ARCH})"
CF_URL="$(curl -fsSL https://api.github.com/repos/cloudflare/cloudflared/releases/latest 2>/dev/null \
          | grep -o "https://[^\"]*cloudflared-windows-${CF_ARCH}\.exe" | head -1)" || true

# API 레이트리밋 대비 — 고정 latest 경로로 폴백
if [ -z "$CF_URL" ]; then
  warn "GitHub API 실패 (레이트리밋?) — latest/download 경로로 폴백"
  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-${CF_ARCH}.exe"
fi

log "cloudflared 다운로드"
curl -fsSL -o "$BIN_DIR/cloudflared.exe" "$CF_URL" || die "cloudflared 다운로드 실패"
chmod +x "$BIN_DIR/cloudflared.exe"
"$BIN_DIR/cloudflared.exe" --version >/dev/null 2>&1 || die "cloudflared 실행 불가"
log "cloudflared 완료: $("$BIN_DIR/cloudflared.exe" --version 2>&1 | head -1)"

# PATH 등록
if ! grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$BIN_DIR:$PATH"

# ─────────────────────────────────────────────────────────────
# 2) IDE  (IDE 값에 따라 toolbox / vscode / 둘 다 — 실패해도 계속)
# ─────────────────────────────────────────────────────────────
install_toolbox() {
  log "JetBrains Toolbox 다운로드"
  if curl -fsSL -o toolbox.exe \
       "https://download.jetbrains.com/product?code=TBA&latest&distribution=windows"; then
    log "Toolbox 설치 (조용히 진행, 1~2분)"
    if MSYS_NO_PATHCONV=1 ./toolbox.exe /S; then
      log "Toolbox 완료"
    else
      warn "Toolbox 설치 실패 — 수동 설치 필요: https://www.jetbrains.com/toolbox-app/"
    fi
  else
    warn "Toolbox 다운로드 실패 — 건너뜀"
  fi
}

install_vscode() {
  # User Installer — 관리자 권한 불필요. connect.sh 가 찾는 경로(VSCODE_USER)에 설치됨:
  #   $HOME/AppData/Local/Programs/Microsoft VS Code/Code.exe
  VSC_DIR="$HOME/AppData/Local/Programs/Microsoft VS Code"
  VSC_EXE="$VSC_DIR/Code.exe"
  VSC_CLI="$VSC_DIR/bin/code.cmd"

  log "VS Code 다운로드 (User Installer, x64)"
  if curl -fsSL -o vscode.exe \
       "https://update.code.visualstudio.com/latest/win32-x64-user/stable"; then
    log "VS Code 설치 (조용히 진행)"
    # Inno Setup: 프롬프트/재부팅/설치후 자동실행 없이
    MSYS_NO_PATHCONV=1 ./vscode.exe /VERYSILENT /NORESTART /MERGETASKS='!runcode' || true

    # 인스톨러가 백그라운드로 빠지는 경우가 있어 설치 완료를 폴링
    for _ in $(seq 1 30); do
      [ -f "$VSC_EXE" ] && break
      sleep 2
    done

    if [ -f "$VSC_EXE" ]; then
      log "VS Code 완료: $VSC_EXE"
      # Remote-SSH 확장 — connect.sh 로 바로 붙을 수 있게 미리 설치
      if [ -f "$VSC_CLI" ]; then
        log "Remote-SSH 확장 설치"
        if MSYS_NO_PATHCONV=1 "$VSC_CLI" --install-extension ms-vscode-remote.remote-ssh --force >/dev/null 2>&1; then
          log "Remote-SSH 확장 완료"
        else
          warn "Remote-SSH 확장 설치 실패 — VS Code 에서 수동 설치하세요"
        fi
      else
        warn "code CLI 없음 — Remote-SSH 확장은 VS Code 에서 수동 설치하세요"
      fi
    else
      warn "VS Code 설치 확인 실패 — 수동 설치 필요: https://code.visualstudio.com/"
    fi
  else
    warn "VS Code 다운로드 실패 — 건너뜀"
  fi
}

case "$IDE" in
  toolbox) install_toolbox ;;
  vscode)  install_vscode  ;;
  both)    install_toolbox; install_vscode ;;
esac

# ─────────────────────────────────────────────────────────────
# 3) PowerToys  (빌드 19041 이상, 실패해도 계속)
# ─────────────────────────────────────────────────────────────
BUILD="$(win_build)"
if [ -n "$BUILD" ] && [ "$BUILD" -ge 19041 ] 2>/dev/null; then
  log "PowerToys 최신 버전 확인 (Windows build $BUILD)"
  PT_URL="$(curl -fsSL https://api.github.com/repos/microsoft/PowerToys/releases/latest 2>/dev/null \
            | grep -o 'https://[^"]*PowerToysUserSetup-[^"]*-x64\.exe' | head -1)" || true
  if [ -n "$PT_URL" ] && curl -fsSL -o pt.exe "$PT_URL"; then
    if MSYS_NO_PATHCONV=1 ./pt.exe /install /quiet /norestart; then
      log "PowerToys 완료"
    else
      warn "PowerToys 설치 실패 — 건너뜀"
    fi
  else
    warn "PowerToys 다운로드 실패 — 건너뜀"
  fi
else
  warn "Windows build ${BUILD:-unknown} (19041 미만) — PowerToys 건너뜀"
fi

# PowerToys 설정 백업 파일
log "PowerToys 설정 백업 다운로드"
mkdir -p "$PTB_DIR"
if curl -fsSL -o "$PTB_DIR/$PTB_FILE" "${RAW_BASE}/${PTB_FILE}"; then
  log "설정 백업: $PTB_DIR/$PTB_FILE"
else
  warn ".ptb 다운로드 실패 — repo 파일명 확인"
fi

# ─────────────────────────────────────────────────────────────
# 4) ssh config
# ─────────────────────────────────────────────────────────────
log "ssh config 생성"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

cat > "$HOME/.ssh/config" << EOF
Host mac
    HostName 127.0.0.1
    Port ${LOCAL_PORT}
    User ${MAC_USER}
    IdentityFile ~/.ssh/id_ed25519_mac
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
chmod 600 "$HOME/.ssh/config"
log "ssh config 완료: ~/.ssh/config"

# ─────────────────────────────────────────────────────────────
# 5) 헬퍼 스크립트
# ─────────────────────────────────────────────────────────────
log "헬퍼 스크립트 다운로드"
for s in connect.sh stop.sh; do
  if curl -fsSL -o "$BIN_DIR/$s" "${RAW_BASE}/${s}"; then
    chmod +x "$BIN_DIR/$s"
    log "  $BIN_DIR/$s"
  else
    warn "$s 다운로드 실패"
  fi
done

# ─────────────────────────────────────────────────────────────
# 6) 개인키 안내
# ─────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════════════"
if [ -f "$KEY" ]; then
  chmod 600 "$KEY"
  log "개인키가 이미 있습니다 — 건너뜀"
else
  BW_URL="https://vault.bitwarden.com/#/login"
  log "Bitwarden 로그인 페이지를 브라우저로 엽니다: $BW_URL"
  # explorer.exe 는 성공해도 exit 1 을 반환하므로 종료코드는 무시
  MSYS_NO_PATHCONV=1 explorer.exe "$BW_URL" 2>/dev/null || true

  cat << 'GUIDE'
  다음은 수동입니다 — 개인키 배치

  1) 열린 브라우저에서 Bitwarden 로그인 → 개인키 전체 복사
     (-----BEGIN 부터 -----END OPENSSH PRIVATE KEY----- 까지)

  2) 아래 명령을 복사해서 실행하고, 붙여넣은 뒤 Enter → Ctrl+D

     cat > ~/.ssh/id_ed25519_mac

  3) 권한 설정과 검증 (아래 두 줄을 복사해서 실행)

     chmod 600 ~/.ssh/id_ed25519_mac
     ssh-keygen -y -f ~/.ssh/id_ed25519_mac >/dev/null && echo "키 정상"

     → passphrase 묻고 "키 정상" 나오면 성공
     → "invalid format" 이면 붙여넣기가 잘린 것:
         sed -i 's/\r$//' ~/.ssh/id_ed25519_mac
       후 다시 검증. 그래도 안 되면 1)부터 다시.
GUIDE
fi
echo "════════════════════════════════════════════════════════════"
echo
log "세팅 완료 (IDE: $IDE). 새 Git Bash 창을 연 뒤 접속하려면:"
echo
case "$IDE" in
  toolbox) echo "    connect.sh          # Toolbox" ;;
  vscode)  echo "    connect.sh vscode   # VS Code" ;;
  both)
    echo "    connect.sh          # Toolbox (기본)"
    echo "    connect.sh vscode   # VS Code"
    echo "    connect.sh both     # 둘 다"
    ;;
esac
echo
