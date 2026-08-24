#!/usr/bin/env bash
#
# 맥 연결 — 매번 실행
#   기존 프로세스 정리 → ssh-agent → Access 인증 → 포워더(자동 재연결) → 검증 → Toolbox
#
set -u

MAC_USER="taeung"
SSH_HOST="ssh.11104002.xyz"
LOCAL_PORT=2222
KEY="$HOME/.ssh/id_ed25519_mac"

GITBIN="/c/Program Files/Git/usr/bin"
TOOLBOX="$HOME/AppData/Local/JetBrains/Toolbox/bin/jetbrains-toolbox.exe"
LOG="$HOME/.cache/cf-forwarder.log"
AGENT_ENV="$HOME/.ssh/agent.env"

export PATH="$HOME/bin:$PATH"

log()  { printf '\033[32m[connect]\033[0m %s\n' "$1"; }
warn() { printf '\033[33m[connect] WARN:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31m[connect] ERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# Git 의 ssh.exe 를 쓰는 래퍼 (Toolbox/Gateway 와 동일 조건)
gssh() { PATH="$GITBIN:$PATH" ssh "$@"; }

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
# 1) 기존 프로세스 정리
# ─────────────────────────────────────────────────────────────
log "기존 프로세스 정리"
taskkill //F //IM jetbrains-toolbox.exe >/dev/null 2>&1 || true
taskkill //F //IM jetbrainsd.exe        >/dev/null 2>&1 || true
taskkill //F //IM cloudflared.exe       >/dev/null 2>&1 || true
sleep 1

# ─────────────────────────────────────────────────────────────
# 2) ssh-agent — 살아있으면 재사용
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
# 3) Cloudflare Access 인증  ★ 포워더보다 먼저 ★
#    토큰이 캐시돼 있으면 즉시 통과, 없으면 브라우저가 열림
# ─────────────────────────────────────────────────────────────
log "Access 인증 확인 (필요 시 브라우저가 열립니다)"
cloudflared.exe access login "https://${SSH_HOST}" \
  || die "Access 인증 실패 — 메일 OTP 를 확인하세요"

# ─────────────────────────────────────────────────────────────
# 4) 포워더 — 끊기면 자동 재시작, 창 닫아도 유지
# ─────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG")"
log "포워더 시작 (로그: $LOG)"

nohup bash -c '
  while true; do
    "$1" access tcp --hostname "$2" --url "localhost:$3"
    echo "[$(date "+%F %T")] forwarder exited — 3초 후 재시작"
    sleep 3
  done
' _ cloudflared.exe "$SSH_HOST" "$LOCAL_PORT" >> "$LOG" 2>&1 &

FWD_PID=$!
disown 2>/dev/null || true
echo "$FWD_PID" > "$HOME/.cache/cf-forwarder.pid"

# ─────────────────────────────────────────────────────────────
# 5) 연결 검증 — sleep 대신 실제 접속을 폴링
#    accept-new: 새 PC 라 known_hosts 가 비어 있으므로 필요
# ─────────────────────────────────────────────────────────────
log "맥 연결 확인 중"
OK=0
for i in $(seq 1 15); do
  if gssh -o BatchMode=yes \
          -o StrictHostKeyChecking=accept-new \
          -o ConnectTimeout=5 \
          -T mac 'echo ok' >/dev/null 2>&1; then
    OK=1
    break
  fi
  sleep 2
done

if [ "$OK" != 1 ]; then
  echo
  warn "맥에 연결할 수 없습니다. 포워더 로그:"
  tail -20 "$LOG" 2>/dev/null
  echo
  die "연결 실패 — 맥의 터널이 HEALTHY 인지 대시보드에서 확인하세요"
fi

log "맥 연결 확인됨 (${MAC_USER}@mac)"

# ─────────────────────────────────────────────────────────────
# 6) Toolbox 실행
# ─────────────────────────────────────────────────────────────
if [ ! -f "$TOOLBOX" ]; then
  warn "Toolbox 를 찾을 수 없음: $TOOLBOX"
  warn "SSH 는 사용 가능합니다:  ssh mac"
  exit 0
fi

log "Toolbox 실행"
PATH="$GITBIN:$PATH" "$TOOLBOX" >/dev/null 2>&1 &
disown 2>/dev/null || true

echo
log "준비 완료"
echo "    Gateway 접속 →  127.0.0.1:${LOCAL_PORT}  (user: ${MAC_USER})"
echo "    터미널 접속   →  ssh mac"
echo "    종료          →  stop.sh"
echo
