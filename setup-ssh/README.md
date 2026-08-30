### install 

`git`: https://git-scm.com/install/windows 

### git bash

```bash
curl -fsSL https://raw.githubusercontent.com/ehdnd/ssajibang/main/setup-ssh/setup.sh | bash
```

### setup

- cloudflare tunnel
- jetbrains toolbox
- powertoys
- ssh config
- helper scripts
- ssh key

### next

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

종료:

```bash
stop.sh             # 프로세스만
stop.sh --wipe      # 개인키 · Access 토큰까지 삭제 (공용 PC 이석 시)
```

### or

```bash
cloudflared.exe access tcp --hostname ssh.11104002.xyz --url localhost:2222
```
