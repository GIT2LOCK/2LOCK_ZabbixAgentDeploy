# Windows — Zabbix Agent 2 Installer (Simple)

Instalador interativo do Zabbix Agent 2 para Windows Server, via PowerShell. Você responde algumas perguntas e o script faz o resto: instala o agente, ajusta a configuração, libera o firewall só para o Zabbix Server e inicia o serviço.

---

## Compatibilidade

| Sistema | Arquitetura | PowerShell |
|---------|-------------|------------|
| Windows Server 2016, 2019, 2022 | x64 | 5.1 ou superior |

O instalador simples não verifica a versão do Windows: ele só exige PowerShell elevado.

---

## Como usar

### Uma linha (recomendado)

Executar no **PowerShell como Administrador**:

```powershell
irm https://raw.githubusercontent.com/GIT2LOCK/2LOCK_ZabbixAgentDeploy/main/windows/zabbix_agent2_install_simple.ps1 | iex
```

Isso baixa e executa o script diretamente, em modo interativo. O instalador faz todas as perguntas durante a execução (veja a próxima seção).

Se o PowerShell não estiver elevado, o script avisa e para logo no início, sem fechar a janela.

---

### Download manual do GitHub

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/GIT2LOCK/2LOCK_ZabbixAgentDeploy/main/windows/zabbix_agent2_install_simple.ps1 -OutFile zabbix_agent2_install_simple.ps1

# Inspecionar
notepad zabbix_agent2_install_simple.ps1

# Executar (PowerShell como Administrador)
.\zabbix_agent2_install_simple.ps1
```

Se a política de execução bloquear o arquivo, libere só para a sessão atual:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

### Modo interativo

Este instalador é **somente interativo**, tanto na execução em uma linha quanto no arquivo local: não existe `-Auto` nem variáveis de ambiente (`ACCEPT_EULA`, `ZABBIX_SERVER` etc.). Para provisionamento em massa, use o instalador completo.

---

## Perguntas do instalador

As perguntas aparecem sempre nesta ordem:

| # | Pergunta | O que informar | Padrão | Validação |
|---|----------|----------------|--------|-----------|
| 1 | `Li e aceito os termos acima [s/N]` | `s` para aceitar | N (cancela) | Qualquer coisa diferente de `s` cancela a instalação |
| 2 | `Nome exato do host cadastrado no Zabbix` | Nome do host, idêntico ao do frontend | — | Letras, números, ponto, hífen e underscore; sem espaços |
| 3 | `IP IPv4 do servidor ou proxy Zabbix` | IP do Zabbix Server ou Proxy | — | IPv4 válido |
| 4 | `Porta do agente [Enter = 10050]` | Porta de escuta do agente | `10050` | Inteiro entre 1024 e 65535 |
| 5 | `Opcoes (ex: 5 ou 0 para nenhum)` | Plugins opcionais | Nenhum | Números 0–6 ou nomes |
| 6 | `Deseja continuar mesmo assim? (s/N)` | Só aparece se o teste da porta 10051 falhar | N (cancela) | `s` continua |

Perguntas inválidas ou vazias (2 a 5) são repetidas até a resposta ser aceita.

### Termo de uso

O termo aparece antes de qualquer pergunta de configuração. Sem o aceite (`s`), o script mostra **"Instalacao cancelada. Termo de uso nao aceito."** e termina sem alterar nada no servidor.

### Porta do agente

A porta padrão é `10050`. Se usar outra porta, ela vale para o agente, o `.conf` e a regra de firewall. Lembre-se de cadastrar a **mesma porta na interface do host** no frontend do Zabbix.

> A porta `10051` (Zabbix Server) é apenas testada pelo instalador e não é configurável.

### Plugins opcionais

```text
[1] MySQL       (built-in)
[2] PostgreSQL  (loadable, instala pacote extra)
[3] MongoDB     (loadable, instala pacote extra)
[4] Memcached   (built-in)
[5] MSSQL       (loadable, instala pacote extra)
[6] Todos
[0] Nenhum
```

Aceita número ou nome (`mysql`, `postgres`, `mongo`, `sqlserver`...), separados por vírgula, espaço ou ponto e vírgula:

```text
5
mssql
2,3,5
postgres mongo
all
```

Enter ou `0` = nenhum plugin.

---

## Exemplo de sessão

```text
Li e aceito os termos acima [s/N]: s
Nome exato do host cadastrado no Zabbix: SRV-APP01
IP IPv4 do servidor ou proxy Zabbix: 172.16.4.113

Porta padrao do Zabbix: 10050
Porta do agente [Enter = 10050]:

  Opcoes (ex: 5 ou 0 para nenhum): 5
Plugins selecionados: MSSQL.

Resumo:
  Host Zabbix   : SRV-APP01
  Servidor      : 172.16.4.113
  Porta ativa   : TCP 10051
  Porta passiva : TCP 10050
  Plugins       : MSSQL

Testando conectividade com 172.16.4.113 na porta 10051...
Conectividade OK.
[1/6] Baixando o Zabbix Agent 2...
...
STATUS FINAL: AGENTE EM EXECUCAO
```

---

## O que o instalador configura

### Arquivo de configuração

O script ajusta o `zabbix_agent2.conf` gerado pelo MSI e antes faz **backup** com timestamp (`zabbix_agent2.conf.bak-AAAAMMDD-HHMMSS`):

```ini
Server=<IP_ZABBIX_SERVER>
ServerActive=<IP_ZABBIX_SERVER>
Hostname=<NOME_DO_HOST>
ListenPort=<PORTA>
Timeout=10
```

O arquivo é gravado sem BOM, como o agente exige.

### Firewall

A regra é criada **restrita ao IP do Zabbix Server** e inclui a porta no nome:

```text
2LOCK - Zabbix Agent 2 - TCP <PORTA>
```

A porta não é aberta para qualquer origem.

### Serviço

O serviço é configurado para iniciar automaticamente. Ao final, o script o reinicia (ou inicia) e aguarda até 15 segundos pelo status `Running`.

---

## Plugins adicionais

| Tipo | Plugins | Comportamento |
|------|---------|---------------|
| Built-in | MySQL, Memcached | Já vêm no `zabbix_agent2.exe`; o script só gera o stub de configuração |
| Loadable | PostgreSQL, MongoDB, MSSQL | O script baixa e instala o pacote `zabbix_agent2_plugins` e gera o stub |

Para cada plugin escolhido é criado um stub em `C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\`:

```text
2lock_mysql.conf
2lock_postgresql.conf
2lock_mongodb.conf
2lock_memcached.conf
2lock_mssql.conf
```

> **Importante:** os stubs são só comentários. O instalador **não preenche credenciais**: você precisa informar URI, usuário e senha de cada sessão depois e reiniciar o agente:
>
> ```powershell
> Restart-Service "Zabbix Agent 2"
> ```

Nos plugins *loadable*, o pacote oficial gera o `.conf` do próprio plugin (com o caminho do binário). As sessões devem ser preenchidas nele, seguindo o lembrete do stub.

Se o download do pacote de plugins falhar, a instalação **continua**: o agente base fica funcional e os plugins precisam ser instalados manualmente depois.

O guia completo do **MSSQL** está em [`windows/plugins/mssql.md`](plugins/mssql.md). Para testar a sessão depois de configurada:

```powershell
& "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" -t mssql.ping[<nome_sessao>]
```

---

## Logs

```text
C:\ProgramData\2LOCK\ZabbixAgent2\install-msi.log          # log do msiexec (agente)
C:\ProgramData\2LOCK\ZabbixAgent2\msi_plugins_install.log  # log do pacote de plugins (se usado)
```

---

## Diagnóstico pós-instalação

O instalador simples não executa testes de item ao final. Valide manualmente:

```powershell
# Status do serviço
Get-Service "Zabbix Agent 2"

# Testar itens
& "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" -t agent.ping
& "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" -t agent.version

# Porta escutando
Test-NetConnection -ComputerName 127.0.0.1 -Port <PORTA>

# Conectividade com o Zabbix Server
Test-NetConnection -ComputerName <IP_ZABBIX> -Port 10051

# Onde está o log do agente
Select-String -Path "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf" -Pattern '^LogFile'
```

---

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---------|----------------|-------------|
| "execute este script em um PowerShell como Administrador" | Console sem elevação | Abra o PowerShell como Administrador e execute de novo |
| "nao foi possivel conectar em `<IP>:10051`" | Firewall, IP errado ou Zabbix Server fora do ar | Confira o IP e a rota; só continue se a rede ainda será liberada |
| "Assinatura digital do MSI invalida" | Download corrompido ou interceptado | Execute novamente; persistindo, revise proxy e antivírus |
| "O servico nao iniciou" | `.conf` inválido ou porta em uso | Veja `install-msi.log` e o `LogFile` do agente |
| Host indisponível no frontend | Hostname diferente, porta divergente ou firewall | Use o mesmo nome e a mesma porta no Zabbix; confira a regra `2LOCK - Zabbix Agent 2 - TCP <PORTA>` |
| Plugin não aparece | Sessão não preenchida ou agente não reiniciado | Preencha o `.conf` do plugin e rode `Restart-Service "Zabbix Agent 2"` |
| Aviso sobre o pacote de plugins | Falha no download na CDN | O agente base está funcional; instale os plugins manualmente |

---

## Desinstalação completa

Para remover completamente o Zabbix Agent 2, o pacote de plugins (MSSQL, PostgreSQL, etc.), serviços, regras de firewall e diretórios residuais:

```powershell
irm https://raw.githubusercontent.com/GIT2LOCK/2LOCK_ZabbixAgentDeploy/main/windows/zabbix_agent2_uninstall.ps1 | iex
```

Ou executando o arquivo localmente:
```powershell
.\zabbix_agent2_uninstall.ps1
```

---

## Observações importantes

- O script precisa de **PowerShell elevado**.
- O **termo de uso** é obrigatório; sem o aceite, nada é instalado.
- Instala a **versão mais recente da série 7.0** (alias `latest` da CDN).
- O instalador simples **não remove versões anteriores** do agente; remova-as antes, se houver.
- **TLS/PSK** não é configurado automaticamente.
- Rodar de novo recria a regra de firewall e refaz o backup do `.conf`.
