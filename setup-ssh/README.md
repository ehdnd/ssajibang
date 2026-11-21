### install 

`git`: https://git-scm.com/install/windows 

### git bash

```bash
curl -fsSL https://raw.githubusercontent.com/ehdnd/ssajibang/main/setup-ssh/setup.sh | bash -s -- toolbox 
```

PowerToys(+ 설정 백업) 설치를 건너뛰려면 `--no-powertoys` 추가 (IDE 인자와 순서 무관):

```bash
curl -fsSL https://raw.githubusercontent.com/ehdnd/ssajibang/main/setup-ssh/setup.sh | bash -s -- toolbox --no-powertoys
```

브랜치 테스트 (헬퍼 스크립트도 그 브랜치에서 받음):

```bash
B=<branch>; curl -fsSL "https://raw.githubusercontent.com/ehdnd/ssajibang/$B/setup-ssh/setup.sh" | SSAJIBANG_REF="$B" bash -s -- toolbox
```

### setup

- cloudflare tunnel
- jetbrains toolbox
- powertoys (`--no-powertoys` 로 건너뛰기)
- ssh config
- helper scripts
- ssh key

### links

Bitwarden: https://vault.bitwarden.com/#/login

Inflearn: https://www.inflearn.com/my/courses

### connect

새 Git Bash 창에서:

```bash
connect.sh          # Toolbox (기본)
connect.sh vscode   # VS Code
connect.sh both     # 둘 다
connect.sh none     # 터널만
```

터널이 이미 살아 있으면 재사용한다 — Toolbox 사용 중에 `connect.sh vscode` 를
실행해도 기존 세션은 끊기지 않는다. 이미 실행 중인 앱은 다시 띄우지 않는다.

#### passphrase 는 connect.sh 에서 한 번만

`connect.sh` 가 ssh-agent 를 `~/.ssh/agent.sock` 고정 소켓으로 띄우고, 앱 설정을 맞춘다.
앱을 connect.sh 밖에서 띄워도(시작 메뉴 등) 다시 묻지 않는다.

- ssh config `IdentityAgent` → 고정 소켓 (환경변수 없이도 agent 를 찾음)
- Toolbox: 설정 → Advanced → SSH executable location = Git ssh
  (기본값이면 Windows 내장 OpenSSH 8.1 을 골라 agent 를 못 씀). Toolbox 가 꺼져 있을 때 적용
- VS Code: `remote.SSH.path` = Git ssh, `remote.SSH.useLocalServer` = true
  (기본 모드는 cmd.exe 로 ssh 를 실행하는데 싸지방은 cmd.exe 가 막혀 있음).
  Remote-SSH 확장이 없으면 설치 — Settings Sync 로그인 전에도 바로 접속 가능
  (`code.cmd` 대신 sh 스크립트 `bin/code` 사용: `.cmd` 는 cmd.exe 가 필요)

설정 파일은 Git for Windows 에 포함된 perl 로 고친다. 확인: `perl -MJSON::PP -e1 && echo ok`

Toolbox 가 그래도 passphrase 를 물으면 `stop.sh` → `connect.sh` (Toolbox 를 새로 띄우며 설정 적용).

#### ICN 라우팅 (hosts 패치)

무료 플랜 도메인은 한국에서 Cloudflare LAX 로 붙어 600~1000ms 지연이 생긴다.
`connect.sh` 가 매번 hosts 에 ICN 으로 가는 IP 를 넣어 인천 엣지로 붙게 한다 (~30ms).

- **Git Bash 를 관리자 권한으로 실행**해야 hosts 를 고칠 수 있다 (안 되면 경고 후 LAX 로 계속)
- 지정 IP 가 응답이 없으면 자동으로 원복하고 기본 경로로 접속
- 확인: `curl -s https://ssh.11104002.xyz/cdn-cgi/trace | grep colo` → `colo=ICN`

```bash
ICN_PATCH=0 connect.sh                 # 패치 끄기
CF_ICN_IP=172.66.x.x connect.sh        # IP 바꾸기 (nslookup lucajournal.pages.dev 로 찾기)
```

### stop

```bash
stop.sh             # 프로세스만
stop.sh --wipe      # 개인키 · Access 토큰 · hosts 패치까지 삭제 (공용 PC 이석 시)
```

### or

```bash
cloudflared.exe access tcp --hostname ssh.11104002.xyz --url localhost:2222
```

### or 

VS Code만:
```bash
taskkill //F //IM Code.exe
```

JetBrains만 (Toolbox + 백그라운드 서비스):
```bash
taskkill //F //IM jetbrains-toolbox.exe //IM jetbrainsd.exe
```

뭐가 떠 있는지 확인:
```
tasklist //NH | grep -iE 'Code.exe|jetbrains|cloudflared'
```
