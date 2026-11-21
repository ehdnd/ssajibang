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
#   ssh-agent 는 환경변수 상속에 기대지 않는다:
#     - agent 소켓을 ~/.ssh/agent.sock 으로 고정하고 ssh config 의 IdentityAgent 로 가리킨다
#       → connect.sh 밖에서 뜬 Toolbox/jetbrainsd 가 띄운 ssh 도 agent 를 찾는다
#     - Toolbox 의 SSH 실행 파일을 Git ssh 로 고정한다 (기본값이면 PATH 에서 찾다가
#       Windows 내장 OpenSSH 8.1 을 골라 Git Bash 의 agent 를 못 쓰고 passphrase 를 묻는다)
#     - VS Code Remote-SSH 는 Git ssh + local server 모드로 고정한다 (기본 모드는 cmd.exe 로
#       ssh 를 실행하는데 싸지방은 cmd.exe 실행이 막혀 있다)
#   설정 파일은 Git for Windows 에 포함된 perl(JSON::PP)로 고친다.
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
AGENT_SOCK="$HOME/.ssh/agent.sock"     # ssh-agent 소켓 (고정 경로, ssh config 의 IdentityAgent)
AGENT_ENV="$HOME/.ssh/agent.env"       # agent PID 보관 (stop.sh 가 종료에 사용)
TOOLBOX_SETTINGS="$HOME/AppData/Local/JetBrains/Toolbox/.settings.json"
VSCODE_SETTINGS="$HOME/AppData/Roaming/Code/User/settings.json"

# Cloudflare ICN 라우팅 패치
#   무료 플랜 도메인(172.67.x.x)은 한국에서 LAX 로 가서 600~1000ms 지연이 생긴다.
#   ICN 으로 가는 Cloudflare IP(172.66.x.x)를 hosts 에 박아 인천 엣지로 붙게 한다.
#   끄기: ICN_PATCH=0 connect.sh   /  IP 바꾸기: CF_ICN_IP=172.66.x.x connect.sh
ICN_PATCH="${ICN_PATCH:-1}"
CF_ICN_IP="${CF_ICN_IP:-172.66.44.186}"
CF_DOMAIN="11104002.xyz"
CF_SUBS="ssh web code vnc"
HOSTS_FILE="${HOSTS_FILE:-/c/Windows/System32/drivers/etc/hosts}"
HOSTS_BEGIN="# >>> ssajibang icn >>>"
HOSTS_END="# <<< ssajibang icn <<<"

export PATH="$HOME/bin:$PATH"

# Windows 프로그램(Toolbox, VS Code)과 ssh config 에 넘길 Windows 형식 경로
#   AGENT_SOCK_WIN 은 SSH_AUTH_SOCK 과 IdentityAgent 에 '같은 문자열'로 쓴다
#   (jetbrainsd 는 둘이 다르면 ssh-agent 설정 충돌로 처리한다)
AGENT_SOCK_WIN="$(cygpath -m "$AGENT_SOCK")"     # C:/Users/<user>/.ssh/agent.sock
GIT_SSH_WIN="$(cygpath -w "$GITBIN/ssh.exe")"   # C:\Program Files\Git\usr\bin\ssh.exe

log()  { printf '\033[32m[connect]\033[0m %s\n' "$1"; }
warn() { printf '\033[33m[connect] WARN:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[31m[connect] ERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# Git 의 ssh.exe 를 쓰는 래퍼 (Toolbox/Gateway 와 동일 조건)
gssh() { PATH="$GITBIN:$PATH" ssh "$@"; }

# JSON 설정 파일의 키를 설정 (Git for Windows 에 포함된 perl + JSON::PP 사용)
#   json_set FILE 'a/b/c:s=문자열' 'x.y:b=true' ...
#     키 경로 구분자는 '/'  (VS Code 키의 '.' 은 키 이름의 일부로 취급)
#     타입: s = 문자열, b = 불리언(true|false)
#   종료코드: 0 변경함 / 1 이미 같음 / 2 실패 (perl·JSON::PP 없음, 엄격한 JSON 아님 등)
#   파일이 없으면 새로 만든다. 주석·trailing comma 가 있는 파일은 건드리지 않는다(2).
#   JSON_SET_DRYRUN=1 이면 파일은 건드리지 않고 판정만 한다.
json_set() {
  command -v perl >/dev/null 2>&1 || return 2
  perl -MJSON::PP -e '
    use strict; use warnings;
    my $file = shift @ARGV;
    # 엄격한 JSON 만 읽는다 — 주석·trailing comma 가 있으면 다시 쓸 때 사라지므로 손대지 않음
    my $js = JSON::PP->new->utf8->allow_nonref->pretty->canonical;
    my $data = {};
    if (-s $file) {
      open(my $in, "<:raw", $file) or exit 2;
      my $txt = do { local $/; <$in> };
      close $in;
      $txt =~ s/^\xEF\xBB\xBF//;
      $data = eval { $js->decode($txt) };
      exit 2 unless ref $data eq "HASH";
    }
    my $changed = 0;
    for my $arg (@ARGV) {
      my ($lhs, $val) = split /=/, $arg, 2;
      defined $val or exit 2;
      my ($path, $type) = $lhs =~ /^(.+):([sb])$/ or exit 2;
      my $new = $type eq "s" ? $val
              : $val eq "true" ? JSON::PP::true : JSON::PP::false;
      my @keys = split m{/}, $path;
      my $last = pop @keys;
      my $node = $data;
      for my $k (@keys) {
        $node->{$k} = {} unless ref $node->{$k} eq "HASH";
        $node = $node->{$k};
      }
      my $old = exists $node->{$last} ? $js->encode($node->{$last}) : "";
      next if $old eq $js->encode($new);
      $node->{$last} = $new;
      $changed = 1;
    }
    exit 1 unless $changed;
    exit 0 if $ENV{JSON_SET_DRYRUN};
    my $tmp = "$file.tmp$$";
    open(my $out, ">:raw", $tmp) or exit 2;
    print $out $js->encode($data);
    close $out or do { unlink $tmp; exit 2 };
    rename($tmp, $file) or do { unlink $tmp; exit 2 };
    exit 0;
  ' "$@"
}

# Toolbox 가 쓸 ssh 실행 파일 = Git ssh  (설정 → Advanced → SSH executable location)
#   Toolbox 3.6+ 는 ssh 를 jetbrainsd 가 실행한다. 기본값(Default)이면 PATH 에서 ssh.exe 를
#   찾으므로, connect.sh 밖에서 뜬 Toolbox(설치 직후 자동 실행, 시작 메뉴 등)는
#   Windows 내장 OpenSSH 8.1 을 골라 Git Bash 의 agent 를 못 쓰고 passphrase 를 묻는다.
toolbox_ssh_ok() {
  JSON_SET_DRYRUN=1 json_set "$TOOLBOX_SETTINGS" \
    "advanced/user_selected_ssh_executable/location:s=$GIT_SSH_WIN"
  [ $? = 1 ]
}

# Toolbox 가 실행 중일 때 쓰면 Toolbox 가 덮어쓸 수 있으므로 꺼져 있을 때만 호출한다
toolbox_ssh_apply() {
  local ver
  ver="$("$GITBIN/ssh.exe" -V 2>&1 | head -1 | tr -d '\r')"
  mkdir -p "$(dirname "$TOOLBOX_SETTINGS")"
  json_set "$TOOLBOX_SETTINGS" \
    "advanced/user_selected_ssh_executable/type:s=OPENSSH" \
    "advanced/user_selected_ssh_executable/version:s=$ver" \
    "advanced/user_selected_ssh_executable/location:s=$GIT_SSH_WIN" \
    "advanced/user_selected_ssh_executable/name:s=$GIT_SSH_WIN"
  case $? in
    0) log "Toolbox SSH 실행 파일 → $GIT_SSH_WIN" ;;
    1) ;;  # 이미 설정됨
    *) warn "Toolbox 설정 파일 수정 실패: $TOOLBOX_SETTINGS"
       warn "  Toolbox 설정 → Advanced → SSH executable location 에서 직접 선택: $GIT_SSH_WIN" ;;
  esac
}

# VS Code Remote-SSH = Git ssh + local server 모드
#   기본 모드(useLocalServer=false)는 Windows 에서 cmd.exe 로 ssh 를 실행하는데
#   (Remote-SSH 코드에 cmd.exe 가 고정) 싸지방은 cmd.exe 실행이 막혀 있어 타임아웃 난다.
#   local server 모드는 node 가 ssh 를 직접 실행한다.
vscode_settings_apply() {
  mkdir -p "$(dirname "$VSCODE_SETTINGS")"
  json_set "$VSCODE_SETTINGS" \
    "remote.SSH.path:s=$GIT_SSH_WIN" \
    "remote.SSH.useLocalServer:b=true"
  case $? in
    0) log "VS Code 설정 적용 (remote.SSH.path = Git ssh, remote.SSH.useLocalServer = true)" ;;
    1) ;;  # 이미 설정됨
    *) warn "VS Code settings.json 을 고치지 못함 (주석·trailing comma 등): $VSCODE_SETTINGS"
       warn "  직접 추가: \"remote.SSH.path\": \"${GIT_SSH_WIN//\\/\\\\}\", \"remote.SSH.useLocalServer\": true" ;;
  esac
}

# Remote-SSH 확장이 없으면 설치 (Settings Sync 로그인 전에도 바로 접속할 수 있게)
#   bin/code.cmd 는 cmd.exe 가 필요하므로 sh 스크립트인 bin/code 를 쓴다.
vscode_ensure_remote_ssh() {
  local cli
  cli="$(dirname "$1")/bin/code"
  if ls -d "$HOME/.vscode/extensions/ms-vscode-remote.remote-ssh-"[0-9]* >/dev/null 2>&1; then
    return
  fi
  if [ ! -f "$cli" ]; then
    warn "Remote-SSH 확장 없음 + code CLI 없음 ($cli) — VS Code 에서 수동 설치하세요"
    return
  fi
  log "Remote-SSH 확장 설치"
  if sh "$cli" --install-extension ms-vscode-remote.remote-ssh >/dev/null 2>&1; then
    log "Remote-SSH 확장 완료"
  else
    warn "Remote-SSH 확장 설치 실패 — VS Code 에서 수동 설치하세요"
  fi
}

# Cloudflare Access 로그인 — 성공 시 cloudflared 가 찍는 토큰(JWT)은 화면에서 지운다
#   (공용 PC 화면·스크롤백에 남지 않게). 로그인 URL 등 나머지 출력은 그대로 보여준다.
cf_login() {
  cloudflared.exe access login "https://${SSH_HOST}" 2>&1 \
    | tr -d '\r' \
    | sed -E -e '/^[A-Za-z0-9_-]{16,}(\.[A-Za-z0-9_-]*)*[[:space:]]*$/d' \
             -e 's/^Successfully fetched your token:?.*/Access 토큰 확인됨 (토큰은 화면에 출력하지 않음)/'
  return "${PIPESTATUS[0]}"
}

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

# ssh config 에 IdentityAgent 가 없으면 추가 (이전 setup.sh 로 만든 config 대비)
#   → SSH_AUTH_SOCK 을 물려받지 못한 ssh 도 config 만 보고 agent 를 찾는다
if ! grep -qi '^[[:space:]]*IdentityAgent' "$HOME/.ssh/config"; then
  sed -i "/^[[:space:]]*IdentitiesOnly/a\\    IdentityAgent $AGENT_SOCK_WIN" "$HOME/.ssh/config"
  if grep -qi '^[[:space:]]*IdentityAgent' "$HOME/.ssh/config"; then
    log "ssh config 에 IdentityAgent 추가 ($AGENT_SOCK_WIN)"
  else
    warn "ssh config 에 IdentityAgent 를 넣지 못함 — setup.sh 를 다시 실행하세요"
  fi
fi

# ─────────────────────────────────────────────────────────────
# 1) ssh-agent — 고정 소켓(~/.ssh/agent.sock), 살아있으면 재사용
# ─────────────────────────────────────────────────────────────
export SSH_AUTH_SOCK="$AGENT_SOCK_WIN"

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
    log "ssh-agent 시작 (소켓: $AGENT_SOCK)"
    rm -f "$AGENT_SOCK"                       # 죽은 agent 가 남긴 소켓
    ssh-agent -s -a "$AGENT_SOCK" > "$AGENT_ENV" || die "ssh-agent 시작 실패"
    . "$AGENT_ENV" >/dev/null
    export SSH_AUTH_SOCK="$AGENT_SOCK_WIN"    # agent.env 의 POSIX 경로 대신 IdentityAgent 와 같은 형식
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
  cf_login || die "Access 인증 실패 — 메일 OTP 를 확인하세요"

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
    if toolbox_ssh_ok; then
      log "Toolbox 이미 실행 중 (SSH: Git ssh)"
    else
      warn "Toolbox 가 이미 실행 중인데 SSH 실행 파일이 Git ssh 가 아님 → passphrase 를 물을 수 있음"
      warn "  stop.sh 후 connect.sh 를 다시 실행하거나,"
      warn "  Toolbox 설정 → Advanced → SSH executable location → $GIT_SSH_WIN"
    fi
  else
    toolbox_ssh_apply
    log "Toolbox 실행"
    # PATH·SSH_AUTH_SOCK 도 함께 넘긴다 (설정 파일 적용이 실패했을 때의 예비 경로)
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
  # VS Code 는 settings.json 변경을 실행 중에도 반영하므로 항상 적용
  vscode_settings_apply
  vscode_ensure_remote_ssh "$vs"
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
