#!/usr/bin/env bash
#
# gh (portable) + PowerToys + JetBrains Gateway + PowerToys Backup

set -eu

# config
GH_OWNER="ehdnd"
GH_REPO="ssajibang"
PTB_FILE="settings_134282238737369559.ptb"
PTB_URL="https://raw.githubusercontent.com/${GH_OWNER}/${GH_REPO}/main/setup/${PTB_FILE}"

GH_DIR="$HOME/tools/gh"
PTB_DIR="$HOME/ptb-backup"
TMP="$(mktemp -d)"

# helper
log() { printf '[setup] %s\n' "$1"; }
die() { printf '[setup] ERROR: %s\n' "$1" >&2; exit 1; }

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

cd "$TMP"

# 1) gh (포터블 zip, 설치/관리자권한 불필요)
log "gh 최신 버전 확인 중"
GH_URL="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
          | grep -o 'https://[^"]*windows_amd64\.zip' | head -1)"
[ -n "$GH_URL" ] || die "gh 다운로드 URL을 못 찾음 (API 호출 제한일 수 있음)"

log "gh 다운로드"
curl -fsSL -o gh.zip "$GH_URL" || die "gh 다운로드 실패"
mkdir -p "$GH_DIR"
unzip -oq gh.zip -d "$GH_DIR" || die "gh 압축 해제 실패"
[ -f "$GH_DIR/bin/gh.exe" ] || die "gh.exe 를 찾을 수 없음"

# PATH (중복 방지)
if ! grep -q 'tools/gh/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/tools/gh/bin:$PATH"' >> "$HOME/.bashrc"
fi
log "gh 완료: $GH_DIR/bin/gh.exe"

# 2) PowerToys (유저설치, 관리자권한 불필요)
log "PowerToys 최신 버전 확인 중"
PT_URL="$(curl -fsSL https://api.github.com/repos/microsoft/PowerToys/releases/latest \
          | grep -o 'https://[^"]*PowerToysUserSetup-[^"]*-x64\.exe' | head -1)"
[ -n "$PT_URL" ] || die "PowerToys 다운로드 URL을 못 찾음"

log "PowerToys 다운로드 및 설치"
curl -fsSL -o pt.exe "$PT_URL" || die "PowerToys 다운로드 실패"
MSYS_NO_PATHCONV=1 ./pt.exe /install /quiet /norestart || die "PowerToys 설치 실패"
log "PowerToys 완료"

# 3) JetBrains Gateway 
log "Gateway 다운로드 및 설치"
curl -fsSL -o gateway.exe \
  "https://download.jetbrains.com/product?code=GW&latest&distribution=windows" \
  || die "Gateway 다운로드 실패"
MSYS_NO_PATHCONV=1 ./gateway.exe /S || die "Gateway 설치 실패 (권한 문제일 수 있음)"
log "Gateway 완료"

# 4) PowerToys .ptb (복원은 수동)
log "PowerToys 설정 백업 다운로드"
mkdir -p "$PTB_DIR"
curl -fsSL -o "$PTB_DIR/$PTB_FILE" "$PTB_URL" || die "설정 백업 다운로드 실패"
log "설정 백업 저장 위치: $PTB_DIR/$PTB_FILE"

log "전체 완료"
log "- 새 Git Bash 창을 열면 gh 사용 가능"
log "- PowerToys 설정 적용: 설정 > 백업 및 복원 > 복원 에서 위 폴더 지정"