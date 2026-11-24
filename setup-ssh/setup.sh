#!/usr/bin/env bash
#
# 싸지방 초기 세팅 — 새 PC에서 한 번만 실행
#
# 사전조건: Git for Windows 설치 완료 (Git Bash에서 실행)
#
#   curl -fsSL https://raw.githubusercontent.com/ehdnd/ssajibang/main/setup-ssh/setup.sh | bash -s -- [구성요소...]
#
#   항상 설치: cloudflared · ssh config · 헬퍼 스크립트(connect.sh, stop.sh) · 개인키 안내
#
#   구성요소 — 여러 개, 순서 무관. connect.sh 와 같은 이름:
#     toolbox       JetBrains Toolbox
#     vscode        VS Code + Remote-SSH 확장
#     herdr         WezTerm(zip) + ~/.wezterm.lua   (herdr 자체는 맥에: brew install herdr)
#     pt|powertoys  PowerToys + 설정 백업(.ptb)
#     none          항상 설치 항목만 (인자 없음과 같음. 다른 구성요소와 함께 오면 무시)
#
#   예)  ... | bash -s -- vscode herdr
#        ... | bash -s -- toolbox pt
#
#   WezTerm 은 안정판으로 고정. 다른 버전: WEZTERM_VERSION=<태그|nightly>
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
GH_REF="${SSAJIBANG_REF:-main}"   # 브랜치 테스트: SSAJIBANG_REF=<branch> 로 헬퍼 스크립트도 그 브랜치에서 받음
RAW_BASE="https://raw.githubusercontent.com/${GH_OWNER}/${GH_REPO}/${GH_REF}/${GH_SUBDIR}"

PTB_FILE="settings_134282238737369559.ptb"
PTB_DIR="$HOME/Documents/PowerToys/Backup"

BIN_DIR="$HOME/bin"

# WezTerm — zip 을 풀기만 하는 포터블 설치 (관리자 권한 불필요). connect.sh 가 같은 경로를 쓴다.
WEZTERM_VERSION="${WEZTERM_VERSION:-20240203-110809-5046fc22}"   # 안정판 (매 PC 같은 버전)
WEZTERM_DIR="$BIN_DIR/wezterm"
WEZTERM_CONF="$HOME/.wezterm.lua"

TMP="$(mktemp -d)"

USAGE="usage: setup.sh [toolbox] [vscode] [herdr] [pt]   (인자 없음 = none: 항상 설치 항목만)"

WANT_TOOLBOX=0
WANT_VSCODE=0
WANT_HERDR=0
WANT_PT=0

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

# 고른 구성요소 목록 (표시용)
selected() {
  local s=""
  if [ "$WANT_TOOLBOX" = 1 ]; then s="$s toolbox"; fi
  if [ "$WANT_VSCODE"  = 1 ]; then s="$s vscode";  fi
  if [ "$WANT_HERDR"   = 1 ]; then s="$s herdr";   fi
  if [ "$WANT_PT"      = 1 ]; then s="$s pt";      fi
  echo "${s# }"
}

# ─────────────────────────────────────────────────────────────
# 인자 파싱 — 구성요소 목록 (여러 개, 순서 무관)
# ─────────────────────────────────────────────────────────────
parse_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      toolbox)        WANT_TOOLBOX=1 ;;
      vscode)         WANT_VSCODE=1  ;;
      herdr)          WANT_HERDR=1   ;;
      pt|powertoys)   WANT_PT=1      ;;
      none)           ;;   # 항상 설치 항목만 — 다른 구성요소와 함께 오면 무시
      -h|--help|help) echo "$USAGE"; exit 0 ;;
      *)              die "알 수 없는 구성요소: $arg  ($USAGE)" ;;
    esac
  done
}

# ─────────────────────────────────────────────────────────────
# cloudflared  (필수 — 실패 시 중단)
# ─────────────────────────────────────────────────────────────
install_cloudflared() {
  local arch url
  case "${PROCESSOR_ARCHITECTURE:-AMD64}" in
    x86|X86) arch="386"   ;;
    *)       arch="amd64" ;;
  esac

  log "cloudflared 최신 릴리스 확인 (arch: ${arch})"
  url="$(curl -fsSL https://api.github.com/repos/cloudflare/cloudflared/releases/latest 2>/dev/null \
         | grep -o "https://[^\"]*cloudflared-windows-${arch}\.exe" | head -1)" || true

  # API 레이트리밋 대비 — 고정 latest 경로로 폴백
  if [ -z "$url" ]; then
    warn "GitHub API 실패 (레이트리밋?) — latest/download 경로로 폴백"
    url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-${arch}.exe"
  fi

  log "cloudflared 다운로드"
  curl -fsSL -o "$BIN_DIR/cloudflared.exe" "$url" || die "cloudflared 다운로드 실패"
  chmod +x "$BIN_DIR/cloudflared.exe"
  "$BIN_DIR/cloudflared.exe" --version >/dev/null 2>&1 || die "cloudflared 실행 불가"
  log "cloudflared 완료: $("$BIN_DIR/cloudflared.exe" --version 2>&1 | head -1)"

  # PATH 등록
  if ! grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
  fi
  export PATH="$BIN_DIR:$PATH"
}

# ─────────────────────────────────────────────────────────────
# ssh config  (필수)
# ─────────────────────────────────────────────────────────────
write_ssh_config() {
  local agent_sock_win
  log "ssh config 생성"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  # IdentityAgent: connect.sh 가 ssh-agent 를 이 고정 소켓으로 띄운다.
  #   SSH_AUTH_SOCK 을 물려받지 못한 ssh(Toolbox/jetbrainsd 가 띄운 것 등)도 agent 를 찾게 한다.
  #   connect.sh 의 SSH_AUTH_SOCK 과 같은 문자열(C:/... 형식)이어야 한다.
  agent_sock_win="$(cygpath -m "$HOME/.ssh/agent.sock")"

  cat > "$HOME/.ssh/config" << EOF
Host mac
    HostName 127.0.0.1
    Port ${LOCAL_PORT}
    User ${MAC_USER}
    IdentityFile ~/.ssh/id_ed25519_mac
    IdentitiesOnly yes
    IdentityAgent ${agent_sock_win}
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
  chmod 600 "$HOME/.ssh/config"
  log "ssh config 완료: ~/.ssh/config"
}

# ─────────────────────────────────────────────────────────────
# 헬퍼 스크립트  (필수)
# ─────────────────────────────────────────────────────────────
install_helpers() {
  local s
  log "헬퍼 스크립트 다운로드"
  for s in connect.sh stop.sh; do
    if curl -fsSL -o "$BIN_DIR/$s" "${RAW_BASE}/${s}"; then
      chmod +x "$BIN_DIR/$s"
      log "  $BIN_DIR/$s"
    else
      warn "$s 다운로드 실패"
    fi
  done
}

# ─────────────────────────────────────────────────────────────
# toolbox  (선택 — 실패해도 계속)
# ─────────────────────────────────────────────────────────────
# 인스톨러가 설치 직후 Toolbox 를 띄우는 경우가 있다. 이 인스턴스는 ssh-agent 도
# SSH 실행 파일 설정(connect.sh 가 적용)도 없는 상태라, 그대로 두면 connect.sh 가
# "이미 실행 중" 으로 넘어가고 원격 접속 시 passphrase 를 묻는다 → 종료해 둔다.
stop_autostarted_toolbox() {
  for _ in $(seq 1 10); do
    if tasklist //FI "IMAGENAME eq jetbrains-toolbox.exe" //NH 2>/dev/null | grep -qiF jetbrains-toolbox.exe; then
      log "설치 직후 자동 실행된 Toolbox 종료 (connect.sh 가 설정 적용 후 다시 띄움)"
      taskkill //F //IM jetbrains-toolbox.exe //IM jetbrainsd.exe >/dev/null 2>&1 || true
      return
    fi
    sleep 1
  done
}

install_toolbox() {
  log "JetBrains Toolbox 다운로드"
  if curl -fsSL -o toolbox.exe \
       "https://download.jetbrains.com/product?code=TBA&latest&distribution=windows"; then
    log "Toolbox 설치 (조용히 진행, 1~2분)"
    if MSYS_NO_PATHCONV=1 ./toolbox.exe /S; then
      log "Toolbox 완료"
      stop_autostarted_toolbox
    else
      warn "Toolbox 설치 실패 — 수동 설치 필요: https://www.jetbrains.com/toolbox-app/"
    fi
  else
    warn "Toolbox 다운로드 실패 — 건너뜀"
  fi
}

# ─────────────────────────────────────────────────────────────
# vscode  (선택 — 실패해도 계속)
# ─────────────────────────────────────────────────────────────
install_vscode() {
  # User Installer — 관리자 권한 불필요. connect.sh 가 찾는 경로(VSCODE_USER)에 설치됨:
  #   $HOME/AppData/Local/Programs/Microsoft VS Code/Code.exe
  VSC_DIR="$HOME/AppData/Local/Programs/Microsoft VS Code"
  VSC_EXE="$VSC_DIR/Code.exe"
  # bin/code.cmd 는 cmd.exe 로만 실행되는데 싸지방은 cmd.exe 가 막혀 있다.
  # bin/code (sh 스크립트)는 cygpath 로 경로를 바꿔 Code.exe 를 node 모드로 직접 실행한다.
  VSC_CLI="$VSC_DIR/bin/code"

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
        if sh "$VSC_CLI" --install-extension ms-vscode-remote.remote-ssh --force >/dev/null 2>&1; then
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

# ─────────────────────────────────────────────────────────────
# herdr  (선택 — 실패해도 계속)
#   싸지방 쪽은 터미널(WezTerm)과 설정만 깐다. herdr 는 맥에서 돈다 (맥: brew install herdr).
#   WezTerm 은 이미 있으면 건너뛰고, ~/.wezterm.lua 는 내용이 다르면 .bak 으로 백업 후 덮어쓴다.
# ─────────────────────────────────────────────────────────────

# zip 압축 해제 — Git Bash 에는 unzip 이 없을 수 있어 Windows 내장 tar.exe(bsdtar)를 먼저 쓴다
unzip_to() {
  local zip="$1" dest="$2"
  if [ -f /c/Windows/System32/tar.exe ] \
     && /c/Windows/System32/tar.exe -xf "$zip" -C "$dest" 2>/dev/null; then
    return 0
  fi
  if command -v unzip >/dev/null 2>&1 && unzip -q "$zip" -d "$dest"; then
    return 0
  fi
  return 1
}

install_wezterm() {
  local url exe

  if [ -f "$WEZTERM_DIR/wezterm-gui.exe" ]; then
    log "WezTerm 이미 설치됨 — 건너뜀 ($WEZTERM_DIR)"
  else
    url="https://github.com/wezterm/wezterm/releases/download/${WEZTERM_VERSION}/WezTerm-windows-${WEZTERM_VERSION}.zip"
    log "WezTerm 다운로드 (${WEZTERM_VERSION})"
    if ! curl -fsSL -o wezterm.zip "$url"; then
      warn "WezTerm 다운로드 실패 — 건너뜀: $url"
      return 0
    fi

    log "WezTerm 압축 해제 → $WEZTERM_DIR"
    mkdir -p wezterm-unzip
    if ! unzip_to wezterm.zip wezterm-unzip; then
      warn "WezTerm 압축 해제 실패 (tar.exe/unzip 없음) — 직접 풀어서 $WEZTERM_DIR 에 두세요"
      return 0
    fi

    # zip 안의 버전 폴더(WezTerm-windows-<버전>/)를 벗겨 경로를 고정한다
    exe="$(find wezterm-unzip -name wezterm-gui.exe | head -1)"
    if [ -z "$exe" ]; then
      warn "zip 안에 wezterm-gui.exe 가 없음 — 건너뜀"
      return 0
    fi
    rm -rf "$WEZTERM_DIR"
    if ! mv "$(dirname "$exe")" "$WEZTERM_DIR"; then
      warn "WezTerm 을 $WEZTERM_DIR 로 옮기지 못함 — 건너뜀"
      return 0
    fi
    log "WezTerm 완료: $WEZTERM_DIR/wezterm-gui.exe"
  fi

  log "WezTerm 설정 다운로드 → ~/.wezterm.lua"
  if ! curl -fsSL -o wezterm.lua "${RAW_BASE}/wezterm.lua"; then
    warn "wezterm.lua 다운로드 실패 — 건너뜀"
    return 0
  fi
  if [ -f "$WEZTERM_CONF" ]; then
    if cmp -s wezterm.lua "$WEZTERM_CONF"; then
      log "~/.wezterm.lua 이미 최신"
      return 0
    fi
    cp "$WEZTERM_CONF" "$WEZTERM_CONF.bak" || { warn "기존 설정 백업 실패 — 덮어쓰지 않음"; return 0; }
    log "기존 설정 백업: ~/.wezterm.lua.bak"
  fi
  if cp wezterm.lua "$WEZTERM_CONF"; then
    log "WezTerm 설정 완료: ~/.wezterm.lua"
  else
    warn "~/.wezterm.lua 쓰기 실패"
  fi
}

# ─────────────────────────────────────────────────────────────
# pt  (선택 — 빌드 19041 이상, 실패해도 계속)
# ─────────────────────────────────────────────────────────────
install_powertoys() {
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
}

# ─────────────────────────────────────────────────────────────
# 개인키 안내  (필수 — 브라우저 + 수동 작업이라 마지막)
# ─────────────────────────────────────────────────────────────
guide_private_key() {
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
}

# ─────────────────────────────────────────────────────────────
# 마무리 안내 — 고른 구성요소에 맞는 connect.sh 명령
# ─────────────────────────────────────────────────────────────
print_next() {
  local sel
  sel="$(selected)"
  echo
  log "세팅 완료 (구성요소: ${sel:-none})"
  echo
  echo "  새 Git Bash 창을 연 뒤 접속:"
  echo
  echo "    connect.sh             # 터널만 (ssh mac)"
  if [ "$WANT_TOOLBOX" = 1 ]; then echo "    connect.sh toolbox     # JetBrains Toolbox"; fi
  if [ "$WANT_VSCODE"  = 1 ]; then echo "    connect.sh vscode      # VS Code"; fi
  if [ "$WANT_HERDR"   = 1 ]; then echo "    connect.sh herdr       # WezTerm 새 창 → 맥의 herdr"; fi
  if [ "$WANT_HERDR"   = 1 ]; then
    echo
    if [ -f "$WEZTERM_DIR/wezterm-gui.exe" ]; then
      echo "  WezTerm 직접 실행: $WEZTERM_DIR/wezterm-gui.exe"
    else
      echo "  WezTerm 이 설치되지 않음 — 위 경고 확인 후 setup herdr 를 다시 실행하세요"
    fi
  fi
  if [ -z "$sel" ]; then
    echo
    echo "  구성요소를 설치하려면 setup 명령 끝에 붙여 다시 실행 (여러 개, 순서 무관):"
    echo "    toolbox   JetBrains Toolbox"
    echo "    vscode    VS Code + Remote-SSH 확장"
    echo "    herdr     WezTerm + ~/.wezterm.lua"
    echo "    pt        PowerToys + 설정 백업"
  fi
  echo
}

# ─────────────────────────────────────────────────────────────
# main — 항상 설치 항목 먼저, 고른 구성요소, 개인키 안내는 마지막
# ─────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  if [ -n "$(selected)" ]; then
    log "구성요소: $(selected)"
  else
    log "구성요소 없음 (none) — 항상 설치 항목만 설치합니다"
  fi

  mkdir -p "$BIN_DIR"
  cd "$TMP"

  install_cloudflared
  write_ssh_config
  install_helpers

  if [ "$WANT_TOOLBOX" = 1 ]; then install_toolbox;   fi
  if [ "$WANT_VSCODE"  = 1 ]; then install_vscode;    fi
  if [ "$WANT_HERDR"   = 1 ]; then install_wezterm;   fi
  if [ "$WANT_PT"      = 1 ]; then install_powertoys; fi

  guide_private_key
  print_next
}

main "$@"
