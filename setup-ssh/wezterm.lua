-- 싸지방 WezTerm 설정 — setup.sh herdr 가 ~/.wezterm.lua 로 설치한다
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- 싸지방은 cmd.exe 가 막혀 있으므로 Git Bash 를 기본 셸로 (새 탭 Ctrl+Shift+T 도 Git Bash)
config.default_prog = { 'C:/Program Files/Git/bin/bash.exe', '-l' }

config.font = wezterm.font_with_fallback { 'JetBrains Mono', 'Malgun Gothic' }
config.font_size = 11

-- 화면이 깨지거나 버벅이면 GPU 대신 소프트웨어 렌더링
-- config.front_end = 'Software'

-- Ctrl+Shift+H : 새 탭에서 맥의 herdr 에 접속 (connect.sh 와 같은 명령)
--   connect.sh 로 터널·ssh-agent 가 떠 있어야 한다.
--   Windows 내장 OpenSSH 8.1 은 고정 agent 소켓을 못 쓰므로 Git 의 ssh.exe 를 쓴다.
--   비대화형 ssh 명령은 맥의 brew PATH 를 못 읽으므로 로그인·대화형 셸로 감싼다.
local herdr = wezterm.action.SpawnCommandInNewTab {
  args = { 'C:/Program Files/Git/usr/bin/ssh.exe', '-t', 'mac', 'exec $SHELL -lic herdr' },
}
config.keys = {
  { key = 'h', mods = 'CTRL|SHIFT', action = herdr },
  { key = 'H', mods = 'CTRL|SHIFT', action = herdr },
}

return config
