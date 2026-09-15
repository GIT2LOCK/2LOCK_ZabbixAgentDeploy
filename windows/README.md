# Windows — Zabbix Agent 2 Installer

Instalador automatizado do Zabbix Agent 2 para Windows Server, via PowerShell.

---

## Compatibilidade

| Sistema | Versões | Arquitetura |
|---------|---------|-------------|
| Windows Server | 2016, 2019, 2022 | x64 |

Versões fora dessa lista geram apenas um aviso (o script pergunta se quer continuar mesmo assim, ou continua automaticamente no modo `-Auto`).

---

## Como usar

### Uma linha — via 2LOCK (recomendado)

Executar no **PowerShell como Administrador**:

```powershell
iwr https://2lock.com.br/windowsagent | iex
```

Isso baixa e executa o script diretamente em modo interativo. O instalador faz todas as perguntas necessárias durante a execução.

---

### Download manual do GitHub

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/GIT2LOCK/2LOCK_ZabbixAgentDeploy/main/windows/zabbix_agent2_install.ps1 -OutFile zabbix_agent2_install.ps1

# Inspecionar
notepad zabbix_agent2_install.ps1

# Executar (PowerShell como Administrador)
.\zabbix_agent2_install.ps1
```

---

### Modo automatizado (sem interação)

Ideal para provisionamento em massa via **Ansible**, **Terraform**, **GPO** ou scripts de bootstrap.

O modo automatizado liga sozinho quando `ACCEPT_EULA=yes` já está definido no ambiente, já que não é possível passar `-Auto` através do `iwr | iex`:

```powershell
# Via URL 2LOCK
$env:ACCEPT_EULA     = "yes"
$env:ZABBIX_SERVER   = "10.0.0.1"
$env:ZABBIX_PORT     = "10050"
$env:ZABBIX_HOSTNAME = "MEUSERVIDOR"
$env:ZABBIX_PLUGINS  = "mssql"
$env:APPLY_FIREWALL  = "yes"
iwr https://2lock.com.br/windowsagent | iex

# Via GitHub raw / arquivo local (equivalente, com -Auto explícito)
$env:ACCEPT_EULA     = "yes"
$env:ZABBIX_SERVER   = "10.0.0.1"
$env:ZABBIX_PORT     = "10050"
$env:ZABBIX_HOSTNAME = "MEUSERVIDOR"
$env:ZABBIX_PLUGINS  = "mssql"
$env:APPLY_FIREWALL  = "yes"
.\zabbix_agent2_install.ps1 -Auto
```

#### Variáveis de ambiente disponíveis

| Variável | Obrigatória | Padrão | Descrição |
|----------|-------------|--------|-----------|
| `ACCEPT_EULA` | Sim | — | Deve ser `yes` para aceitar o termo; também é o que liga o modo automático quando usado via `iwr \| iex` |
| `ZABBIX_SERVER` | Sim | — | IP do Zabbix Server ou Proxy |
| `ZABBIX_PORT` | Não | `10050` | Porta de escuta do agente |
| `ZABBIX_HOSTNAME` | Não | nome do computador (`$env:COMPUTERNAME`) | Nome do host no Zabbix — deve ser idêntico ao cadastrado |
| `ZABBIX_PLUGINS` | Não | vazio | Plugins opcionais para gerar stub de configuração; vazio não gera nenhum |
| `APPLY_FIREWALL` | Não | `n` | `yes` para aplicar a regra de firewall automaticamente |
| `ZABBIX_VERSION` | Não | `7.0.30` | Versão do Zabbix Agent 2 a baixar da CDN oficial |
| `ZABBIX_INSTALL_DIR` | Não | `C:\Program Files\Zabbix Agent 2` | Pasta de instalação |

---

## O que o script configura

### Origem do instalador

Diferente do Linux (que usa repositório apt/dnf), o Windows não tem um pacote de sistema para o Zabbix Agent 2. O script baixa o **MSI oficial estático** (sem dependência externa de OpenSSL) direto da CDN da Zabbix:

```
https://cdn.zabbix.com/zabbix/binaries/stable/<major>/<versao>/zabbix_agent2-<versao>-windows-amd64-static.msi
```

A versão é fixada em `ZABBIX_VERSION` no topo do script (não existe alias "latest" nessa CDN), atualmente `7.0.30`. Revisar em [zabbix.com/download_agents](https://www.zabbix.com/download_agents) periodicamente.

### Arquivo principal gerado

`C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf`

```ini
Server=<ZABBIX_SERVER>
ServerActive=<ZABBIX_SERVER>
Hostname=<ZABBIX_HOSTNAME>
ListenPort=<ZABBIX_PORT>
LogType=file
LogFile=C:\Program Files\Zabbix Agent 2\logs\zabbix_agent2.log
LogFileSize=10
DebugLevel=3
Timeout=10
Include=C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\*.conf
```

### User parameter instalado

Arquivo: `C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\userparameters_2lock.conf`

| Chave | Tipo | Descrição |
|-------|------|-----------|
| `windows.top.cpu` | Text | JSON com os 5 processos de maior consumo de CPU acumulado |

Exemplo de retorno:
```json
[{"process":"sqlservr","cpu":452.1,"mem_mb":812.4},{"process":"AppServer","cpu":120.3,"mem_mb":340.2}]
```

Para usar no Zabbix: item do tipo **Zabbix agent**, chave `windows.top.cpu`, tipo de dado **Text**, intervalo sugerido **5m**.

> Diferente do `linux.top.cpu` (que reporta `%cpu`/`%mem` instantâneos via `ps`), o `windows.top.cpu` reporta `cpu` como tempo de processador acumulado em segundos (propriedade `CPU` do `Get-Process`) e `mem_mb` como working set em MB. Os nomes das chaves são intencionalmente diferentes do Linux por causa dessa diferença de unidade.

### Firewall

A regra é criada **restrita ao IP do Zabbix Server**, via `New-NetFirewallRule`, não abre a porta para qualquer origem:

```powershell
New-NetFirewallRule -DisplayName "Zabbix Agent 2 - 2LOCK" -Direction Inbound `
    -Protocol TCP -LocalPort <PORTA> -RemoteAddress <IP_ZABBIX_SERVER> -Action Allow
```

---

## Plugins adicionais

No Windows, os plugins **já vêm compilados dentro do `zabbix_agent2.exe`** — não existe pacote separado para instalar, diferente do Linux (`zabbix-agent2-plugin-<nome>`). A seleção de plugins nesta etapa só decide quais arquivos de configuração (stub) são gerados em `zabbix_agent2.d\`:

```text
[1] MySQL
[2] PostgreSQL
[3] MongoDB
[4] Memcached
[5] MSSQL
[6] Todos
[0] Nenhum
```

No modo automatizado, use `ZABBIX_PLUGINS` com nomes ou números separados por espaço, vírgula ou ponto e vírgula:

```powershell
$env:ZABBIX_PLUGINS = "mssql"
$env:ZABBIX_PLUGINS = "5"
$env:ZABBIX_PLUGINS = "all"      # gera stub de todos os plugins listados
$env:ZABBIX_PLUGINS = "none"     # nao gera nenhum stub (padrao)
```

> **Importante:** apenas o **MSSQL** tem guia completo neste repositório ([`windows/plugins/mssql.md`](plugins/mssql.md)), por ser o único relevante nos projetos atuais da 2LOCK em servidores Windows (bancos SQL Server do Protheus/Smarte, por exemplo). Os demais plugins geram um stub comentado apontando para a documentação oficial do Zabbix, sem exemplo de sessão configurado.

Após configurar ou alterar um arquivo de plugin em `zabbix_agent2.d\`, reinicie o agente:

```powershell
Restart-Service "Zabbix Agent 2"
```

---

## Validações realizadas pelo script

| Verificação | Resultado esperado |
|---|---|
| `agent.ping` | `1` |
| `agent.version` | Começa com `7.` |
| `system.uname` | Informativo |
| Hostname no conf | Igual ao informado |
| Porta escutando | Visível via `Test-NetConnection` local |

---

## Log de instalação

```
C:\ProgramData\zabbix\2lock_install.log       # transcript completo da execucao
C:\ProgramData\zabbix\msi_install.log          # log verboso do msiexec
```

---

## Diagnóstico pós-instalação

```powershell
# Status do servico
Get-Service "Zabbix Agent 2"

# Ultimas linhas do log
Get-Content "C:\Program Files\Zabbix Agent 2\logs\zabbix_agent2.log" -Tail 50

# Testar itens manualmente
& "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" -t agent.ping
& "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" -t agent.version
& "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" -t windows.top.cpu

# Verificar porta escutando
Test-NetConnection -ComputerName 127.0.0.1 -Port <PORTA>

# Testar conectividade com o Zabbix Server
Test-NetConnection -ComputerName <IP_ZABBIX> -Port 10051
```

---

## Observações importantes

- O script **remove versões anteriores** do agente (via chaves de registro `Uninstall\*` + `msiexec /x`) antes de instalar
- O arquivo de configuração existente recebe **backup automático** com timestamp
- O script precisa ser executado em **PowerShell elevado** (como Administrador); do contrário, para com erro logo no início
- TLS/PSK não é configurado automaticamente — comentários no arquivo gerado orientam como habilitar futuramente
- A versão do agente é **fixa** no script (`ZABBIX_VERSION`), diferente do Linux que sempre pega a mais recente da série 7.0 via repositório — revisar manualmente quando uma nova patch for lançada
