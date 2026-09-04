### install 

`git`

### git bash

```
curl -sL --compressed https://raw.githubusercontent.com/ehdnd/ssajibang/refs/heads/main/setup-codespace/setup.sh | bash
```

### setup

- PowerToys Backup
- Run jetbrains Gateway

### git bash

```
gh auth login -s codespace
```

```
gh codespace ssh --repo ehdnd/spring-mvc-1-itemservice --server-port 2222
```

### gateway

while running git bash ssh

- host: localhost
- port: 2222
- username: `{whoami}`
- keypair: codespace.auto

### git bash

```
gh codespace stop
```
