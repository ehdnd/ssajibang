#!/usr/bin/env bash
#
# 세션 종료
#   stop.sh         프로세스만 종료
#   stop.sh --wipe  개인키 · Access 토큰 · agent · hosts ICN 패치까지 삭제 (공용 PC 이석 시)
#
set -u

KEY="$HOME/.ssh/id_ed25519_mac"
LOG="$HOME/.cache/cf-forwarder.log"
PIDFILE="$HOME/.cache/cf-forwarder.pid"
AGENT_ENV="$HOME/.ssh/agent.env"

# connect.sh 의 ICN hosts 패치와 동일한 값
CF_DOMAIN="11104002.xyz"
HOSTS_FILE="${HOSTS_FILE:-/c/Windows/System32/drivers/etc/hosts}"
HOSTS_BEGIN="# >>> ssajibang icn >>>"
HOSTS_END="# <<< ssajibang icn <<<"

log() { printf '\033[32m[stop]\033[0m %s\n' "$1"; }

# hosts 에서 ICN 패치 블록과 도메인 줄 제거 (cat > 로 써서 파일 권한 유지)
hosts_revert() {
  local tmp="$HOME/.cache/hosts.new"
  [ -f "$HOSTS_FILE" ] || return 0
  mkdir -p "$HOME/.cache"
  awk -v b="$HOSTS_BEGIN" -v e="$HOSTS_END" '
    { line = $0; sub(/\r$/, "", line) }
    line == b { skip = 1; next }
    line == e { skip = 0; next }
    skip { next }
    { print }
  ' "$HOSTS_FILE" | grep -viE "[[:space:]]([a-z0-9-]+\.)?${CF_DOMAIN//./\\.}([[:space:]]|$)" > "$tmp"
  if cmp -s "$tmp" "$HOSTS_FILE"; then
    rm -f "$tmp"; return 0
  fi
  if cat "$tmp" > "$HOSTS_FILE" 2>/dev/null; then
    ipconfig //flushdns >/dev/null 2>&1 || true
    log "hosts ICN 패치 제거"
  else
    log "hosts 수정 실패 (관리자 권한 필요) — 직접 지우세요: $HOSTS_FILE"
  fi
  rm -f "$tmp"
}

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
  hosts_revert

  log "삭제 완료 — 개인키 · Access 토큰 · known_hosts · hosts 패치"
  echo
  echo "  다음 접속 시 Bitwarden 에서 키를 다시 붙여넣어야 합니다."
else
  echo
  echo "  자격증명은 남아 있습니다."
  echo "  공용 PC 에서 자리를 뜬다면:  stop.sh --wipe"
fi
echo
