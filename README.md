# 2LOCK — Zabbix Agent Deploy

Scripts e guias para instalação e configuração automatizada do **Zabbix Agent 2** em ambientes Linux e Windows.

Desenvolvido e mantido pela **2LOCK** para uso em projetos de monitoramento com **Zabbix 7.0 LTS**.

---

## Estrutura do Repositório

```
zabbix-agent-deploy/
│
├── linux/
│   ├── zabbix_agent2_install.sh   ← Instalador automatizado
│   ├── README.md                  ← Instruções de uso e parâmetros
│   └── plugins/
│       └── mysql.md               ← Configuração do plugin MySQL
│
└── windows/
    ├── zabbix_agent2_install.ps1  ← Instalador automatizado (PowerShell)
    ├── README.md                  ← Instruções de uso e parâmetros
    └── plugins/
        └── mssql.md               ← Configuração do plugin MSSQL
```

Cada pasta é **autossuficiente** — tudo que você precisa para instalar e configurar o agente em um determinado sistema operacional está dentro da pasta correspondente.

---

## Linux — Instalação Rápida

Compatível com **AlmaLinux / RHEL / Rocky** e **Ubuntu / Debian** (x86_64 e aarch64).

### Uma linha — via 2LOCK (recomendado)

```bash
curl -fsSL https://2lock.com.br/linuxagent | sudo bash
```

### Download direto do GitHub

```bash
curl -O https://raw.githubusercontent.com/2lock/zabbix-agent-deploy/main/linux/zabbix_agent2_install.sh
chmod +x zabbix_agent2_install.sh
sudo ./zabbix_agent2_install.sh
```

### Modo automatizado (sem interação)

```bash
sudo ACCEPT_EULA=yes \
     ZABBIX_SERVER=10.0.0.1 \
     ZABBIX_PORT=10050 \
     ZABBIX_HOSTNAME=MEUSERVIDOR \
     APPLY_FIREWALL=yes \
     bash <(curl -fsSL https://2lock.com.br/linuxagent) --auto
```

> Veja o [README do Linux](linux/README.md) para detalhes completos de uso e parâmetros.

---

## Windows — Instalação Rápida

Compatível com **Windows Server 2016 / 2019 / 2022**.

### Uma linha — via 2LOCK (recomendado)

Executar no **PowerShell como Administrador**:

```powershell
iwr https://2lock.com.br/windowsagent | iex
```

### Modo automatizado (sem interação)

```powershell
$env:ACCEPT_EULA    = "yes"
$env:ZABBIX_SERVER  = "10.0.0.1"
$env:ZABBIX_PORT    = "10050"
$env:ZABBIX_HOSTNAME = "MEUSERVIDOR"
$env:APPLY_FIREWALL = "yes"
iwr https://2lock.com.br/windowsagent | iex
```

> Veja o [README do Windows](windows/README.md) para detalhes completos de uso e parâmetros.

---

## O que os instaladores fazem

### Linux
- Detecta automaticamente a distribuição e arquitetura (x86_64 / aarch64)
- Verifica sincronismo NTP antes de instalar
- Remove versões anteriores do agente
- Configura o repositório oficial Zabbix 7.0
- Instala o Zabbix Agent 2 base e permite selecionar plugins opcionais (interativo ou `ZABBIX_PLUGINS` no modo `--auto`)
- Adiciona o usuário `zabbix` ao grupo `docker` (se Docker estiver instalado)
- Configura user parameter customizado: `linux.top.cpu`
- Aplica regra de firewall restrita ao IP do Zabbix Server
- Valida a instalação e gera log completo

### Windows
- Baixa o instalador MSI oficial do Zabbix 7.0
- Instala e configura o Zabbix Agent 2 como serviço Windows
- Configura a porta de escuta e o hostname
- Aplica regra de firewall restrita ao IP do Zabbix Server
- Valida o serviço e a conectividade

---

##  Plugins disponíveis

| Plugin | SO | Instalação rápida | Documentação |
|--------|----|-------------------|-------------|
| MySQL | Linux | [linux/plugins/mysql.md](linux/plugins/mysql.md) | Configuração passo a passo |
| MSSQL | Windows | [windows/plugins/mssql.md](windows/plugins/mssql.md) | Configuração passo a passo |
| Docker | Linux | automático via grupo `docker` | ver [linux/README.md](linux/README.md) |

---

##  Sistemas testados

| SO | Versão | Arquitetura | Status |
|---|---|---|---|
| AlmaLinux | 9.x | x86_64 | ✅ Validado |
| AlmaLinux | 8.x | x86_64 | ✅ Validado |
| RHEL | 9.x | x86_64 | ✅ Validado |
| Rocky Linux | 9.x | x86_64 | ✅ Validado |
| Ubuntu | 22.04 LTS | x86_64 | ✅ Validado |
| Ubuntu | 20.04 LTS | x86_64 | ✅ Validado |
| Debian | 11 / 12 | x86_64 | ✅ Validado |
| Windows Server | 2022 | x86_64 | 🔜 Em breve |
| Windows Server | 2019 | x86_64 | 🔜 Em breve |

---

## Pré-requisitos gerais

- Acesso root (Linux) ou Administrador (Windows)
- Conectividade com `repo.zabbix.com` (HTTPS)
- IP do Zabbix Server acessível na rede
- NTP ativo no servidor (recomendado)

---

## Licença

Este repositório é de propriedade da **2LOCK**. O uso dos scripts é permitido em ambientes sob gestão da 2LOCK. Para outros usos, entre em contato.

---

##  Contribuições

Scripts mantidos pela equipe de infraestrutura da 2LOCK. Para sugestões ou correções https://2lock.com.br/contato/
