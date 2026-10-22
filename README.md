# ![2LOCK](https://2lock.com.br/wp-content/uploads/2024/10/logo.webp)

# 2LOCK — Zabbix Agent Deploy

> Scripts e guias para instalação e configuração automatizada do **Zabbix Agent 2** em ambientes Linux e Windows.
>
> Desenvolvido e mantido pela **2LOCK** para uso em projetos de monitoramento com **Zabbix 7.0 LTS**.

![Zabbix 7.0 LTS](https://img.shields.io/badge/Zabbix-7.0%20LTS-1B2B6B?style=flat-square&logo=zabbix&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-x86__64%20%7C%20aarch64-2D52C4?style=flat-square&logo=linux&logoColor=white)
![Windows](https://img.shields.io/badge/Windows%20Server-2016%20%7C%202019%20%7C%202022-2D52C4?style=flat-square&logo=windows&logoColor=white)
![Automatizado](https://img.shields.io/badge/Deploy-Automatizado-4FC3E8?style=flat-square)

---

## Estrutura do Repositório

```
zabbix-agent-deploy/
│
├── linux/
│   ├── zabbix_agent2_install.sh         ← Instalador automatizado
│   ├── README.md                        ← Instruções de uso e parâmetros
│   └── plugins/
│       └── mysql.md                     ← Configuração do plugin MySQL
│
└── windows/
    ├── zabbix_agent2_install_simple.ps1 ← Instalador interativo (PowerShell)
    ├── README.md                        ← Instruções de uso
    └── plugins/
        └── mssql.md                     ← Configuração do plugin MSSQL
```

> Cada pasta é **autossuficiente** — tudo que você precisa para instalar e configurar o agente em um determinado sistema operacional está dentro da pasta correspondente.

---

## 🐧 Linux — Instalação Rápida

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

## 🪟 Windows — Instalação Rápida

Compatível com **Windows Server 2016 / 2019 / 2022** (x64, PowerShell 5.1 ou superior).

### Uma linha — via GitHub (recomendado)

Executar no **PowerShell como Administrador**:

```powershell
irm https://raw.githubusercontent.com/GIT2LOCK/2LOCK_ZabbixAgentDeploy/main/windows/zabbix_agent2_install_simple.ps1 | iex
```

O instalador é **interativo** e faz as perguntas durante a execução:

1. Aceite do termo de uso
2. Nome do host (idêntico ao cadastrado no Zabbix)
3. IP do Zabbix Server ou Proxy
4. Porta do agente (padrão `10050`)
5. Plugins opcionais

### Download direto do GitHub

```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/GIT2LOCK/2LOCK_ZabbixAgentDeploy/main/windows/zabbix_agent2_install_simple.ps1 -OutFile zabbix_agent2_install_simple.ps1

# Inspecionar
notepad zabbix_agent2_install_simple.ps1

# Executar (PowerShell como Administrador)
.\zabbix_agent2_install_simple.ps1
```

> Não há modo automatizado no Windows nesta versão. Veja o [README do Windows](windows/README.md) para o passo a passo, exemplo de sessão e problemas comuns.

---

## ⚙️ O que os instaladores fazem

### 🐧 Linux

- Detecta automaticamente a distribuição e arquitetura (x86_64 / aarch64)
- Verifica sincronismo NTP antes de instalar
- Remove versões anteriores do agente
- Configura o repositório oficial Zabbix 7.0
- Instala o Zabbix Agent 2 base e permite selecionar plugins opcionais (interativo ou `ZABBIX_PLUGINS` no modo `--auto`)
- Adiciona o usuário `zabbix` ao grupo `docker` (se Docker estiver instalado)
- Configura user parameter customizado: `linux.top.cpu`
- Aplica regra de firewall restrita ao IP do Zabbix Server
- Valida a instalação e gera log completo

### 🪟 Windows

- Exibe o termo de uso e exige o aceite (`s`)
- Pergunta hostname, IP do Zabbix Server, porta do agente (padrão `10050`) e plugins opcionais
- Testa a conectividade com o Zabbix Server na porta `10051`
- Baixa o MSI oficial da série 7.0 (`latest`) na CDN da Zabbix e valida a assinatura digital
- Instala o Zabbix Agent 2 como serviço Windows e ajusta o `zabbix_agent2.conf` (com backup)
- Instala o pacote `zabbix_agent2_plugins` quando há plugin *loadable* selecionado e gera stubs de configuração (sem credenciais)
- Aplica regra de firewall restrita ao IP do Zabbix Server, com a porta no nome da regra
- Inicia o serviço e mostra o resumo da instalação

---

## 🔌 Plugins disponíveis

| Plugin | SO | Documentação |
|--------|----|--------------|
| MySQL  | Linux   | [linux/plugins/mysql.md](linux/plugins/mysql.md) |
| MSSQL  | Windows | [windows/plugins/mssql.md](windows/plugins/mssql.md) |
| MySQL, Memcached | Windows | Built-in no `zabbix_agent2.exe`; o instalador gera só o stub de configuração |
| PostgreSQL, MongoDB | Windows | Pacote `zabbix_agent2_plugins` instalado pelo instalador; stub gerado, sessões a preencher |
| Docker | Linux   | Automático via grupo `docker` — ver [linux/README.md](linux/README.md) |

> No Windows, o instalador **não preenche credenciais** de plugin: os stubs são só comentários, e as sessões devem ser configuradas depois.

---

## ✅ Sistemas testados

| Sistema Operacional | Versão     | Arquitetura | Status        |
|---------------------|------------|-------------|---------------|
| AlmaLinux           | 9.x        | x86_64      | ✅ Validado   |
| AlmaLinux           | 8.x        | x86_64      | ✅ Validado   |
| RHEL                | 9.x        | x86_64      | ✅ Validado   |
| Rocky Linux         | 9.x        | x86_64      | ✅ Validado   |
| Ubuntu              | 22.04 LTS  | x86_64      | ✅ Validado   |
| Ubuntu              | 20.04 LTS  | x86_64      | ✅ Validado   |
| Debian              | 11 / 12    | x86_64      | ✅ Validado   |
| Windows Server      | 2025       | x86_64      | 🔜 Em breve  |
| Windows Server      | 2022       | x86_64      | ✅ Validado   |
| Windows Server      | 2019       | x86_64      | ✅ Validado   |
| Windows Server      | 2016       | x86_64      | 🔜 Em breve  |

---

## 📋 Pré-requisitos gerais

- Acesso root (Linux) ou Administrador com PowerShell elevado (Windows)
- Conectividade com `repo.zabbix.com` (Linux) ou `cdn.zabbix.com` (Windows), via HTTPS
- IP do Zabbix Server acessível na rede (porta `10051` do servidor e a porta do agente, padrão `10050`)
- NTP ativo no servidor (recomendado)

---

## 📄 Licença

Este repositório é de propriedade da **2LOCK**. O uso dos scripts é permitido em ambientes sob gestão da 2LOCK. Para outros usos, entre em contato.

---

## 🤝 Contribuições

Scripts mantidos pela equipe de infraestrutura da 2LOCK. Para sugestões ou correções: [https://2lock.com.br/contato/](https://2lock.com.br/contato/)

---

<div align="center">
  <img src="https://2lock.com.br/wp-content/uploads/2024/10/logo.webp" alt="2LOCK" height="32">
  <br>
  <sub>Conectividade e segurança de redes para empresas · <a href="https://2lock.com.br">2lock.com.br</a></sub>
</div>
