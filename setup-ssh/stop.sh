#!/usr/bin/env bash
#
# 세션 종료
#   stop.sh         프로세스만 종료
#   stop.sh --wipe  개인키 · Access 토큰 · agent 까지 삭제 (공용 PC 이석 시)
#
set -u

KEY="$HOME/.ssh/id_ed25519_mac"
LOG="$HOME/.cache/cf-forwarder.log"
PIDFILE="$HOME/.cache/cf-forwarder.pid"
AGENT_ENV="$HOME/.ssh/agent.env"

log() { printf '\033[32m[stop]\033[0m %s\n' "$1"; }

# ─────────────────────────────────────────────────────────────
# 프로세스 종료
# ─────────────────────────────────────────────────────────────
log "프로세스 종료"

if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

taskkill //F //IM cloudflared.exe       >/dev/null 2>&1 || true
taskkill //F //IM jetbrains-toolbox.exe >/dev/null 2>&1 || true
taskkill //F //IM jetbrainsd.exe        >/dev/null 2>&1 || true
taskkill //F //IM Code.exe              >/dev/null 2>&1 || true

# ssh-agent 종료
if [ -f "$AGENT_ENV" ]; then
  . "$AGENT_ENV" >/dev/null 2>&1 || true
  ssh-agent -k >/dev/null 2>&1 || true
  rm -f "$AGENT_ENV"
fi

log "프로세스 종료 완료"

# ─────────────────────────────────────────────────────────────
# --wipe : 자격증명 삭제
# ─────────────────────────────────────────────────────────────
if [ "${1:-}" = "--wipe" ]; then
  log "자격증명 삭제"

  rm -f "$KEY" "$KEY.pub"
  rm -rf "$HOME/.cloudflared"          # Access JWT 캐시
  rm -f  "$HOME/.ssh/known_hosts"
  rm -f  "$LOG"

  log "삭제 완료 — 개인키 · Access 토큰 · known_hosts"
  echo
  echo "  다음 접속 시 Bitwarden 에서 키를 다시 붙여넣어야 합니다."
else
  echo
  echo "  자격증명은 남아 있습니다."
  echo "  공용 PC 에서 자리를 뜬다면:  stop.sh --wipe"
fi
echo
