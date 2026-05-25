# Linux — Zabbix Agent 2 Installer

Instalador automatizado do Zabbix Agent 2 para distribuições Linux baseadas em RPM e DEB.

---

## Compatibilidade

| Família | Distribuições | Versões |
|---------|--------------|---------|
| RPM | AlmaLinux, RHEL, Rocky Linux, CentOS | 8.x, 9.x |
| DEB | Ubuntu, Debian | Ubuntu 20.04+, Debian 11+ |

Arquiteturas suportadas: **x86_64** e **aarch64** (ARM 64-bit).

---

##  Como usar

### Uma linha — via 2LOCK (recomendado)

```bash
curl -fsSL https://2lock.com.br/linuxagent | sudo bash
```

Isso baixa e executa o script diretamente em modo interativo. O instalador faz todas as perguntas necessárias durante a execução.

---

###  Download manual do GitHub

```bash
curl -O https://raw.githubusercontent.com/2lock/zabbix-agent-deploy/main/linux/zabbix_agent2_install.sh
chmod +x zabbix_agent2_install.sh

# Inspecionar 
less zabbix_agent2_install.sh

# Executar
sudo ./zabbix_agent2_install.sh
```

---

### Modo automatizado (sem interação)

Ideal para provisionamento em massa via **Ansible**, **Terraform** ou scripts de bootstrap:

```bash
# Via URL 2LOCK
sudo ACCEPT_EULA=yes \
     ZABBIX_SERVER=10.0.0.1 \
     ZABBIX_PORT=10050 \
     ZABBIX_HOSTNAME=MEUSERVIDOR \
     ZABBIX_PLUGINS="mysql memcached" \
     APPLY_FIREWALL=yes \
     bash <(curl -fsSL https://2lock.com.br/linuxagent) --auto

# Via GitHub raw
sudo ACCEPT_EULA=yes \
     ZABBIX_SERVER=10.0.0.1 \
     ZABBIX_PORT=10050 \
     ZABBIX_HOSTNAME=MEUSERVIDOR \
     ZABBIX_PLUGINS="mysql memcached" \
     APPLY_FIREWALL=yes \
     ./zabbix_agent2_install.sh --auto
```

#### Variáveis de ambiente disponíveis

| Variável | Obrigatória | Padrão | Descrição |
|----------|-------------|--------|-----------|
| `ACCEPT_EULA` | Sim (--auto) | — | Deve ser `yes` para aceitar o termo |
| `ZABBIX_SERVER` | Sim (--auto) | — | IP do Zabbix Server ou Proxy |
| `ZABBIX_PORT` | Não | `10050` | Porta de escuta do agente |
| `ZABBIX_HOSTNAME` | Não | hostname do SO | Nome do host no Zabbix — deve ser idêntico ao cadastrado |
| `ZABBIX_PLUGINS` | Não | vazio | Plugins opcionais do Agent 2 para instalar no modo `--auto`; vazio instala apenas o pacote base |
| `APPLY_FIREWALL` | Não | `n` | `yes` para aplicar a regra de firewall automaticamente |

---

## O que o script configura

### Arquivo principal gerado

`/etc/zabbix/zabbix_agent2.conf`

```ini
Server=<ZABBIX_SERVER>
ServerActive=<ZABBIX_SERVER>
Hostname=<ZABBIX_HOSTNAME>
ListenPort=<ZABBIX_PORT>
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=10
DebugLevel=3
Timeout=10
Include=/etc/zabbix/zabbix_agent2.d/*.conf
```

### User parameter instalado

Arquivo: `/etc/zabbix/zabbix_agent2.d/userparameters_2lock.conf`

| Chave | Tipo | Descrição |
|-------|------|-----------|
| `linux.top.cpu` | Text | JSON com os 5 processos de maior consumo de CPU |

Exemplo de retorno:
```json
[{"process":"java","cpu":45.2,"mem":12.1},{"process":"mysqld","cpu":12.3,"mem":8.4}]
```

Para usar no Zabbix: item do tipo **Zabbix agent**, chave `linux.top.cpu`, tipo de dado **Text**, intervalo sugerido **5m**.

### Firewall

A regra é criada **restrita ao IP do Zabbix Server** — não abre a porta para qualquer origem.

- **firewalld** (AlmaLinux/RHEL/Rocky): usa `rich-rule` com `source address`
- **ufw** (Ubuntu/Debian): usa `ufw allow from <IP> to any port <PORTA>`

---

## Integração com Docker

Se o Docker estiver instalado, o script automaticamente:

1. Detecta o grupo `docker` (ou `dockerroot`)
2. Adiciona o usuário `zabbix` ao grupo
3. Reinicia o agente para herdar a permissão
4. Valida o acesso com `docker.info`

> **Importante:** o Agent 2 roda como usuário `zabbix` (não root). Adicionar ao grupo docker é a forma correta e segura de conceder acesso ao socket.

Se o Docker for instalado **após** o agente, execute manualmente:

```bash
usermod -aG docker zabbix
systemctl restart zabbix-agent2
```

---

## Plugins adicionais

Durante a execução interativa, o script pergunta quais plugins opcionais do Zabbix Agent 2 devem ser instalados:

```text
[1] MySQL
[2] PostgreSQL
[3] MongoDB
[4] Memcached
[5] MSSQL
[6] Todos
[0] Nenhum (apenas zabbix-agent2)
```

No modo automatizado (`--auto`), use `ZABBIX_PLUGINS` com nomes ou números separados por espaço, vírgula ou ponto e vírgula:

```bash
ZABBIX_PLUGINS="mysql postgresql memcached"
ZABBIX_PLUGINS="1,4,5"
ZABBIX_PLUGINS="all"      # instala todos os plugins opcionais listados
ZABBIX_PLUGINS="none"     # instala apenas zabbix-agent2
```

Se `ZABBIX_PLUGINS` não for definida no modo `--auto`, o instalador instala somente o `zabbix-agent2` base.

Os pacotes seguem o padrão `zabbix-agent2-plugin-<nome>`, por exemplo:

| Plugin | Pacote |
|--------|--------|
| MySQL | `zabbix-agent2-plugin-mysql` |
| PostgreSQL | `zabbix-agent2-plugin-postgresql` |
| MongoDB | `zabbix-agent2-plugin-mongodb` |
| Memcached | `zabbix-agent2-plugin-memcached` |
| MSSQL | `zabbix-agent2-plugin-mssql` |

> **Importante:** Docker não é instalado como plugin via pacote. O script mantém o tratamento separado: quando detecta o grupo `docker` ou `dockerroot`, adiciona o usuário `zabbix` ao grupo para permitir acesso ao socket `/var/run/docker.sock`.

Após instalar ou alterar configurações de plugins em `/etc/zabbix/zabbix_agent2.d/`, reinicie o agente:

```bash
systemctl restart zabbix-agent2
```

---

## Validações realizadas pelo script

| Verificação | Resultado esperado |
|---|---|
| `agent.ping` | `1` |
| `agent.version` | Começa com `7.` |
| `system.uname` | Informativo |
| Hostname no conf | Igual ao informado |
| Porta escutando | Visível via `ss` |

---

## Log de instalação

```
/var/log/zabbix/2lock_install.log
```

---

##  Diagnóstico pós-instalação

```bash
# Status do serviço
systemctl status zabbix-agent2

# Últimas linhas do log
tail -50 /var/log/zabbix/zabbix_agent2.log

# Testar itens manualmente
zabbix_agent2 -t agent.ping
zabbix_agent2 -t agent.version
zabbix_agent2 -t linux.top.cpu

# Verificar porta escutando
ss -tlnp | grep <PORTA>

# Testar conectividade com o Zabbix Server
nc -zv <IP_ZABBIX> 10051
```

---

## Observações importantes

- O script **remove versões anteriores** do agente antes de instalar
- O arquivo de configuração existente recebe **backup automático** com timestamp
- Em caso de erro, o script remove o repositório Zabbix para evitar estado inconsistente
- TLS/PSK não é configurado automaticamente — comentários no arquivo gerado orientam como habilitar futuramente
