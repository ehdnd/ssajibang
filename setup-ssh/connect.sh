#!/usr/bin/env bash
#
# 맥 연결 — 매번 실행
#
#   connect.sh [target]
#     target: toolbox (기본) | vscode | both | none
#     별칭   : tb=toolbox, code/vs=vscode, all=both
#
#   공통 준비: 사전확인 → ssh-agent → (터널) → 검증
#   그 다음 target 앱 실행.
#
#   터널이 이미 살아 있으면(포워더 PID + ssh 응답) 재구축 없이 재사용한다.
#   → Toolbox 를 쓰는 중에 `connect.sh vscode` 를 실행해도 기존 세션이 끊기지 않는다.
#   → 이미 실행 중인 앱은 다시 죽이지 않는다 (그냥 "이미 실행 중" 안내).
#
#   ※ Git Bash 전용.
#
set -u

# ─────────────────────────────────────────────────────────────
# target 파싱
# ─────────────────────────────────────────────────────────────
case "${1:-toolbox}" in
  toolbox|tb)        TARGET=toolbox ;;
  vscode|vs|code)    TARGET=vscode  ;;
  both|all)          TARGET=both    ;;
  none|"")           TARGET=none    ;;
  -h|--help|help)
    echo "usage: connect.sh [toolbox|vscode|both|none]"
    exit 0 ;;
  *)
    printf '\033[31m[connect] ERROR:\033[0m 알 수 없는 target: %s\n' "$1" >&2
    echo "usage: connect.sh [toolbox|vscode|both|none]" >&2
    exit 1 ;;
esac

MAC_USER="taeung"
SSH_HOST="ssh.11104002.xyz"
LOCAL_PORT=2222
KEY="$HOME/.ssh/id_ed25519_mac"

GITBIN="/c/Program Files/Git/usr/bin"
TOOLBOX="$HOME/AppData/Local/JetBrains/Toolbox/bin/jetbrains-toolbox.exe"
VSCODE_USER="$HOME/AppData/Local/Programs/Microsoft VS Code/Code.exe"
VSCODE_SYS="/c/Program Files/Microsoft VS Code/Code.exe"
LOG="$HOME/.cache/cf-forwarder.log"
PIDFILE="$HOME/.cache/cf-forwarder.pid"
AGENT_ENV="$HOME/.ssh/agent.env"

# Cloudflare ICN 라우팅 패치
#   무료 플랜 도메인(172.67.x.x)은 한국에서 LAX 로 가서 600~1000ms 지연이 생긴다.
#   ICN 으로 가는 Cloudflare IP(172.66.x.x)를 hosts 에 박아 인천 엣지로 붙게 한다.
#   끄기: ICN_PATCH=0 connect.sh   /  IP 바꾸기: CF_ICN_IP=172.66.x.x connect.sh
ICN_PATCH="${ICN_PATCH:-1}"
CF_ICN_IP="${CF_ICN_IP:-172.66.44.186}"
CF_DOMAIN="11104002.xyz"
CF_SUBS="ssh web code"
HOSTS_FILE="${HOSTS_FILE:-/c/Windows/System32/drivers/etc/hosts}"
HOSTS_BEGIN="# >>> ssajibang icn >>>"
HOSTS_END="# <<< ssajibang icn <<<"

export PATH="$HOME/bin:$PATH"

log()  { printf '\033[32m[connect]\033[0m %s\n' "$1"; }
warn() { printf '\033[33m[connect] WARN:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31m[connect] ERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# Git 의 ssh.exe 를 쓰는 래퍼 (Toolbox/Gateway 와 동일 조건)
gssh() { PATH="$GITBIN:$PATH" ssh "$@"; }

mac_ok() {
  gssh -o BatchMode=yes \
       -o StrictHostKeyChecking=accept-new \
       -o ConnectTimeout=5 \
       -T mac 'echo ok' >/dev/null 2>&1
}

# 윈도우 프로세스 실행 여부 (IMAGENAME 정확히 일치)
proc_running() {
  tasklist //FI "IMAGENAME eq $1" //NH 2>/dev/null | grep -qiF "$1"
}

# hosts 에서 우리 블록과 도메인 관련 줄을 뺀 내용을 stdout 으로
hosts_stripped() {
  awk -v b="$HOSTS_BEGIN" -v e="$HOSTS_END" '
    { line = $0; sub(/\r$/, "", line) }
    line == b { skip = 1; next }
    line == e { skip = 0; next }
    skip { next }
    { print }
  ' "$HOSTS_FILE" | grep -viE "[[:space:]]([a-z0-9-]+\.)?${CF_DOMAIN//./\\.}([[:space:]]|$)"
}

# hosts 파일 덮어쓰기 — mv 대신 cat > 로 써서 원래 파일 권한(ACL)을 유지
hosts_write() {
  cat "$1" > "$HOSTS_FILE" 2>/dev/null
}

# 0: 변경함 / 1: 이미 적용됨 / 2: 쓰기 실패(관리자 권한 없음)
icn_apply() {
  local tmp="$HOME/.cache/hosts.new" s
  mkdir -p "$HOME/.cache"
  hosts_stripped > "$tmp"
  # 마지막 줄에 개행이 없으면 붙여서 줄이 이어지지 않게
  if [ -s "$tmp" ] && [ -n "$(tail -c1 "$tmp")" ]; then printf '\r\n' >> "$tmp"; fi
  {
    printf '%s\r\n' "$HOSTS_BEGIN"
    for s in $CF_SUBS; do printf '%s %s.%s\r\n' "$CF_ICN_IP" "$s" "$CF_DOMAIN"; done
    printf '%s\r\n' "$HOSTS_END"
  } >> "$tmp"
  if cmp -s "$tmp" "$HOSTS_FILE"; then rm -f "$tmp"; return 1; fi
  if ! hosts_write "$tmp"; then rm -f "$tmp"; return 2; fi
  rm -f "$tmp"
  ipconfig //flushdns >/dev/null 2>&1 || true
  return 0
}

# 패치 원복 (IP 가 죽었을 때 원래 DNS 로 돌아가기용)
icn_revert() {
  local tmp="$HOME/.cache/hosts.new"
  hosts_stripped > "$tmp"
  cmp -s "$tmp" "$HOSTS_FILE" || hosts_write "$tmp"
  rm -f "$tmp"
  ipconfig //flushdns >/dev/null 2>&1 || true
}

# 지금 SSH 호스트가 붙는 Cloudflare 데이터센터 (실패 시 빈 문자열)
cf_colo() {
  curl -s --max-time 5 "https://${SSH_HOST}/cdn-cgi/trace" 2>/dev/null \
    | tr -d '\r' | sed -n 's/^colo=//p'
}

# ─────────────────────────────────────────────────────────────
# 0) 사전 확인
# ─────────────────────────────────────────────────────────────
command -v cloudflared.exe >/dev/null 2>&1 \
  || die "cloudflared.exe 없음 — setup.sh 를 먼저 실행하세요"

[ -f "$KEY" ] \
  || die "개인키 없음: $KEY  (Bitwarden 에서 붙여넣으세요)"

[ -f "$HOME/.ssh/config" ] \
  || die "ssh config 없음 — setup.sh 를 먼저 실행하세요"

chmod 600 "$KEY" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# 1) ssh-agent — 살아있으면 재사용
# ─────────────────────────────────────────────────────────────
if [ -f "$AGENT_ENV" ]; then
  . "$AGENT_ENV" >/dev/null 2>&1 || true
fi

ssh-add -l >/dev/null 2>&1
case $? in
  0)
    log "키가 이미 agent 에 등록되어 있음"
    ;;
  1)
    log "키 등록 — passphrase 를 입력하세요"
    ssh-add "$KEY" || die "키 등록 실패 (passphrase 확인)"
    ;;
  *)
    log "ssh-agent 시작"
    ssh-agent -s > "$AGENT_ENV"
    . "$AGENT_ENV" >/dev/null
    log "키 등록 — passphrase 를 입력하세요"
    ssh-add "$KEY" || die "키 등록 실패 (passphrase 확인)"
    ;;
esac

# ─────────────────────────────────────────────────────────────
# 1.5) Cloudflare ICN 라우팅 — hosts 패치 (터널보다 먼저)
#    hosts 가 바뀌었으면 기존 포워더는 LAX 로 붙어 있으므로 강제 재구축
# ─────────────────────────────────────────────────────────────
FORCE_REBUILD=0
if [ "$ICN_PATCH" = 1 ]; then
  icn_apply
  case $? in
    0) log "hosts 패치 적용 → ${CF_ICN_IP} (ICN)"; FORCE_REBUILD=1 ;;
    1) log "hosts 패치 이미 적용됨" ;;
    2) warn "hosts 수정 실패 — Git Bash 를 '관리자 권한으로 실행' 해야 합니다 (LAX 경유로 계속)" ;;
  esac

  COLO="$(cf_colo)"
  if [ -z "$COLO" ]; then
    # 지정 IP 가 응답 없음 → 막혔을 수 있으니 원복해서 기본 경로로라도 접속
    warn "${CF_ICN_IP} 응답 없음 — hosts 패치를 원복하고 기본 경로로 접속합니다"
    warn "  다른 IP 시도: nslookup lucajournal.pages.dev → CF_ICN_IP=<172.66.x.x> connect.sh"
    icn_revert
    FORCE_REBUILD=1
  elif [ "$COLO" = ICN ]; then
    log "Cloudflare 엣지: ICN"
  else
    warn "Cloudflare 엣지: ${COLO} (ICN 아님) — 지연이 클 수 있습니다"
  fi
else
  log "ICN 패치 꺼짐 (ICN_PATCH=0)"
fi

# ─────────────────────────────────────────────────────────────
# 2) 터널 — 살아있으면 재사용, 아니면 재구축
#    재사용 조건: 강제 재구축 아님 + 포워더 PID 살아있음 + ssh 로 맥 응답
# ─────────────────────────────────────────────────────────────
if [ "$FORCE_REBUILD" = 0 ] \
   && [ -f "$PIDFILE" ] \
   && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null \
   && mac_ok; then
  log "터널 재사용 — 이미 연결됨 (재구축 건너뜀)"
else
  log "터널 재구축"
  taskkill //F //IM cloudflared.exe >/dev/null 2>&1 || true
  sleep 1

  # Cloudflare Access 인증  ★ 포워더보다 먼저 ★
  #   토큰이 캐시돼 있으면 즉시 통과, 없으면 브라우저가 열림
  log "Access 인증 확인 (필요 시 브라우저가 열립니다)"
  cloudflared.exe access login "https://${SSH_HOST}" \
    || die "Access 인증 실패 — 메일 OTP 를 확인하세요"

  # 포워더 — 끊기면 자동 재시작, 창 닫아도 유지
  mkdir -p "$(dirname "$LOG")"
  log "포워더 시작 (로그: $LOG)"
  nohup bash -c '
    while true; do
      "$1" access tcp --hostname "$2" --url "localhost:$3"
      echo "[$(date "+%F %T")] forwarder exited — 3초 후 재시작"
      sleep 3
    done
  ' _ cloudflared.exe "$SSH_HOST" "$LOCAL_PORT" >> "$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  disown 2>/dev/null || true

  # 연결 검증 — sleep 대신 실제 접속을 폴링
  #   accept-new: 새 PC 라 known_hosts 가 비어 있으므로 필요
  log "맥 연결 확인 중"
  OK=0
  for i in $(seq 1 15); do
    if mac_ok; then OK=1; break; fi
    sleep 2
  done
  if [ "$OK" != 1 ]; then
    echo
    warn "맥에 연결할 수 없습니다. 포워더 로그:"
    tail -20 "$LOG" 2>/dev/null
    echo
    die "연결 실패 — 맥의 터널이 HEALTHY 인지 대시보드에서 확인하세요"
  fi
fi

log "맥 연결 확인됨 (${MAC_USER}@mac)"

# ─────────────────────────────────────────────────────────────
# 3) 앱 실행 — 이미 실행 중이면 건너뜀
# ─────────────────────────────────────────────────────────────
launch_toolbox() {
  if [ ! -f "$TOOLBOX" ]; then
    warn "Toolbox 를 찾을 수 없음: $TOOLBOX"
    return
  fi
  if proc_running jetbrains-toolbox.exe; then
    log "Toolbox 이미 실행 중"
  else
    log "Toolbox 실행"
    PATH="$GITBIN:$PATH" "$TOOLBOX" >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
}

launch_vscode() {
  local vs=""
  if   [ -f "$VSCODE_USER" ]; then vs="$VSCODE_USER"
  elif [ -f "$VSCODE_SYS"  ]; then vs="$VSCODE_SYS"
  fi
  if [ -z "$vs" ]; then
    warn "VS Code 를 찾을 수 없음:"
    warn "  $VSCODE_USER"
    warn "  $VSCODE_SYS"
    return
  fi
  if proc_running Code.exe; then
    log "VS Code 이미 실행 중"
  else
    log "VS Code 실행"
    "$vs" >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
}

case "$TARGET" in
  toolbox) launch_toolbox ;;
  vscode)  launch_vscode  ;;
  both)    launch_toolbox; launch_vscode ;;
  none)    log "앱 실행 건너뜀 (target=none)" ;;
esac

# ─────────────────────────────────────────────────────────────
# 4) 안내
# ─────────────────────────────────────────────────────────────
echo
log "준비 완료 (target: $TARGET)"
case "$TARGET" in
  toolbox|both) echo "    Gateway 접속    →  127.0.0.1:${LOCAL_PORT}  (user: ${MAC_USER})" ;;
esac
case "$TARGET" in
  vscode|both)  echo "    Remote-SSH 접속 →  F1 → 'Remote-SSH: Connect to Host' → mac" ;;
esac
echo "    터미널 접속     →  ssh mac"
echo "    종료            →  stop.sh"
echo
