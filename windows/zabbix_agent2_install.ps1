<#
=============================================================================
2LOCK -- Instalacao e Configuracao do Zabbix Agent 2 (Windows)
Versao: 1.0 | Setembro 2026
Suporte: Windows Server 2016 / 2019 / 2022 (x64)
Zabbix: 7.0 LTS (versao fixada em ZABBIX_VERSION, revisar periodicamente)

Uso interativo (executar como Administrador):
    .\zabbix_agent2_install.ps1

Uso automatizado (sem interacao):
    $env:ACCEPT_EULA     = "yes"
    $env:ZABBIX_SERVER   = "10.0.0.1"
    $env:ZABBIX_PORT     = "10050"
    $env:ZABBIX_HOSTNAME = "SERVIDOR01"
    $env:APPLY_FIREWALL  = "yes"
    $env:ZABBIX_PLUGINS  = "mssql"
    .\zabbix_agent2_install.ps1 -Auto

Uso via uma linha (iwr | iex) -- modo automatico e ligado automaticamente
quando ACCEPT_EULA=yes ja esta definido no ambiente, pois nao ha como
passar -Auto atraves do pipe:
    $env:ACCEPT_EULA = "yes"; $env:ZABBIX_SERVER = "10.0.0.1"
    iwr https://2lock.com.br/windowsagent | iex
=============================================================================
#>

[CmdletBinding()]
param(
    [switch]$Auto
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# -----------------------------------------------------------------------------
# MODO NAO-INTERATIVO
# -----------------------------------------------------------------------------
$AutoMode = $Auto.IsPresent -or ($env:ACCEPT_EULA -eq "yes")

# -----------------------------------------------------------------------------
# VERSAO DO ZABBIX AGENT 2 A INSTALAR
# Fixada manualmente (nao existe alias "latest" na CDN da Zabbix para Windows).
# Ultima verificada: 7.0.30 (25 ago 2026). Revisar em www.zabbix.com/download_agents
# antes de reutilizar este script em projetos futuros.
# -----------------------------------------------------------------------------
$ZabbixVersion = if ($env:ZABBIX_VERSION) { $env:ZABBIX_VERSION } else { "7.0.30" }
$ZabbixMajor   = ($ZabbixVersion -split '\.')[0..1] -join '.'

# -----------------------------------------------------------------------------
# CORES / HELPERS DE SAIDA
# -----------------------------------------------------------------------------
function Write-InfoMsg    { param([string]$Msg) Write-Host "[INFO]  $Msg" -ForegroundColor Cyan }
function Write-OkMsg      { param([string]$Msg) Write-Host "[OK]    $Msg" -ForegroundColor Green }
function Write-WarnMsg    { param([string]$Msg) Write-Host "[AVISO] $Msg" -ForegroundColor Yellow }
function Write-ErrMsg     { param([string]$Msg) Write-Host "[ERRO]  $Msg" -ForegroundColor Red }
function Write-Separator  { Write-Host ("-" * 60) -ForegroundColor DarkGray }
function Stop-Install     { param([string]$Msg) Write-ErrMsg $Msg; throw $Msg }

function Read-Prompt {
    param([string]$Prompt)
    Write-Host -NoNewline $Prompt
    return (Read-Host).Trim()
}

# -----------------------------------------------------------------------------
# PLUGINS OPCIONAIS
# No Windows, os plugins ja vem compilados dentro do zabbix_agent2.exe: nao ha
# pacote separado para instalar. A "selecao" aqui decide apenas quais arquivos
# de configuracao de plugin (stub) sao gerados em zabbix_agent2.d\.
# Apenas MSSQL tem guia completo neste repositorio (windows\plugins\mssql.md);
# os demais geram apenas um stub comentado.
# -----------------------------------------------------------------------------
$PluginKeys = @("mysql", "postgresql", "mongodb", "memcached", "mssql")
$SelectedPlugins = @()

function Get-PluginLabel {
    param([string]$Key)
    switch ($Key) {
        "mysql"      { "MySQL" }
        "postgresql" { "PostgreSQL" }
        "mongodb"    { "MongoDB" }
        "memcached"  { "Memcached" }
        "mssql"      { "MSSQL" }
        default      { $null }
    }
}

function Get-PluginKeyFromToken {
    param([string]$Token)
    $t = $Token.ToLowerInvariant()
    if (@("1","mysql") -contains $t)                { return "mysql" }
    if (@("2","postgresql","postgres") -contains $t) { return "postgresql" }
    if (@("3","mongodb","mongo") -contains $t)       { return "mongodb" }
    if (@("4","memcached") -contains $t)             { return "memcached" }
    if (@("5","mssql","sqlserver") -contains $t)     { return "mssql" }
    return $null
}

function Get-PluginSelectionLabel {
    if ($SelectedPlugins.Count -eq 0) { return "Nenhum (apenas zabbix_agent2.exe base)" }
    return (($SelectedPlugins | ForEach-Object { Get-PluginLabel $_ }) -join ", ")
}

function Resolve-PluginSelection {
    param([string]$Raw)
    $script:SelectedPlugins = @()
    if ([string]::IsNullOrWhiteSpace($Raw)) { return }

    $tokens = $Raw -split '[,;\s]+' | Where-Object { $_ -ne "" }
    foreach ($token in $tokens) {
        $tl = $token.ToLowerInvariant()
        if (@("0","none","nenhum","nenhuma","base") -contains $tl) { $script:SelectedPlugins = @(); return }
        if (@("6","all","todos","todas","*") -contains $tl) { $script:SelectedPlugins = $PluginKeys.Clone(); return }

        $key = Get-PluginKeyFromToken $tl
        if (-not $key) {
            Stop-Install "Selecao de plugins: opcao invalida '$token'. Use numeros 1-6, 0, ou nomes como mysql,mssql."
        }
        if ($script:SelectedPlugins -notcontains $key) { $script:SelectedPlugins += $key }
    }
}

function Show-PluginPrompt {
    Write-Host "  Plugins opcionais do Zabbix Agent 2 (ja compilados no binario)" -ForegroundColor White
    Write-Host "  Apenas MSSQL tem guia completo neste projeto (windows\plugins\mssql.md)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Selecione os plugins a configurar (Enter = nenhum):"
    Write-Host ""
    Write-Host "  [1] MySQL"
    Write-Host "  [2] PostgreSQL"
    Write-Host "  [3] MongoDB"
    Write-Host "  [4] Memcached"
    Write-Host "  [5] MSSQL"
    Write-Host "  [6] Todos"
    Write-Host "  [0] Nenhum"
    Write-Host ""
    $raw = Read-Prompt "  Opcoes (ex: 5 ou 0 para nenhum): "
    Resolve-PluginSelection $raw
    Write-OkMsg "Plugins selecionados: $(Get-PluginSelectionLabel)."
}

# -----------------------------------------------------------------------------
# VALIDACAO DE IPV4
# -----------------------------------------------------------------------------
function Test-IPv4 {
    param([string]$Ip)
    if ($Ip -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') { return $false }
    foreach ($i in 1..4) { if ([int]$Matches[$i] -gt 255) { return $false } }
    return $true
}

# -----------------------------------------------------------------------------
# EXTRAIR RESULTADO DO ZABBIX_AGENT2 -T
# Formato: item.key[...] [tipo] | valor
# -----------------------------------------------------------------------------
function Invoke-ZbxTest {
    param([string]$AgentExe, [string]$Conf, [string]$Item)
    $raw = & $AgentExe -c $Conf -t $Item 2>$null
    if (-not $raw) { return "" }
    $line = ($raw | Select-Object -Last 1)
    $parts = $line -split '\|'
    return ($parts[-1]).Trim()
}

# -----------------------------------------------------------------------------
# VERIFICACAO DE ADMINISTRADOR
# -----------------------------------------------------------------------------
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-Install "Este script deve ser executado como Administrador (PowerShell elevado)."
}

# -----------------------------------------------------------------------------
# LOG
# -----------------------------------------------------------------------------
$LogDir  = "C:\ProgramData\zabbix"
$LogFile = Join-Path $LogDir "2lock_install.log"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
try { Start-Transcript -Path $LogFile -Append | Out-Null } catch { }

# -----------------------------------------------------------------------------
# BANNER
# -----------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Blue
Write-Host "   2LOCK - Zabbix Agent 2 - Instalador Automatizado (Windows)"     -ForegroundColor Cyan
Write-Host "   Sempre Conectados! | Zabbix 7.0 LTS | $(Get-Date -Format yyyy)"  -ForegroundColor DarkGray
if ($AutoMode) {
    Write-Host "   [ STATUS: MODO AUTOMATIZADO ATIVO ]" -ForegroundColor Yellow
}
Write-Host "  ================================================================" -ForegroundColor Blue
Write-Host ""
Write-Separator
Write-Host ""

# -----------------------------------------------------------------------------
# TERMO DE USO
# -----------------------------------------------------------------------------
Write-Host "  TERMO DE USO -- LEIA ANTES DE CONTINUAR" -ForegroundColor White
Write-Host ""
Write-Host "  Este instalador e de uso exclusivo da 2LOCK e foi desenvolvido" -ForegroundColor DarkGray
Write-Host "  para automatizar a implantacao do Zabbix Agent 2." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  >> Este script realizara alteracoes no sistema operacional,"
Write-Host "     incluindo instalacao de software, arquivos de configuracao"
Write-Host "     e ajustes nas regras de firewall."
Write-Host ""
Write-Host "  >> O Zabbix Agent 2 sera configurado EXCLUSIVAMENTE para"
Write-Host "     comunicacao com o servidor Zabbix informado na instalacao."
Write-Host "     Nenhum dado e enviado para servidores externos."
Write-Host ""
Write-Host "  >> A execucao deve ser autorizada pelo responsavel tecnico."
Write-Host "     Utilize somente em ambientes aprovados pela equipe de infra."
Write-Host ""
Write-Host "  >> A 2LOCK nao se responsabiliza por uso indevido deste"
Write-Host "     instalador fora do escopo de projetos sob sua gestao."
Write-Host ""
Write-Separator
Write-Host ""

if ($AutoMode) {
    if ($env:ACCEPT_EULA -ne "yes") {
        Stop-Install "Modo automatico requer `$env:ACCEPT_EULA = 'yes'. Defina a variavel antes de executar."
    }
    Write-OkMsg "Termo aceito via ACCEPT_EULA=yes."
} else {
    $acceptTerms = Read-Prompt "  Li e aceito os termos acima [s/N]: "
    Write-Host ""
    if ($acceptTerms -notmatch '^[sS]$') {
        Write-InfoMsg "Instalacao cancelada. Termo de uso nao aceito."
        try { Stop-Transcript | Out-Null } catch { }
        return
    }
    Write-OkMsg "Termo aceito. Prosseguindo..."
}
Write-Host ""

# -----------------------------------------------------------------------------
# DETECCAO DO SISTEMA OPERACIONAL
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Detectando sistema operacional..."

$os = Get-CimInstance Win32_OperatingSystem
$osCaption = $os.Caption
$osBuild   = [int]$os.BuildNumber

$knownServerBuilds = @{ 14393 = "2016"; 17763 = "2019"; 20348 = "2022" }
if ($knownServerBuilds.ContainsKey($osBuild)) {
    Write-OkMsg "Sistema operacional: $osCaption (Windows Server $($knownServerBuilds[$osBuild]))"
} else {
    Write-WarnMsg "Sistema operacional nao esta na lista testada (2016/2019/2022): $osCaption (build $osBuild)"
    if (-not $AutoMode) {
        $continueOs = Read-Prompt "  Deseja continuar mesmo assim? [s/N]: "
        if ($continueOs -notmatch '^[sS]$') { Write-InfoMsg "Instalacao cancelada."; try { Stop-Transcript | Out-Null } catch { }; return }
    } else {
        Write-WarnMsg "Modo automatico: continuando mesmo com SO nao testado."
    }
}

if (-not [Environment]::Is64BitOperatingSystem) {
    Stop-Install "Sistema operacional de 32 bits detectado. Zabbix Agent 2 7.0 requer x64."
}
Write-OkMsg "Arquitetura: x64"
Write-Host ""

# -----------------------------------------------------------------------------
# VERIFICACAO DE SINCRONISMO DE HORARIO (W32TIME)
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Verificando sincronismo de horario (W32Time)..."

$w32time = Get-Service -Name W32Time -ErrorAction SilentlyContinue
if ($w32time -and $w32time.Status -eq "Running") {
    Write-OkMsg "Servico W32Time esta ativo."
} else {
    Write-WarnMsg "Servico W32Time nao esta ativo (ou nao encontrado)."
    Write-WarnMsg "Diferenca de horario entre agente e Zabbix Server causa"
    Write-WarnMsg "problemas silenciosos de coleta e alertas incorretos."
    Write-Host ""
    if ($AutoMode) {
        Write-WarnMsg "Modo automatico: continuando mesmo sem W32Time ativo."
    } else {
        $continueNtp = Read-Prompt "  Deseja continuar mesmo assim? [s/N]: "
        if ($continueNtp -notmatch '^[sS]$') { Write-InfoMsg "Instalacao cancelada."; try { Stop-Transcript | Out-Null } catch { }; return }
    }
}
Write-Host ""

# -----------------------------------------------------------------------------
# COLETA DE INFORMACOES
# -----------------------------------------------------------------------------
Write-Separator
Write-Host "  Configuracao do agente" -ForegroundColor White
Write-Host ""

# --- Hostname ---
$currentHostname = $env:COMPUTERNAME
if ($AutoMode) {
    $ZabbixHostname = if ($env:ZABBIX_HOSTNAME) { $env:ZABBIX_HOSTNAME.Trim() } else { $currentHostname }
    Write-InfoMsg "Hostname (automatico): $ZabbixHostname"
} else {
    Write-Host "  Hostname detectado: " -NoNewline
    Write-Host $currentHostname -ForegroundColor Yellow
    $inputHostname = Read-Prompt "  Pressione Enter para confirmar ou digite outro: "
    $ZabbixHostname = if ($inputHostname) { $inputHostname } else { $currentHostname }
}

if ([string]::IsNullOrWhiteSpace($ZabbixHostname)) {
    Stop-Install "Hostname invalido: valor vazio."
}
if ($ZabbixHostname -notmatch '^[a-zA-Z0-9_.-]+$') {
    Stop-Install "Hostname invalido: '$ZabbixHostname'. Use apenas letras, numeros, hifen, underscore ou ponto."
}
Write-Host ""

# --- IP do Zabbix Server ---
if ($AutoMode) {
    if (-not $env:ZABBIX_SERVER) { Stop-Install "Modo automatico requer `$env:ZABBIX_SERVER = '<IP>'." }
    $ZabbixServerIp = $env:ZABBIX_SERVER.Trim()
    if (-not (Test-IPv4 $ZabbixServerIp)) { Stop-Install "ZABBIX_SERVER invalido: '$ZabbixServerIp'. Informe um IPv4 valido." }
    Write-InfoMsg "Zabbix Server IP (automatico): $ZabbixServerIp"
} else {
    do {
        $ZabbixServerIp = Read-Prompt "  IP do Zabbix Server: "
        if (-not (Test-IPv4 $ZabbixServerIp)) { Write-WarnMsg "  IP invalido. Cada octeto deve estar entre 0 e 255 (ex: 10.156.6.2)." }
    } while (-not (Test-IPv4 $ZabbixServerIp))
}
Write-Host ""

# --- Porta ---
if ($AutoMode) {
    $ZabbixAgentPort = if ($env:ZABBIX_PORT) { $env:ZABBIX_PORT.Trim() } else { "10050" }
    Write-InfoMsg "Porta do agente (automatico): $ZabbixAgentPort"
} else {
    Write-Host "  Porta padrao do Zabbix: 10050" -ForegroundColor DarkGray
    do {
        $inputPort = Read-Prompt "  Porta do agente [Enter = 10050]: "
        $ZabbixAgentPort = if ($inputPort) { $inputPort } else { "10050" }
        $portValid = ($ZabbixAgentPort -match '^\d+$') -and ([int]$ZabbixAgentPort -ge 1024) -and ([int]$ZabbixAgentPort -le 65535)
        if (-not $portValid) { Write-WarnMsg "  Porta invalida. Informe um numero entre 1024 e 65535." }
    } while (-not $portValid)
}
Write-Host ""

# --- Plugins opcionais ---
if ($AutoMode) {
    Resolve-PluginSelection ($env:ZABBIX_PLUGINS)
    Write-InfoMsg "Plugins selecionados (automatico): $(Get-PluginSelectionLabel)."
} else {
    Show-PluginPrompt
}
Write-Host ""

# -----------------------------------------------------------------------------
# VERIFICACAO DE CONECTIVIDADE
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Verificando conectividade de rede..."
Write-Host ""

Write-InfoMsg "Testando acesso a cdn.zabbix.com..."
try {
    $probe = Invoke-WebRequest -Uri "https://cdn.zabbix.com" -Method Head -UseBasicParsing -TimeoutSec 8
    Write-OkMsg "cdn.zabbix.com ............. acessivel (HTTPS)"
} catch {
    Write-WarnMsg "cdn.zabbix.com ............. sem resposta"
    if ($AutoMode) {
        Write-WarnMsg "Modo automatico: continuando mesmo sem acesso a CDN."
    } else {
        $continueRepo = Read-Prompt "  Deseja continuar mesmo assim? [s/N]: "
        if ($continueRepo -notmatch '^[sS]$') { Write-InfoMsg "Instalacao cancelada."; try { Stop-Transcript | Out-Null } catch { }; return }
    }
}

Write-InfoMsg "Testando alcance ao Zabbix Server ($ZabbixServerIp)..."
if (Test-Connection -ComputerName $ZabbixServerIp -Count 2 -Quiet -ErrorAction SilentlyContinue) {
    Write-OkMsg "Zabbix Server ............... alcancavel via ICMP"
} else {
    Write-WarnMsg "Zabbix Server ............... sem resposta ICMP (pode estar bloqueado, nao critico)"
}

Write-InfoMsg "Testando porta 10051/TCP no Zabbix Server..."
$tcpTest = Test-NetConnection -ComputerName $ZabbixServerIp -Port 10051 -WarningAction SilentlyContinue
if ($tcpTest.TcpTestSucceeded) {
    Write-OkMsg "Porta 10051/TCP ............. aberta (Zabbix Server respondendo)"
} else {
    Write-WarnMsg "Porta 10051/TCP ............. sem resposta, verificar firewall do Zabbix Server"
}
Write-Host ""

# -----------------------------------------------------------------------------
# FIREWALL -- REGRA RESTRITA AO IP DO ZABBIX SERVER
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Verificando firewall para porta $ZabbixAgentPort/TCP..."
Write-InfoMsg "A regra sera restrita ao IP do Zabbix Server: $ZabbixServerIp"
Write-Host ""

$FirewallApplied = $false
$FwRuleName = "Zabbix Agent 2 - 2LOCK"

$existingRule = Get-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue
if ($existingRule) {
    $portFilter = $existingRule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    $addrFilter = $existingRule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
    if ($portFilter.LocalPort -eq $ZabbixAgentPort -and $addrFilter.RemoteAddress -contains $ZabbixServerIp) {
        Write-OkMsg "Regra ja existe para $ZabbixServerIp`:$ZabbixAgentPort/TCP."
        $FirewallApplied = $true
    }
}

if (-not $FirewallApplied) {
    Write-WarnMsg "Porta $ZabbixAgentPort/TCP nao esta liberada para $ZabbixServerIp."
    Write-Host ""
    $applyFw = "n"
    if ($AutoMode) {
        $applyFw = if ($env:APPLY_FIREWALL) { $env:APPLY_FIREWALL.Trim() } else { "n" }
    } else {
        $applyFw = Read-Prompt "  Deseja liberar agora (somente para $ZabbixServerIp)? [s/N]: "
    }
    Write-Host ""

    if ($applyFw -match '^([sS]|yes)$') {
        if ($existingRule) { Remove-NetFirewallRule -DisplayName $FwRuleName -ErrorAction SilentlyContinue }
        New-NetFirewallRule -DisplayName $FwRuleName -Direction Inbound -Protocol TCP `
            -LocalPort $ZabbixAgentPort -RemoteAddress $ZabbixServerIp -Action Allow | Out-Null
        Write-OkMsg "Regra aplicada: somente $ZabbixServerIp acessa a porta $ZabbixAgentPort/TCP."
        $FirewallApplied = $true
    } else {
        Write-WarnMsg "Porta nao liberada. Aplique manualmente:"
        Write-Host ""
        Write-Host "    New-NetFirewallRule -DisplayName '$FwRuleName' -Direction Inbound ``"
        Write-Host "      -Protocol TCP -LocalPort $ZabbixAgentPort -RemoteAddress $ZabbixServerIp -Action Allow"
        Write-Host ""
    }
}
Write-Host ""

# -----------------------------------------------------------------------------
# CONFIRMACAO FINAL
# -----------------------------------------------------------------------------
Write-Separator
Write-Host "  Resumo -- o seguinte sera executado no sistema:" -ForegroundColor White
Write-Host ""
Write-Host "  Hostname no Zabbix : " -NoNewline; Write-Host $ZabbixHostname -ForegroundColor Green
Write-Host "  Zabbix Server IP   : " -NoNewline; Write-Host $ZabbixServerIp -ForegroundColor Green
Write-Host "  Porta              : " -NoNewline; Write-Host $ZabbixAgentPort -ForegroundColor Green
Write-Host "  Versao do agente   : " -NoNewline; Write-Host $ZabbixVersion -ForegroundColor Green
Write-Host "  Plugins            : " -NoNewline; Write-Host (Get-PluginSelectionLabel) -ForegroundColor Green
Write-Host ""

if (-not $AutoMode) {
    $finalConfirm = Read-Prompt "  Confirmar e iniciar a instalacao? [s/N]: "
    if ($finalConfirm -notmatch '^[sS]$') { Write-InfoMsg "Instalacao cancelada."; try { Stop-Transcript | Out-Null } catch { }; return }
}
Write-Host ""

# -----------------------------------------------------------------------------
# REMOCAO DE AGENTES ANTERIORES
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Verificando instalacoes anteriores do Zabbix Agent..."

foreach ($svcName in @("Zabbix Agent 2", "Zabbix Agent")) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-WarnMsg "Servico encontrado: $svcName. Parando..."
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
    }
}

$uninstallRoots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$oldAgents = Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "Zabbix Agent*" }

if ($oldAgents) {
    foreach ($entry in $oldAgents) {
        Write-WarnMsg "Removendo: $($entry.DisplayName) ($($entry.PSChildName))..."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$($entry.PSChildName)`" /qn /norestart" -Wait -NoNewWindow
    }
    Write-OkMsg "Agente(s) anterior(es) removido(s)."
} else {
    Write-OkMsg "Nenhum agente anterior encontrado."
}
Write-Host ""

# -----------------------------------------------------------------------------
# DOWNLOAD DO MSI OFICIAL (variante estatica, sem dependencia de OpenSSL)
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Baixando Zabbix Agent 2 $ZabbixVersion (MSI oficial)..."

$MsiName = "zabbix_agent2-$ZabbixVersion-windows-amd64-static.msi"
$MsiUrl  = "https://cdn.zabbix.com/zabbix/binaries/stable/$ZabbixMajor/$ZabbixVersion/$MsiName"
$MsiPath = Join-Path $env:TEMP $MsiName

Write-InfoMsg "URL: $MsiUrl"
try {
    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing
} catch {
    Stop-Install "Falha ao baixar o MSI. Verifique conectividade com cdn.zabbix.com e se a versao $ZabbixVersion existe. Detalhe: $($_.Exception.Message)"
}

if (-not (Test-Path $MsiPath)) { Stop-Install "Download do MSI nao encontrado em $MsiPath." }
Write-OkMsg "Download concluido: $MsiPath"
Write-Host ""

# -----------------------------------------------------------------------------
# INSTALACAO SILENCIOSA DO MSI
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Instalando Zabbix Agent 2..."

$InstallDir = if ($env:ZABBIX_INSTALL_DIR) { $env:ZABBIX_INSTALL_DIR } else { "C:\Program Files\Zabbix Agent 2" }
$MsiLog = Join-Path $LogDir "msi_install.log"

$msiArgs = @(
    "/i", "`"$MsiPath`"",
    "/qn", "/norestart",
    "/l*v", "`"$MsiLog`"",
    "SERVER=$ZabbixServerIp",
    "SERVERACTIVE=$ZabbixServerIp",
    "HOSTNAME=$ZabbixHostname",
    "LISTENPORT=$ZabbixAgentPort",
    "ENABLEPATH=1",
    "INSTALLFOLDER=`"$InstallDir`""
)

$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -NoNewWindow -PassThru
if ($proc.ExitCode -ne 0) {
    Stop-Install "Instalacao do MSI falhou (codigo $($proc.ExitCode)). Consulte: $MsiLog"
}

$AgentExe = Join-Path $InstallDir "zabbix_agent2.exe"
if (-not (Test-Path $AgentExe)) {
    Stop-Install "zabbix_agent2.exe nao encontrado em $InstallDir apos a instalacao."
}

$AgentVersionFull = (& $AgentExe -V 2>&1 | Select-Object -First 1)
Write-OkMsg "Instalado: $AgentVersionFull"
Write-Host ""

# -----------------------------------------------------------------------------
# USER PARAMETER -- windows.top.cpu
# Equivalente ao linux.top.cpu do instalador Linux: retorna JSON com os 5
# processos que mais consomem CPU no momento.
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Configurando user parameter customizado..."

$AgentConfD = Join-Path $InstallDir "zabbix_agent2.d"
New-Item -ItemType Directory -Path $AgentConfD -Force | Out-Null

$TopCpuCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object { [PSCustomObject]@{process=$_.ProcessName; cpu=[math]::Round($_.CPU,2); mem_mb=[math]::Round($_.WorkingSet64/1MB,1)} } | ConvertTo-Json -Compress"'

$UserParamContent = @"
# =============================================================================
# User Parameters -- 2LOCK
# Metricas customizadas coletadas pelo Zabbix Agent 2
# =============================================================================

# --- windows.top.cpu ---
# Retorna JSON com os 5 processos que mais consomem CPU (tempo acumulado)
# Formato: [{"process":"nome","cpu":X.X,"mem_mb":X.X}, ...]
# Uso no Zabbix: Item tipo "Zabbix agent", chave: windows.top.cpu
# Tipo de dado: Text | Intervalo sugerido: 5m
UserParameter=windows.top.cpu,$TopCpuCmd
"@

$UserParamFile = Join-Path $AgentConfD "userparameters_2lock.conf"
Set-Content -Path $UserParamFile -Value $UserParamContent -Encoding UTF8
Write-OkMsg "User parameter criado: $UserParamFile"

Write-InfoMsg "Validando comando do user parameter..."
try {
    $testOutput = Invoke-Expression $TopCpuCmd
    if ($testOutput -match '"process"') {
        Write-OkMsg "Saida do comando validada."
    } else {
        Write-WarnMsg "Comando retornou saida inesperada: '$testOutput'"
    }
} catch {
    Write-WarnMsg "Falha ao validar o comando localmente: $($_.Exception.Message)"
}
Write-Host ""

# -----------------------------------------------------------------------------
# STUBS DE PLUGIN (apenas para os plugins selecionados)
# -----------------------------------------------------------------------------
if ($SelectedPlugins.Count -gt 0) {
    Write-Separator
    Write-InfoMsg "Gerando stubs de configuracao de plugin..."

    foreach ($plugin in $SelectedPlugins) {
        $label = Get-PluginLabel $plugin
        $stubFile = Join-Path $AgentConfD "$plugin.conf"

        if ($plugin -eq "mssql") {
            $stubContent = @"
# =============================================================================
# Plugin MSSQL -- Zabbix Agent 2 -- 2LOCK
# Ver guia completo: windows\plugins\mssql.md
# =============================================================================
# Plugins.MSSQL.Sessions.<nome_sessao>.Uri=sqlserver://127.0.0.1:1433
# Plugins.MSSQL.Sessions.<nome_sessao>.User=<usuario_monitoramento>
# Plugins.MSSQL.Sessions.<nome_sessao>.Password=<senha>
#
# Apos configurar, valide com:
#   zabbix_agent2.exe -t mssql.ping[<nome_sessao>]
# Aplique o template oficial "MSSQL by Zabbix agent 2" no frontend.
"@
        } else {
            $stubContent = @"
# =============================================================================
# Plugin $label -- Zabbix Agent 2 -- 2LOCK
# Stub gerado automaticamente. Nao ha guia especifico deste plugin neste
# repositorio ainda. Consulte a documentacao oficial do Zabbix para a
# sintaxe de Plugins.$($label.ToUpper()).Sessions.<nome>.*
# =============================================================================
"@
        }

        Set-Content -Path $stubFile -Value $stubContent -Encoding UTF8
        Write-OkMsg "Stub gerado: $stubFile"
    }
    Write-Host ""
}

# -----------------------------------------------------------------------------
# CONFIGURACAO DO ZABBIX AGENT 2
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Gerando arquivo de configuracao..."

$AgentConf = Join-Path $InstallDir "zabbix_agent2.conf"
$LogDirAgent = Join-Path $InstallDir "logs"
New-Item -ItemType Directory -Path $LogDirAgent -Force | Out-Null

if (Test-Path $AgentConf) {
    $backupName = "$AgentConf.bkp.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item -Path $AgentConf -Destination $backupName -Force
    Write-InfoMsg "Backup: $backupName"
}

$ConfContent = @"
# =============================================================================
# Zabbix Agent 2 -- 2LOCK
# Gerado automaticamente em: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Versao instalada: $AgentVersionFull
# Host: $ZabbixHostname | Server: $ZabbixServerIp | Porta: $ZabbixAgentPort
# =============================================================================

# --- Servidor Zabbix ---
Server=$ZabbixServerIp
ServerActive=$ZabbixServerIp

# --- Identidade do Host ---
# OBRIGATORIO: deve ser IDENTICO ao nome cadastrado no Zabbix
Hostname=$ZabbixHostname

# --- Porta de escuta ---
ListenPort=$ZabbixAgentPort

# --- Logs ---
LogType=file
LogFile=$LogDirAgent\zabbix_agent2.log
LogFileSize=10
DebugLevel=3

# --- Performance ---
Timeout=10

# --- Includes ---
Include=$AgentConfD\*.conf

# --- Seguranca ---
# PSK desabilitado -- rede interna corporativa
# Para habilitar PSK futuramente:
#   TLSConnect=psk
#   TLSAccept=psk
#   TLSPSKIdentity=<identidade>
#   TLSPSKFile=$InstallDir\zabbix_agent2.psk
"@

Set-Content -Path $AgentConf -Value $ConfContent -Encoding UTF8
Write-OkMsg "Configuracao gerada: $AgentConf"
Write-Host ""

# -----------------------------------------------------------------------------
# VALIDACAO PREVIA DA CONFIGURACAO
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Executando validacao previa da configuracao..."

$pingTest = & $AgentExe -c $AgentConf -t agent.ping 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-ErrMsg "Validacao previa falhou: zabbix_agent2 nao conseguiu carregar a configuracao."
    Write-WarnMsg "Saida detalhada do teste local:"
    Write-Host $pingTest
    Write-WarnMsg "Revise tambem o conteudo de: $AgentConf e $AgentConfD\*.conf"
    Stop-Install "Interrompendo apos falha de validacao."
}
Write-OkMsg "Validacao previa concluida: configuracao carregada com sucesso."
Write-Host ""

# -----------------------------------------------------------------------------
# REGISTRAR / HABILITAR / INICIAR O SERVICO
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Habilitando e iniciando o servico Zabbix Agent 2..."

$svcCheck = Get-Service -Name "Zabbix Agent 2" -ErrorAction SilentlyContinue
if (-not $svcCheck) {
    # O MSI normalmente ja registra o servico; caso nao tenha, registra manualmente.
    & $AgentExe --config $AgentConf --install
    Start-Sleep -Seconds 1
}

Set-Service -Name "Zabbix Agent 2" -StartupType Automatic -ErrorAction SilentlyContinue

try {
    Restart-Service -Name "Zabbix Agent 2" -Force -ErrorAction Stop
} catch {
    Write-ErrMsg "Falha ao iniciar o servico Zabbix Agent 2 apos gerar a configuracao."
    Write-WarnMsg "Detalhe: $($_.Exception.Message)"
    Write-WarnMsg "Verifique o Visualizador de Eventos (Application) e: $LogDirAgent\zabbix_agent2.log"
    Stop-Install "Interrompendo apos falha ao iniciar o servico."
}
Start-Sleep -Seconds 3

$svcStatus = Get-Service -Name "Zabbix Agent 2"
if ($svcStatus.Status -eq "Running") {
    Write-OkMsg "Servico Zabbix Agent 2 esta ATIVO."
} else {
    Write-ErrMsg "Servico Zabbix Agent 2 nao iniciou corretamente (status: $($svcStatus.Status))."
    Write-WarnMsg "Verifique: $LogDirAgent\zabbix_agent2.log"
    Stop-Install "Interrompendo apos falha de inicializacao do servico."
}
Write-Host ""

# -----------------------------------------------------------------------------
# VALIDACAO FINAL
# -----------------------------------------------------------------------------
Write-Separator
Write-InfoMsg "Validando agente instalado..."
Write-Host ""

$PingResult = Invoke-ZbxTest -AgentExe $AgentExe -Conf $AgentConf -Item "agent.ping"
$VerResult  = Invoke-ZbxTest -AgentExe $AgentExe -Conf $AgentConf -Item "agent.version"
$OsResult   = Invoke-ZbxTest -AgentExe $AgentExe -Conf $AgentConf -Item "system.uname"

if ($PingResult -eq "1") {
    Write-OkMsg "agent.ping .................. 1 (OK)"
} else {
    Write-WarnMsg "agent.ping .................. '$PingResult' (esperado: 1, verificar servico)"
}

if ($VerResult -match '^7\.') {
    Write-OkMsg "agent.version ............... $VerResult (OK)"
} else {
    Write-WarnMsg "agent.version ............... '$VerResult' (verificar instalacao)"
}

if ($OsResult) {
    Write-OkMsg "system.uname ................ $OsResult"
} else {
    Write-WarnMsg "system.uname ................ sem retorno (nao critico)"
}

$confHostname = ""
$hostnameMatch = Select-String -Path $AgentConf -Pattern '^Hostname=(.*)$'
if ($hostnameMatch) { $confHostname = $hostnameMatch.Matches[0].Groups[1].Value }
if ($confHostname -eq $ZabbixHostname) {
    Write-OkMsg "Hostname no conf ............ $confHostname (OK)"
} else {
    Write-WarnMsg "Hostname no conf ............ '$confHostname' (esperado: $ZabbixHostname)"
}

$portListening = Test-NetConnection -ComputerName "127.0.0.1" -Port $ZabbixAgentPort -WarningAction SilentlyContinue
if ($portListening.TcpTestSucceeded) {
    Write-OkMsg "Porta $ZabbixAgentPort/TCP .......... ESCUTANDO (OK)"
} else {
    Write-WarnMsg "Porta $ZabbixAgentPort/TCP .......... nao detectada localmente"
}
Write-Host ""

if (-not $FirewallApplied) {
    Write-Separator
    Write-WarnMsg "Porta $ZabbixAgentPort/TCP ainda precisa ser liberada no firewall!"
    Write-WarnMsg "IMPORTANTE: restrinja ao IP do Zabbix Server ($ZabbixServerIp)"
    Write-Host ""
    Write-Host "    New-NetFirewallRule -DisplayName '$FwRuleName' -Direction Inbound ``"
    Write-Host "      -Protocol TCP -LocalPort $ZabbixAgentPort -RemoteAddress $ZabbixServerIp -Action Allow"
    Write-Host ""
}

Write-Separator
Write-Host ""
Write-OkMsg "Instalacao concluida com sucesso!"
Write-Host "  Host     : $ZabbixHostname" -ForegroundColor DarkGray
Write-Host "  Server   : $ZabbixServerIp" -ForegroundColor DarkGray
Write-Host "  Porta    : $ZabbixAgentPort" -ForegroundColor DarkGray
Write-Host "  Versao   : $AgentVersionFull" -ForegroundColor DarkGray
Write-Host "  Plugins  : $(Get-PluginSelectionLabel)" -ForegroundColor DarkGray
Write-Host "  Log      : $LogFile" -ForegroundColor DarkGray
Write-Host ""

Remove-Item -Path $MsiPath -Force -ErrorAction SilentlyContinue
try { Stop-Transcript | Out-Null } catch { }
