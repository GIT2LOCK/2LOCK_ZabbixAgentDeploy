#!/bin/bash
# =============================================================================
# 2LOCK -- Instalacao e Configuracao do Zabbix Agent 2
# Versao: 3.0 | Abril 2026
# Suporte: AlmaLinux / RHEL / Rocky (rpm) | Ubuntu / Debian (deb)
# Zabbix: 7.0 LTS (sempre a versao mais recente disponivel do 7.0)
#
# Uso interativo:
#   sudo ./zabbix_agent2_install.sh
#
# Uso automatizado (sem interacao):
#   sudo ACCEPT_EULA=yes ZABBIX_SERVER=10.0.0.1 ZABBIX_PORT=10050 \
#        ZABBIX_HOSTNAME=SERVIDOR01 APPLY_FIREWALL=yes \
#        ./zabbix_agent2_install.sh --auto
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# MODO NAO-INTERATIVO
# Flag --auto + variaveis de ambiente eliminam todas as perguntas
# -----------------------------------------------------------------------------
AUTO_MODE=false
for arg in "$@"; do
    [[ "$arg" == "--auto" ]] && AUTO_MODE=true
done

# Tenta vincular um descritor dedicado ao terminal de controle para leituras
# interativas mesmo quando o script for executado via pipe (curl | bash).
TTY_FD=""
if exec 3</dev/tty 2>/dev/null; then
    TTY_FD=3
fi

# -----------------------------------------------------------------------------
# CORES -- apenas caracteres ASCII puros, sem aspas inteligentes
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error()   { echo -e "${RED}[ERRO]${NC}  $*" >&2; }
die()     { error "$*"; exit 1; }
separator() { echo -e "${DIM}------------------------------------------------------${NC}"; }

# Sanitiza entrada de usuario/variaveis:
# - remove carriage return (\r)
# - remove espacos no inicio/fim
sanitize_input() {
    echo -n "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Leitura interativa robusta:
# - Prioriza /dev/tty para funcionar mesmo quando stdin estiver redirecionado
# - Retorna erro explicito se nao houver TTY disponivel
prompt_read() {
    local __var_name="$1"
    local __prompt="$2"
    local __value=""
    echo -n "$__prompt"
    if [[ -n "${TTY_FD}" ]]; then
        read -r __value <&"${TTY_FD}" || die "Falha ao ler entrada interativa no terminal."
    else
        die "Entrada interativa indisponivel (sem TTY). Use --auto com ACCEPT_EULA=yes para execucao nao interativa."
    fi
    __value="$(sanitize_input "$__value")"
    printf -v "$__var_name" '%s' "$__value"
}

# -----------------------------------------------------------------------------
# VERIFICACAO DE ROOT
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    die "Este script deve ser executado como root ou via sudo."
fi

# Log (criado apos verificacao de root)
LOG_FILE="/var/log/zabbix/2lock_install.log"
mkdir -p /var/log/zabbix
exec > >(tee -a "$LOG_FILE") 2>&1
echo "====== 2LOCK Zabbix Agent 2 Install -- $(date '+%Y-%m-%d %H:%M:%S') ======" >> "$LOG_FILE"

# -----------------------------------------------------------------------------
# TRAP -- CLEANUP EM CASO DE ERRO INESPERADO
# -----------------------------------------------------------------------------
INSTALL_STARTED=false
DISTRO=""
PKG_MANAGER=""

cleanup_on_error() {
    local exit_code=$?
    if [[ "$INSTALL_STARTED" == true && $exit_code -ne 0 ]]; then
        echo ""
        error "Instalacao interrompida com erro (codigo: ${exit_code})."
        warn  "Removendo repositorio Zabbix para evitar estado inconsistente..."
        if [[ "$DISTRO" == "rpm" ]]; then
            rpm -q zabbix-release &>/dev/null && \
                ${PKG_MANAGER:-dnf} remove -y zabbix-release &>/dev/null || true
        elif [[ "$DISTRO" == "deb" ]]; then
            dpkg -l zabbix-release 2>/dev/null | grep -q "^ii" && \
                apt-get remove -y zabbix-release &>/dev/null || true
        fi
        warn "Verifique o log completo em: ${LOG_FILE}"
    fi
}
trap cleanup_on_error EXIT

# -----------------------------------------------------------------------------
# FUNCAO: VALIDAR IPV4
# Valida cada octeto entre 0 e 255
# Rejeita entradas como 999.0.0.1 ou 10.256.1.1
# -----------------------------------------------------------------------------
validate_ipv4() {
    local ip="$1"
    local regex='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'
    if [[ ! "$ip" =~ $regex ]]; then
        return 1
    fi
    local octet
    for octet in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" \
                 "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
        if [[ "$octet" -gt 255 ]]; then
            return 1
        fi
    done
    return 0
}

# -----------------------------------------------------------------------------
# FUNCAO: EXTRAIR RESULTADO DO ZABBIX_AGENT2
# Formato de saida do agent2 -t:
#   item.key[...] [tipo|valor_tipo] | valor
# Extrai o campo apos o ultimo pipe e remove espacos
# -----------------------------------------------------------------------------
zbx_test() {
    local item="$1"
    local raw
    raw=$(zabbix_agent2 -t "$item" 2>/dev/null) || true
    echo "$raw" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $NF); print $NF}'
}

# -----------------------------------------------------------------------------
# BANNER 2LOCK -- ASCII puro, sem caracteres especiais
# -----------------------------------------------------------------------------
clear
echo ""
echo -e "${BOLD}${BLUE}"
cat << 'EOF'
  ╔════════════════════════════════════════════════════════╗
  ║                                                     TM ║
  ║   ██████╗ ██╗      ██████╗  ██████╗██╗  ██╗            ║
  ║  ╚════██╗██║     ██╔═══██╗██╔════╝██║ ██╔╝             ║
  ║   █████╔╝██║     ██║   ██║██║     █████╔╝              ║
  ║  ██╔═══╝ ██║     ██║   ██║██║     ██╔═██╗              ║
  ║  ███████╗███████╗╚██████╔╝╚██████╗██║  ██╗             ║
  ║  ╚══════╝╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝             ║
  ║                                                        ║
  ╚════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Informações de rodapé
echo -e "${BOLD}${CYAN}            Zabbix Agent 2 - Instalador Automatizado${NC}"
echo -e "${DIM}            Sempre Conectados! | Zabbix 7.0 LTS | $(date '+%Y')${NC}"

if [[ "$AUTO_MODE" == true ]]; then
    echo -e "${YELLOW}            [ STATUS: MODO AUTOMATIZADO ATIVO ]${NC}"
fi

echo ""
separator
echo ""
# -----------------------------------------------------------------------------
# TERMO DE USO
# -----------------------------------------------------------------------------
echo -e "${BOLD}  TERMO DE USO -- LEIA ANTES DE CONTINUAR${NC}"
echo ""
echo -e "${DIM}  Este instalador e de uso exclusivo da 2LOCK e foi desenvolvido"
echo    "  para automatizar a implantacao do Zabbix Agent 2"
echo ""
echo    "  >> Este script realizara alteracoes no sistema operacional,"
echo    "     incluindo instalacao de pacotes, arquivos de configuracao"
echo    "     e ajustes nas regras de firewall."
echo ""
echo    "  >> O Zabbix Agent 2 sera configurado EXCLUSIVAMENTE para"
echo    "     comunicacao com o servidor Zabbix informado na instalacao."
echo    "     Nenhum dado e enviado para servidores externos."
echo ""
echo    "  >> A execucao deve ser autorizada pelo responsavel tecnico."
echo    "     Utilize somente em ambientes aprovados pela equipe de infra."
echo ""
echo    "  >> A 2LOCK nao se responsabiliza por uso indevido deste"
echo    "     instalador fora do escopo de projetos sob sua gestao."
echo ""
separator
echo ""

if [[ "$AUTO_MODE" == true ]]; then
    if [[ "${ACCEPT_EULA:-}" != "yes" ]]; then
        die "Modo --auto requer ACCEPT_EULA=yes. Defina a variavel antes de executar."
    fi
    success "Termo aceito via ACCEPT_EULA=yes."
else
    prompt_read ACCEPT_TERMS "  Li e aceito os termos acima [s/N]: "
    echo ""
    if [[ ! "$ACCEPT_TERMS" =~ ^[sS]$ ]]; then
        info "Instalacao cancelada. Termo de uso nao aceito."
        exit 0
    fi
    success "Termo aceito. Prosseguindo..."
fi
echo ""

# -----------------------------------------------------------------------------
# DETECCAO DE DISTRIBUICAO
# -----------------------------------------------------------------------------
separator
info "Detectando distribuicao Linux..."

DISTRO_VERSION=""
FIREWALL_TYPE=""

if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
    DISTRO_VERSION="${VERSION_ID:-}"
    DISTRO_PRETTY="${PRETTY_NAME:-desconhecido}"
else
    die "Nao foi possivel detectar a distribuicao. /etc/os-release nao encontrado."
fi

if echo "${DISTRO_ID} ${DISTRO_ID_LIKE}" | grep -qiE "rhel|almalinux|rocky|centos|fedora"; then
    DISTRO="rpm"
    PKG_MANAGER="dnf"
    command -v dnf &>/dev/null || PKG_MANAGER="yum"
    FIREWALL_TYPE="firewalld"
elif echo "${DISTRO_ID} ${DISTRO_ID_LIKE}" | grep -qiE "ubuntu|debian"; then
    DISTRO="deb"
    PKG_MANAGER="apt-get"
    FIREWALL_TYPE="ufw"
else
    die "Distribuicao nao suportada: ${DISTRO_PRETTY}"
fi

ARCH=$(uname -m)

# Mapeia arquitetura para o nome usado nas URLs do repositorio Zabbix RPM
# DEB nao precisa -- o apt resolve via dpkg --print-architecture automaticamente
case "$ARCH" in
    x86_64)  REPO_ARCH="x86_64" ;;
    aarch64) REPO_ARCH="aarch64" ;;
    *)
        die "Arquitetura nao suportada: '${ARCH}'.\nZabbix Agent 2 7.0 suporta: x86_64 (Intel/AMD) e aarch64 (ARM 64-bit)."
        ;;
esac

success "Distribuicao : ${DISTRO_PRETTY}"
info    "Arquitetura  : ${ARCH} (repo: ${REPO_ARCH})"
info    "Familia pkg  : ${DISTRO} (${PKG_MANAGER})"
info    "Firewall     : ${FIREWALL_TYPE}"
echo ""

# -----------------------------------------------------------------------------
# VERIFICACAO DE NTP
# -----------------------------------------------------------------------------
separator
info "Verificando sincronismo de horario (NTP)..."

NTP_OK=false
if   systemctl is-active --quiet chronyd          2>/dev/null; then NTP_OK=true; success "chronyd esta ativo."
elif systemctl is-active --quiet ntpd             2>/dev/null; then NTP_OK=true; success "ntpd esta ativo."
elif systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then NTP_OK=true; success "systemd-timesyncd esta ativo."
fi

if [[ "$NTP_OK" == false ]]; then
    warn "Nenhum servico NTP ativo detectado!"
    warn "Diferenca de horario entre agente e Zabbix Server causa"
    warn "problemas silenciosos de coleta e alertas incorretos."
    echo ""
    if [[ "$AUTO_MODE" == true ]]; then
        warn "Modo --auto: continuando mesmo sem NTP."
    else
        prompt_read CONTINUE_NTP "  Deseja continuar mesmo assim? [s/N]: "
        [[ ! "$CONTINUE_NTP" =~ ^[sS]$ ]] && { info "Instalacao cancelada."; exit 0; }
    fi
fi
echo ""

# -----------------------------------------------------------------------------
# COLETA DE INFORMACOES
# -----------------------------------------------------------------------------
separator
echo -e "${BOLD}  Configuracao do agente${NC}"
echo ""

# --- Hostname ---
CURRENT_HOSTNAME=$(hostname -s)

if [[ "$AUTO_MODE" == true ]]; then
    ZABBIX_HOSTNAME="$(sanitize_input "${ZABBIX_HOSTNAME:-$CURRENT_HOSTNAME}")"
    info "Hostname (automatico): ${ZABBIX_HOSTNAME}"
else
    echo -e "  Hostname detectado: ${YELLOW}${CURRENT_HOSTNAME}${NC}"
    prompt_read INPUT_HOSTNAME "  Pressione Enter para confirmar ou digite outro: "
    ZABBIX_HOSTNAME="${INPUT_HOSTNAME:-$CURRENT_HOSTNAME}"
fi

if [[ -z "$ZABBIX_HOSTNAME" ]]; then
    die "Hostname invalido: valor vazio apos limpeza. Informe ao menos 1 caractere."
fi

if [[ ! "$ZABBIX_HOSTNAME" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    die "Hostname invalido: '${ZABBIX_HOSTNAME}'. Use apenas letras, numeros, hifen, underscore ou ponto."
fi
echo ""

# --- IP do Zabbix Server ---
if [[ "$AUTO_MODE" == true ]]; then
    [[ -z "${ZABBIX_SERVER:-}" ]] && \
        die "Modo --auto requer ZABBIX_SERVER=<IP>."
    ZABBIX_SERVER_IP="$(sanitize_input "${ZABBIX_SERVER}")"
    if ! validate_ipv4 "$ZABBIX_SERVER_IP"; then
        die "ZABBIX_SERVER invalido: '${ZABBIX_SERVER_IP}'. Informe um IPv4 valido."
    fi
    info "Zabbix Server IP (automatico): ${ZABBIX_SERVER_IP}"
else
    while true; do
        prompt_read ZABBIX_SERVER_IP "  IP do Zabbix Server: "
        if validate_ipv4 "$ZABBIX_SERVER_IP"; then
            break
        else
            warn "  IP invalido. Cada octeto deve estar entre 0 e 255 (ex: 10.156.6.2)."
        fi
    done
fi
echo ""

# --- Porta ---
if [[ "$AUTO_MODE" == true ]]; then
    ZABBIX_AGENT_PORT="$(sanitize_input "${ZABBIX_PORT:-10050}")"
    info "Porta do agente (automatico): ${ZABBIX_AGENT_PORT}"
else
    echo -e "  ${DIM}Porta padrao do Zabbix: 10050${NC}"
    while true; do
        prompt_read INPUT_PORT "  Porta do agente [Enter = 10050]: "
        ZABBIX_AGENT_PORT="${INPUT_PORT:-10050}"
        if [[ "$ZABBIX_AGENT_PORT" =~ ^[0-9]+$ ]] && \
           [[ "$ZABBIX_AGENT_PORT" -ge 1024 ]] && \
           [[ "$ZABBIX_AGENT_PORT" -le 65535 ]]; then
            break
        else
            warn "  Porta invalida. Informe um numero entre 1024 e 65535."
        fi
    done
fi
echo ""

# -----------------------------------------------------------------------------
# VERIFICACAO DE CONECTIVIDADE
# -----------------------------------------------------------------------------
separator
info "Verificando conectividade de rede..."
echo ""

info "Testando acesso a repo.zabbix.com..."
if curl -s --connect-timeout 5 --max-time 8 -o /dev/null \
    -w "%{http_code}" "https://repo.zabbix.com" | grep -qE "^(200|301|302)"; then
    success "repo.zabbix.com ............. acessivel (HTTPS)"
else
    warn "repo.zabbix.com ............. sem resposta"
    if [[ "$AUTO_MODE" == true ]]; then
        warn "Modo --auto: continuando mesmo sem acesso ao repositorio."
    else
        prompt_read CONTINUE_REPO "  Deseja continuar mesmo assim? [s/N]: "
        [[ ! "$CONTINUE_REPO" =~ ^[sS]$ ]] && { info "Instalacao cancelada."; exit 0; }
    fi
fi

info "Testando alcance ao Zabbix Server (${ZABBIX_SERVER_IP})..."
if ping -c 2 -W 3 "$ZABBIX_SERVER_IP" &>/dev/null; then
    success "Zabbix Server ............... alcancavel via ICMP"
else
    warn    "Zabbix Server ............... sem resposta ICMP (pode estar bloqueado -- nao critico)"
fi

info "Testando porta 10051/TCP no Zabbix Server..."
if command -v nc &>/dev/null; then
    if nc -z -w 4 "$ZABBIX_SERVER_IP" 10051 &>/dev/null; then
        success "Porta 10051/TCP ............. aberta (Zabbix Server respondendo)"
    else
        warn    "Porta 10051/TCP ............. sem resposta -- verificar firewall do Zabbix Server"
    fi
else
    info "nc (netcat) nao disponivel -- teste de porta 10051 ignorado."
fi
echo ""

# -----------------------------------------------------------------------------
# FIREWALL -- REGRA RESTRITA AO IP DO ZABBIX SERVER
# Nao abre a porta para qualquer origem
# -----------------------------------------------------------------------------
separator
info "Verificando firewall para porta ${ZABBIX_AGENT_PORT}/TCP..."
info "A regra sera restrita ao IP do Zabbix Server: ${ZABBIX_SERVER_IP}"
echo ""

FIREWALL_APPLIED=false

check_and_apply_firewall() {

    # --- firewalld (AlmaLinux / RHEL / Rocky) ---
    if [[ "$FIREWALL_TYPE" == "firewalld" ]]; then
        if ! command -v firewall-cmd &>/dev/null; then
            warn "firewalld nao instalado. Verifique a liberacao manualmente."
            return
        fi
        if ! systemctl is-active --quiet firewalld; then
            warn "firewalld esta INATIVO neste servidor."
            info "Se usar iptables direto:"
            echo "    iptables -A INPUT -s ${ZABBIX_SERVER_IP} -p tcp --dport ${ZABBIX_AGENT_PORT} -j ACCEPT"
            return
        fi

        # Verifica se a rich rule ja existe para este IP e porta
        local existing_rules
        existing_rules=$(firewall-cmd --list-rich-rules --zone=public 2>/dev/null || true)
        if echo "$existing_rules" | grep -q "source address=\"${ZABBIX_SERVER_IP}\"" && \
           echo "$existing_rules" | grep -q "port=\"${ZABBIX_AGENT_PORT}\""; then
            success "Regra ja existe no firewalld para ${ZABBIX_SERVER_IP}:${ZABBIX_AGENT_PORT}/TCP."
            FIREWALL_APPLIED=true
            return
        fi

        warn "Porta ${ZABBIX_AGENT_PORT}/TCP nao esta liberada para ${ZABBIX_SERVER_IP}."
        echo ""

        local apply_fw="n"
        if [[ "$AUTO_MODE" == true ]]; then
            apply_fw="$(sanitize_input "${APPLY_FIREWALL:-n}")"
        else
            prompt_read apply_fw "  Deseja liberar agora (somente para ${ZABBIX_SERVER_IP})? [s/N]: "
        fi
        echo ""

        if [[ "$apply_fw" =~ ^([sS]|yes)$ ]]; then
            firewall-cmd --permanent --zone=public \
                --add-rich-rule="rule family=\"ipv4\" source address=\"${ZABBIX_SERVER_IP}\" port port=\"${ZABBIX_AGENT_PORT}\" protocol=\"tcp\" accept" \
                || die "Falha ao adicionar rich rule no firewalld."
            firewall-cmd --reload \
                || die "Falha ao recarregar o firewalld."
            success "Regra aplicada: somente ${ZABBIX_SERVER_IP} acessa a porta ${ZABBIX_AGENT_PORT}/TCP."
            FIREWALL_APPLIED=true
        else
            warn "Porta nao liberada. Aplique manualmente:"
            echo ""
            echo "    firewall-cmd --permanent --zone=public \\"
            echo "      --add-rich-rule='rule family=\"ipv4\" source address=\"${ZABBIX_SERVER_IP}\" port port=\"${ZABBIX_AGENT_PORT}\" protocol=\"tcp\" accept'"
            echo "    firewall-cmd --reload"
        fi

    # --- ufw (Ubuntu / Debian) ---
    elif [[ "$FIREWALL_TYPE" == "ufw" ]]; then
        if ! command -v ufw &>/dev/null; then
            warn "ufw nao instalado. Verifique a liberacao manualmente."
            return
        fi

        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1 | awk '{print $2}')
        if [[ "$ufw_status" != "active" ]]; then
            warn "ufw esta INATIVO neste servidor."
            info "Se usar iptables direto:"
            echo "    iptables -A INPUT -s ${ZABBIX_SERVER_IP} -p tcp --dport ${ZABBIX_AGENT_PORT} -j ACCEPT"
            return
        fi

        # Verifica se regra especifica para este IP e porta ja existe
        if ufw status 2>/dev/null | grep -q "${ZABBIX_SERVER_IP}" && \
           ufw status 2>/dev/null | grep -q "${ZABBIX_AGENT_PORT}"; then
            success "Regra ja existe no ufw para ${ZABBIX_SERVER_IP}:${ZABBIX_AGENT_PORT}/TCP."
            FIREWALL_APPLIED=true
            return
        fi

        warn "Porta ${ZABBIX_AGENT_PORT}/TCP nao esta liberada para ${ZABBIX_SERVER_IP}."
        echo ""

        local apply_fw="n"
        if [[ "$AUTO_MODE" == true ]]; then
            apply_fw="$(sanitize_input "${APPLY_FIREWALL:-n}")"
        else
            prompt_read apply_fw "  Deseja liberar agora (somente para ${ZABBIX_SERVER_IP})? [s/N]: "
        fi
        echo ""

        if [[ "$apply_fw" =~ ^([sS]|yes)$ ]]; then
            ufw allow from "${ZABBIX_SERVER_IP}" to any port "${ZABBIX_AGENT_PORT}" proto tcp \
                comment "Zabbix Agent 2 - 2LOCK" \
                || die "Falha ao adicionar regra no ufw."
            success "Regra aplicada: somente ${ZABBIX_SERVER_IP} acessa a porta ${ZABBIX_AGENT_PORT}/TCP."
            FIREWALL_APPLIED=true
        else
            warn "Porta nao liberada. Aplique manualmente:"
            echo "    ufw allow from ${ZABBIX_SERVER_IP} to any port ${ZABBIX_AGENT_PORT} proto tcp"
        fi
    fi
}

check_and_apply_firewall
echo ""

# -----------------------------------------------------------------------------
# CONFIRMACAO FINAL -- ignorada em modo automatizado
# -----------------------------------------------------------------------------
separator
echo -e "  ${BOLD}Resumo -- o seguinte sera executado no sistema:${NC}"
echo ""
echo -e "  Hostname no Zabbix : ${GREEN}${ZABBIX_HOSTNAME}${NC}"
echo -e "  Zabbix Server IP   : ${GREEN}${ZABBIX_SERVER_IP}${NC}"
echo -e "  Porta do agente    : ${GREEN}${ZABBIX_AGENT_PORT}/TCP${NC}"
echo -e "  Distribuicao       : ${GREEN}${DISTRO_PRETTY}${NC}"
echo -e "  Pacote             : ${GREEN}zabbix-agent2 latest 7.0 + plugins${NC}"
echo -e "  PSK / Criptografia : ${YELLOW}Desabilitado${NC}"
if [[ "$FIREWALL_APPLIED" == true ]]; then
    echo -e "  Firewall           : ${GREEN}${ZABBIX_AGENT_PORT}/TCP liberado (somente ${ZABBIX_SERVER_IP})${NC}"
else
    echo -e "  Firewall           : ${YELLOW}Pendente -- liberar manualmente${NC}"
fi
echo -e "  Log de instalacao  : ${DIM}${LOG_FILE}${NC}"
echo ""
separator
echo ""

if [[ "$AUTO_MODE" == true ]]; then
    info "Modo --auto: iniciando sem confirmacao manual."
else
    prompt_read CONFIRM "  Confirmar e iniciar instalacao? [s/N]: "
    echo ""
    [[ ! "$CONFIRM" =~ ^[sS]$ ]] && { info "Instalacao cancelada."; exit 0; }
fi

# A partir daqui: alteracoes reais no sistema
INSTALL_STARTED=true

# -----------------------------------------------------------------------------
# REMOCAO DE VERSOES ANTERIORES
# -----------------------------------------------------------------------------
separator
info "Verificando instalacao anterior do Zabbix Agent..."

remove_old_agents_rpm() {
    local agents_found=()
    rpm -q zabbix-agent2 &>/dev/null && agents_found+=("zabbix-agent2")
    rpm -q zabbix-agent  &>/dev/null && agents_found+=("zabbix-agent")
    if [[ ${#agents_found[@]} -gt 0 ]]; then
        warn "Encontrado(s): ${agents_found[*]} -- removendo..."
        for svc in zabbix-agent2 zabbix-agent; do
            systemctl is-active  "$svc" &>/dev/null && systemctl stop    "$svc" || true
            systemctl is-enabled "$svc" &>/dev/null && systemctl disable "$svc" || true
        done
        $PKG_MANAGER remove -y "${agents_found[@]}" &>/dev/null
        rm -rf /etc/zabbix/zabbix_agent*.conf /etc/zabbix/zabbix_agent*.d 2>/dev/null || true
        success "Agente(s) anterior(es) removido(s)."
    else
        success "Nenhum agente anterior encontrado."
    fi
}

remove_old_agents_deb() {
    local agents_found=()
    dpkg -l zabbix-agent2 2>/dev/null | grep -q "^ii" && agents_found+=("zabbix-agent2")
    dpkg -l zabbix-agent  2>/dev/null | grep -q "^ii" && agents_found+=("zabbix-agent")
    if [[ ${#agents_found[@]} -gt 0 ]]; then
        warn "Encontrado(s): ${agents_found[*]} -- removendo..."
        for svc in zabbix-agent2 zabbix-agent; do
            systemctl is-active  "$svc" &>/dev/null && systemctl stop    "$svc" || true
            systemctl is-enabled "$svc" &>/dev/null && systemctl disable "$svc" || true
        done
        $PKG_MANAGER remove --purge -y "${agents_found[@]}" &>/dev/null
        $PKG_MANAGER autoremove -y &>/dev/null
        rm -rf /etc/zabbix/zabbix_agent*.conf /etc/zabbix/zabbix_agent*.d 2>/dev/null || true
        success "Agente(s) anterior(es) removido(s)."
    else
        success "Nenhum agente anterior encontrado."
    fi
}

[[ "$DISTRO" == "rpm" ]] && remove_old_agents_rpm
[[ "$DISTRO" == "deb" ]] && remove_old_agents_deb
echo ""

# -----------------------------------------------------------------------------
# INSTALACAO DO REPOSITORIO ZABBIX 7.0
# -----------------------------------------------------------------------------
separator
info "Configurando repositorio Zabbix 7.0 (latest)..."

install_repo_rpm() {
    local major_ver
    major_ver=$(echo "$DISTRO_VERSION" | cut -d. -f1)
    local repo_distro="rhel"
    [[ "${DISTRO_ID:-}" == "centos" ]] && repo_distro="centos"
    # O pacote zabbix-release é noarch (independente de arquitetura)
    # mas a URL do repositorio varia por arquitetura no Zabbix 7.0
    local repo_url="https://repo.zabbix.com/zabbix/7.0/${repo_distro}/${major_ver}/${REPO_ARCH}/zabbix-release-latest.el${major_ver}.noarch.rpm"
    info "URL: ${repo_url}"
    $PKG_MANAGER remove -y zabbix-release &>/dev/null || true
    $PKG_MANAGER install -y "$repo_url" &>/dev/null \
        || die "Falha ao instalar repositorio Zabbix. Verifique conectividade com repo.zabbix.com"
    $PKG_MANAGER clean all &>/dev/null
    $PKG_MANAGER makecache &>/dev/null || true
    success "Repositorio Zabbix 7.0 configurado (RPM)."
}

install_repo_deb() {
    local codename
    codename=$(lsb_release -sc 2>/dev/null || echo "${VERSION_CODENAME:-}")
    [[ -z "$codename" ]] && \
        die "Nao foi possivel detectar o codename da distro. Instale o pacote lsb-release."
    local repo_distro="ubuntu"
    [[ "${DISTRO_ID:-}" == "debian" ]] && repo_distro="debian"
    local deb_pkg="zabbix-release_7.0-1+${repo_distro}${DISTRO_VERSION}_all.deb"
    local deb_url="https://repo.zabbix.com/zabbix/7.0/${repo_distro}/pool/main/z/zabbix-release/${deb_pkg}"
    info "Baixando: ${deb_pkg}"
    local tmp_deb="/tmp/${deb_pkg}"
    wget -q "$deb_url" -O "$tmp_deb" \
        || die "Falha ao baixar repositorio. URL: ${deb_url}"
    dpkg -i "$tmp_deb" &>/dev/null \
        || die "Falha ao instalar pacote de repositorio."
    rm -f "$tmp_deb"
    $PKG_MANAGER update -qq &>/dev/null
    success "Repositorio Zabbix 7.0 configurado (DEB)."
}

[[ "$DISTRO" == "rpm" ]] && install_repo_rpm
[[ "$DISTRO" == "deb" ]] && install_repo_deb
echo ""

# -----------------------------------------------------------------------------
# INSTALACAO DO ZABBIX AGENT 2 + PLUGINS
# -----------------------------------------------------------------------------
separator
info "Instalando Zabbix Agent 2 (versao mais recente do 7.0) e plugins..."

if [[ "$DISTRO" == "rpm" ]]; then
    $PKG_MANAGER install -y zabbix-agent2 zabbix-agent2-plugin-* \
        || die "Falha na instalacao do zabbix-agent2. Consulte o log acima e: ${LOG_FILE}"
elif [[ "$DISTRO" == "deb" ]]; then
    DEBIAN_FRONTEND=noninteractive $PKG_MANAGER install -y \
        zabbix-agent2 zabbix-agent2-plugin-* \
        || die "Falha na instalacao do zabbix-agent2. Consulte o log acima e: ${LOG_FILE}"
fi

command -v zabbix_agent2 &>/dev/null \
    || die "Binario zabbix_agent2 nao encontrado apos instalacao."

AGENT_VERSION_RAW=$(zabbix_agent2 -V 2>&1)
AGENT_VERSION_FULL=${AGENT_VERSION_RAW%%$'\n'*}
success "Instalado: ${AGENT_VERSION_FULL}"
echo ""

# -----------------------------------------------------------------------------
# DOCKER -- ADICIONAR USUARIO ZABBIX AO GRUPO DOCKER (SE INSTALADO)
# -----------------------------------------------------------------------------
separator
info "Verificando instalacao do Docker..."
echo ""

DOCKER_GROUP_ADDED=false

add_zabbix_to_docker_group() {
    local docker_group=""
    if   getent group docker      &>/dev/null; then docker_group="docker"
    elif getent group dockerroot  &>/dev/null; then docker_group="dockerroot"
    fi

    if [[ -z "$docker_group" ]]; then
        info "Docker nao encontrado -- etapa ignorada."
        info "Caso instale o Docker futuramente, execute:"
        echo    "    usermod -aG docker zabbix"
        echo    "    systemctl restart zabbix-agent2"
        return
    fi

    success "Docker detectado (grupo: ${docker_group})."

    if id -nG zabbix 2>/dev/null | grep -qw "$docker_group"; then
        success "Usuario zabbix ja pertence ao grupo ${docker_group}."
        return
    fi

    info "Adicionando usuario zabbix ao grupo ${docker_group}..."
    if usermod -aG "$docker_group" zabbix 2>/dev/null; then
        success "Usuario zabbix adicionado ao grupo ${docker_group}."
        info    "O servico sera reiniciado ao final para aplicar a mudanca de grupo."
        DOCKER_GROUP_ADDED=true
    else
        warn "Falha ao adicionar zabbix ao grupo ${docker_group} -- instalacao continua."
        warn "Execute manualmente apos a instalacao:"
        echo    "    usermod -aG ${docker_group} zabbix"
        echo    "    systemctl restart zabbix-agent2"
    fi
}

add_zabbix_to_docker_group
echo ""

# -----------------------------------------------------------------------------
# USER PARAMETERS -- METRICAS CUSTOMIZADAS
# -----------------------------------------------------------------------------
separator
info "Configurando user parameters customizados..."
echo ""

setup_user_parameters() {
    local up_file="/etc/zabbix/zabbix_agent2.d/userparameters_2lock.conf"

    # Cria ou sobrescreve o arquivo de user parameters
    cat > "$up_file" << 'UPEOF'
# =============================================================================
# User Parameters -- 2LOCK
# Metricas customizadas coletadas pelo Zabbix Agent 2
# =============================================================================

# --- linux.top.cpu ---
# Retorna JSON com os 5 processos que mais consomem CPU no momento
# Formato: [{"process":"nome","cpu":X.X,"mem":X.X}, ...]
# Uso no Zabbix: Item tipo "Zabbix agent", chave: linux.top.cpu
# Tipo de dado: Text | Intervalo sugerido: 5m
UserParameter=linux.top.cpu,ps -eo comm,%cpu,%mem --sort=-%cpu | head -n 6 | tail -n +2 | awk 'BEGIN{printf "["}{printf "%s{\"process\":\"%s\",\"cpu\":%s,\"mem\":%s}",(NR>1?",":""),$1,$2,$3}END{printf "]"}'
UPEOF

    chown zabbix:zabbix "$up_file" 2>/dev/null || true
    chmod 640 "$up_file"
    success "User parameter criado: ${up_file}"

    # Valida o comando diretamente antes de reiniciar o servico
    info "Validando comando do user parameter..."
    local test_output
    test_output=$(ps -eo comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 6 | tail -n +2 | awk 'BEGIN{printf "["}{printf "%s{\"process\":\"%s\",\"cpu\":%s,\"mem\":%s}",(NR>1?",":""),$1,$2,$3}END{printf "]"}')
    if echo "$test_output" | grep -q '"process"'; then
        success "Saida do comando validada:"
        echo    "    ${test_output}"
    else
        warn "Comando retornou saida inesperada: '${test_output}'"
        warn "Verifique manualmente apos a instalacao."
    fi
}

setup_user_parameters
echo ""

# -----------------------------------------------------------------------------
# CONFIGURACAO DO ZABBIX AGENT 2
# Usa heredoc com delimitador sem aspas para expandir variaveis corretamente
# -----------------------------------------------------------------------------
separator
info "Gerando arquivo de configuracao..."

AGENT_CONF="/etc/zabbix/zabbix_agent2.conf"
AGENT_CONF_D="/etc/zabbix/zabbix_agent2.d"

if [[ -f "$AGENT_CONF" ]]; then
    cp "$AGENT_CONF" "${AGENT_CONF}.bkp.$(date +%Y%m%d%H%M%S)"
    info "Backup: ${AGENT_CONF}.bkp.*"
fi

mkdir -p "$AGENT_CONF_D"

cat > "$AGENT_CONF" << AGENTEOF
# =============================================================================
# Zabbix Agent 2 -- 2LOCK
# Gerado automaticamente em: $(date '+%Y-%m-%d %H:%M:%S')
# Versao instalada: ${AGENT_VERSION_FULL}
# Host: ${ZABBIX_HOSTNAME} | Server: ${ZABBIX_SERVER_IP} | Porta: ${ZABBIX_AGENT_PORT}
# =============================================================================

# --- Servidor Zabbix ---
Server=${ZABBIX_SERVER_IP}
ServerActive=${ZABBIX_SERVER_IP}

# --- Identidade do Host ---
# OBRIGATORIO: deve ser IDENTICO ao nome cadastrado no Zabbix
Hostname=${ZABBIX_HOSTNAME}

# --- Porta de escuta ---
ListenPort=${ZABBIX_AGENT_PORT}

# --- Logs ---
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=10
DebugLevel=3

# --- Performance ---
Timeout=10

# --- Includes ---
Include=${AGENT_CONF_D}/*.conf

# --- Seguranca ---
# PSK desabilitado -- rede interna corporativa
# Para habilitar PSK futuramente:
#   TLSConnect=psk
#   TLSAccept=psk
#   TLSPSKIdentity=<identidade>
#   TLSPSKFile=/etc/zabbix/zabbix_agent2.psk
AGENTEOF

# Placeholder no includes -- delimitador com aspas simples para nao expandir variaveis
cat > "${AGENT_CONF_D}/README.conf" << 'READMEEOF'
# Diretorio de plugins do Zabbix Agent 2 -- 2LOCK
# Coloque aqui arquivos .conf para plugins adicionais.
# Exemplos:
#   mysql.conf  -- Plugin MySQL
#   mssql.conf  -- Plugin MSSQL
# Apos qualquer alteracao: systemctl restart zabbix-agent2
READMEEOF

chown -R zabbix:zabbix /etc/zabbix/ 2>/dev/null || true
chmod 640 "$AGENT_CONF"

success "Configuracao gerada: ${AGENT_CONF}"
echo ""


# Compatibilidade: alguns templates antigos usam parametros nao suportados pelo Agent2
# Ex.: MaxLinesPerSecond (valido no agentd, invalido no agent2).
sanitize_unsupported_params() {
    local changed=0
    local f

    for f in "$AGENT_CONF" "$AGENT_CONF_D"/*.conf; do
        [[ -f "$f" ]] || continue
        if grep -Eq '^[[:space:]]*MaxLinesPerSecond=' "$f"; then
            sed -i -E 's/^[[:space:]]*(MaxLinesPerSecond=.*)$/# 2LOCK-AUTO-COMMENT (invalido no agent2): \1/' "$f"
            warn "Parametro invalido para zabbix_agent2 removido automaticamente: MaxLinesPerSecond em ${f}"
            changed=1
        fi
    done

    return $changed
}

# -----------------------------------------------------------------------------
# VALIDACAO PREVIA DA CONFIGURACAO
# Garante que o binario carregue o conf antes do restart do servico
# -----------------------------------------------------------------------------
separator
sanitize_unsupported_params || true

info "Executando validacao previa da configuracao..."

if ! command -v zabbix_agent2 &>/dev/null; then
    die "Binario zabbix_agent2 nao encontrado apos a instalacao."
fi

if ! zabbix_agent2 -c "$AGENT_CONF" -t agent.ping >/dev/null 2>&1; then
    error "Validacao previa falhou: zabbix_agent2 nao conseguiu carregar a configuracao."
    warn  "Saida detalhada do teste local:"
    zabbix_agent2 -c "$AGENT_CONF" -t agent.ping || true
    warn  "Revise tambem o conteudo de: ${AGENT_CONF} e ${AGENT_CONF_D}/*.conf"
    exit 1
fi

success "Validacao previa concluida: configuracao carregada com sucesso."
echo ""

# -----------------------------------------------------------------------------
# HABILITAR E INICIAR O SERVICO
# -----------------------------------------------------------------------------
separator
info "Habilitando e iniciando servico zabbix-agent2..."

systemctl daemon-reload
systemctl enable zabbix-agent2 &>/dev/null

if ! systemctl restart zabbix-agent2; then
    error "Falha ao iniciar o servico zabbix-agent2 apos gerar a configuracao."
    warn  "Status resumido do servico:"
    systemctl status --no-pager -l zabbix-agent2 || true
    warn  "Ultimas linhas do journal (zabbix-agent2):"
    journalctl -u zabbix-agent2 -n 50 --no-pager || true
    exit 1
fi
sleep 3

# Reinicia novamente se grupo Docker foi adicionado (necessario para herdar grupo)
if [[ "$DOCKER_GROUP_ADDED" == true ]]; then
    info "Reiniciando para aplicar permissao de grupo Docker..."
    if ! systemctl restart zabbix-agent2; then
        error "Falha ao reiniciar o servico apos ajuste de grupo Docker."
        warn  "Status resumido do servico:"
        systemctl status --no-pager -l zabbix-agent2 || true
        warn  "Ultimas linhas do journal (zabbix-agent2):"
        journalctl -u zabbix-agent2 -n 50 --no-pager || true
        exit 1
    fi
    sleep 2
fi

if systemctl is-active --quiet zabbix-agent2; then
    success "Servico zabbix-agent2 esta ATIVO."
    if [[ "$DOCKER_GROUP_ADDED" == true ]]; then
        local_docker_result=$(zbx_test "docker.info")
        if echo "$local_docker_result" | grep -qi "version"; then
            success "Acesso ao Docker validado -- coleta de containers pronta."
        else
            warn "Agente no ar, mas docker.info nao retornou dados esperados."
            warn "Verifique se o socket /var/run/docker.sock esta acessivel."
        fi
    fi
else
    error "Servico zabbix-agent2 nao iniciou corretamente."
    warn  "Verifique: journalctl -u zabbix-agent2 -n 30"
    exit 1
fi
echo ""

# -----------------------------------------------------------------------------
# VALIDACAO FINAL
# Usa zbx_test() para extrair corretamente o valor apos o ultimo pipe
# Nao compara system.hostname com ZABBIX_HOSTNAME -- valida o conf diretamente
# -----------------------------------------------------------------------------
separator
info "Validando agente instalado..."
echo ""

PING_RESULT=$(zbx_test "agent.ping")
VER_RESULT=$(zbx_test  "agent.version")
OS_RESULT=$(zbx_test   "system.uname")

# agent.ping deve retornar exatamente "1"
if [[ "$PING_RESULT" == "1" ]]; then
    success "agent.ping .................. 1 (OK)"
else
    warn    "agent.ping .................. '${PING_RESULT}' (esperado: 1 -- verificar servico)"
fi

# agent.version deve comecar com "7."
if echo "$VER_RESULT" | grep -q "^7\."; then
    success "agent.version ............... ${VER_RESULT} (OK)"
else
    warn    "agent.version ............... '${VER_RESULT}' (verificar instalacao)"
fi

# system.uname -- informativo
if [[ -n "$OS_RESULT" ]]; then
    success "system.uname ................ ${OS_RESULT}"
else
    warn    "system.uname ................ sem retorno (nao critico)"
fi

# Valida hostname lendo diretamente o arquivo de configuracao gerado
CONF_HOSTNAME=$(grep "^Hostname=" "$AGENT_CONF" 2>/dev/null | cut -d'=' -f2 || true)
if [[ "$CONF_HOSTNAME" == "$ZABBIX_HOSTNAME" ]]; then
    success "Hostname no conf ............ ${CONF_HOSTNAME} (OK)"
else
    warn    "Hostname no conf ............ '${CONF_HOSTNAME}' (esperado: ${ZABBIX_HOSTNAME})"
fi

# Porta escutando
if ss -tlnp 2>/dev/null | grep -q ":${ZABBIX_AGENT_PORT} " || \
   netstat -tlnp 2>/dev/null | grep -q ":${ZABBIX_AGENT_PORT} "; then
    success "Porta ${ZABBIX_AGENT_PORT}/TCP .......... ESCUTANDO (OK)"
else
    warn    "Porta ${ZABBIX_AGENT_PORT}/TCP .......... nao detectada via ss/netstat"
fi
echo ""

if [[ "$FIREWALL_APPLIED" == false ]]; then
    separator
    warn "Porta ${ZABBIX_AGENT_PORT}/TCP ainda precisa ser liberada no firewall!"
    warn "IMPORTANTE: restrinja ao IP do Zabbix Server (${ZABBIX_SERVER_IP})"
    echo ""
    if [[ "$FIREWALL_TYPE" == "firewalld" ]]; then
        echo "    firewall-cmd --permanent --zone=public \\"
        echo "      --add-rich-rule='rule family=\"ipv4\" source address=\"${ZABBIX_SERVER_IP}\" port port=\"${ZABBIX_AGENT_PORT}\" protocol=\"tcp\" accept'"
        echo "    firewall-cmd --reload"
    else
        echo "    ufw allow from ${ZABBIX_SERVER_IP} to any port ${ZABBIX_AGENT_PORT} proto tcp"
    fi
    echo ""
fi

separator
echo ""
success "Instalacao concluida com sucesso!"
echo -e "  ${DIM}Host     : ${ZABBIX_HOSTNAME}${NC}"
echo -e "  ${DIM}Server   : ${ZABBIX_SERVER_IP}${NC}"
echo -e "  ${DIM}Porta    : ${ZABBIX_AGENT_PORT}${NC}"
echo -e "  ${DIM}Versao   : ${AGENT_VERSION_FULL}${NC}"
if [[ "$DOCKER_GROUP_ADDED" == true ]]; then
    echo -e "  ${DIM}Docker   : usuario zabbix adicionado ao grupo docker${NC}"
else
    echo -e "  ${DIM}Docker   : nao detectado (configurar manualmente se necessario)${NC}"
fi
echo -e "  ${DIM}Log      : ${LOG_FILE}${NC}"
echo ""
