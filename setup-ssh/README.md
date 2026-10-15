### install 

`git`: https://git-scm.com/install/windows 

### git bash

```bash
curl -fsSL https://raw.githubusercontent.com/ehdnd/ssajibang/main/setup-ssh/setup.sh | bash -s -- toolbox 
```

### setup

- cloudflare tunnel
- jetbrains toolbox
- powertoys
- ssh config
- helper scripts
- ssh key

### bitwarden

Bitwarden: https://vault.bitwarden.com/#/login

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
