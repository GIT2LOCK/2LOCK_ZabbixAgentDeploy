#requires -Version 5.1

# ============================================================
# 2LOCK - Instalador automatico do Zabbix Agent 2
# Windows Server 64 bits | Zabbix 7.0 LTS
# Uso: colar no PowerShell como Administrador e responder as perguntas
# Termo de uso, porta configuravel e suporte completo ao plugin MSSQL
# ============================================================

$ErrorActionPreference = "Stop"

# --- Verificacao de admin (sem fechar o console) ---
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERRO: execute este script em um PowerShell como Administrador." -ForegroundColor Red
    Write-Host "Feche esta janela, abra o PowerShell como admin e cole novamente." -ForegroundColor Yellow
    return
}

$BaseDir  = Join-Path ([string]$env:ProgramData) "2LOCK\ZabbixAgent2"
$MsiPath  = Join-Path $BaseDir "zabbix_agent2.msi"
$MsiLog   = Join-Path $BaseDir "install-msi.log"
$MsiUrl   = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/latest/zabbix_agent2-7.0-latest-windows-amd64-openssl.msi"

function Stop-Installer {
    param([string]$Message)
    Write-Host "`nERRO: $Message" -ForegroundColor Red
    if (Test-Path $MsiLog) {
        Write-Host "Log MSI: $MsiLog" -ForegroundColor Yellow
        $ErrLines = Get-Content $MsiLog -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '(?i)(Return value 3|error \d+:|fatal error|Installation failed)' } |
            Select-Object -Last 5
        if ($ErrLines) {
            Write-Host "Linhas de erro identificadas no log MSI:" -ForegroundColor DarkYellow
            $ErrLines | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
        }
    }
    throw "Instalacao abortada."
}

# ------------------------------------------------------------
# FUNCAO AUXILIAR: Definicao e atualizacao de parametros (.conf)
# Evita parametros duplicados, preserva comentarios e substitui existentes
# ------------------------------------------------------------
function Set-AgentParameter {
    param(
        [System.Collections.Generic.List[string]]$ConfigLines,
        [string]$Name,
        [string]$Value
    )
    $Pattern = '^\s*' + [regex]::Escape($Name) + '\s*='
    $Indexes = @()
    for ($i = 0; $i -lt $ConfigLines.Count; $i++) {
        if ($ConfigLines[$i] -match $Pattern) { $Indexes += $i }
    }
    if ($Indexes.Count -eq 0) {
        [void]$ConfigLines.Add("$Name=$Value")
    } else {
        $ConfigLines[$Indexes[0]] = "$Name=$Value"
        for ($j = 1; $j -lt $Indexes.Count; $j++) {
            $ConfigLines[$Indexes[$j]] =
                "# Duplicata desativada pelo instalador 2LOCK: " + $ConfigLines[$Indexes[$j]]
        }
    }
}

# ------------------------------------------------------------
# PLUGINS OPCIONAIS
# Built-in  = ja compilado no zabbix_agent2.exe, nenhuma instalacao extra.
# Loadable  = exige o pacote separado zabbix_agent2_plugins-<versao>-windows-amd64.msi.
# MSSQL     = plugin loadable com configuracao interativa completa.
# ------------------------------------------------------------
$PluginKeys         = @("mysql", "postgresql", "mongodb", "memcached", "mssql")
$BuiltinPluginKeys  = @("mysql", "memcached")
$LoadablePluginKeys = @("postgresql", "mongodb", "mssql")
$SelectedPlugins    = @()

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

function Get-PluginKind {
    param([string]$Key)
    if ($BuiltinPluginKeys -contains $Key)  { return "builtin" }
    if ($LoadablePluginKeys -contains $Key) { return "loadable" }
    return "desconhecido"
}

function Get-PluginKeyFromToken {
    param([string]$Token)
    $t = $Token.ToLowerInvariant()
    if (@("1","mysql") -contains $t)                 { return "mysql" }
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
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $true }

    $tokens = $Raw -split '[,;\s]+' | Where-Object { $_ -ne "" }
    foreach ($token in $tokens) {
        $tl = $token.ToLowerInvariant()
        if (@("0","none","nenhum","nenhuma","base") -contains $tl) { $script:SelectedPlugins = @(); return $true }
        if (@("6","all","todos","todas","*") -contains $tl) { $script:SelectedPlugins = $PluginKeys.Clone(); return $true }

        $key = Get-PluginKeyFromToken $tl
        if (-not $key) {
            Write-Host "Opcao invalida '$token'. Use numeros 1-6, 0, ou nomes como mysql,mssql." -ForegroundColor Yellow
            $script:SelectedPlugins = @()
            return $false
        }
        if ($script:SelectedPlugins -notcontains $key) { $script:SelectedPlugins += $key }
    }
    return $true
}

function Show-PluginPrompt {
    Write-Host "  Plugins opcionais do Zabbix Agent 2" -ForegroundColor White
    Write-Host "  MySQL e Memcached ja vem compilados no zabbix_agent2.exe (built-in)." -ForegroundColor DarkGray
    Write-Host "  PostgreSQL, MongoDB e MSSQL sao plugins 'loadable': este script baixa" -ForegroundColor DarkGray
    Write-Host "  e instala automaticamente o pacote zabbix_agent2_plugins se algum" -ForegroundColor DarkGray
    Write-Host "  deles for selecionado. O plugin MSSQL e configurado interativamente." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Selecione os plugins a configurar (Enter = nenhum):"
    Write-Host ""
    Write-Host "  [1] MySQL       (built-in)"
    Write-Host "  [2] PostgreSQL  (loadable, instala pacote extra)"
    Write-Host "  [3] MongoDB     (loadable, instala pacote extra)"
    Write-Host "  [4] Memcached   (built-in)"
    Write-Host "  [5] MSSQL       (loadable, configuracao completa do SQL Server)"
    Write-Host "  [6] Todos"
    Write-Host "  [0] Nenhum"
    Write-Host ""
    do {
        $raw = (Read-Host "  Opcoes (ex: 5 para MSSQL, ou 0 para nenhum)").Trim()
        $ok  = Resolve-PluginSelection $raw
    } while (-not $ok)

    # Caso o usuario pressione Enter direto, oferece de forma transparente a opcao do MSSQL
    if ($SelectedPlugins.Count -eq 0 -and $raw -eq "") {
        Write-Host ""
        $optMssql = (Read-Host "  Deseja configurar o plugin Microsoft SQL Server (MSSQL)? [s/N]").Trim()
        if ($optMssql -match '^[sS]$') {
            $script:SelectedPlugins = @("mssql")
        }
    }

    Write-Host "Plugins selecionados: $(Get-PluginSelectionLabel)." -ForegroundColor Green
}

Write-Host "=============================================="
Write-Host "  2LOCK - Zabbix Agent 2 para Windows Server"
Write-Host "==============================================`n"

# 0. Termo de uso - aceite obrigatorio
Write-Host "  TERMO DE USO -- LEIA ANTES DE CONTINUAR" -ForegroundColor White
Write-Host "----------------------------------------------"
Write-Host ""
Write-Host "  Este instalador e de uso exclusivo da 2LOCK e foi desenvolvido" -ForegroundColor DarkGray
Write-Host "  para automatizar a implantacao do Zabbix Agent 2." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  >> Este script realizara alteracoes no sistema operacional,"
Write-Host "     incluindo download e instalacao de software (CDN oficial da"
Write-Host "     Zabbix), arquivos de configuracao e regra de firewall."
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
Write-Host "----------------------------------------------"
Write-Host ""

$AcceptTerms = (Read-Host "Li e aceito os termos acima [s/N]").Trim()
if ($AcceptTerms -notmatch '^[sS]$') {
    Write-Host "Instalacao cancelada. Termo de uso nao aceito." -ForegroundColor Yellow
    return
}
Write-Host ""

# 1. Nome do host
do {
    $ZabbixHostname = (Read-Host "Nome exato do host cadastrado no Zabbix").Trim()

    if ([string]::IsNullOrWhiteSpace($ZabbixHostname)) {
        Write-Host "O nome do host nao pode ficar vazio." -ForegroundColor Yellow
        continue
    }

    if ($ZabbixHostname -notmatch '^[a-zA-Z0-9_.-]+$') {
        Write-Host "Nome invalido. Use apenas letras, numeros, ponto, hifen ou underscore (sem espacos)." -ForegroundColor Yellow
        $ZabbixHostname = ""
    }
} while ([string]::IsNullOrWhiteSpace($ZabbixHostname))

# 2. IP do Zabbix Server
do {
    $ZabbixServer = (Read-Host "IP IPv4 do servidor ou proxy Zabbix").Trim()
    $ParsedIP = $null

    $ValidIP = [System.Net.IPAddress]::TryParse($ZabbixServer, [ref]$ParsedIP)

    if (-not $ValidIP -or
        $ParsedIP.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        Write-Host "IP IPv4 invalido. Exemplo: 172.16.4.113" -ForegroundColor Yellow
        $ZabbixServer = ""
    }
} while ([string]::IsNullOrWhiteSpace($ZabbixServer))

# 2b. Porta do agente (default 10050; a porta 10051 do Server NAO muda)
Write-Host "`nPorta padrao do Zabbix: 10050" -ForegroundColor DarkGray
do {
    $InputPort = (Read-Host "Porta do agente [Enter = 10050]").Trim()
    $ZabbixAgentPort = if ($InputPort) { $InputPort } else { "10050" }

    $PortValid = ($ZabbixAgentPort -match '^\d{1,5}$') -and
                 ([int64]$ZabbixAgentPort -ge 1024) -and
                 ([int64]$ZabbixAgentPort -le 65535)

    if (-not $PortValid) {
        Write-Host "Porta invalida. Informe um numero inteiro entre 1024 e 65535." -ForegroundColor Yellow
    }
} while (-not $PortValid)
$ZabbixAgentPort = [string][int]$ZabbixAgentPort   # normaliza (ex: 010050 -> 10050)

# Portas de comunicacao do Zabbix a serem liberadas no firewall (10050 e 10051)
$FwInboundPorts = @($ZabbixAgentPort, "10050", "10051") | Select-Object -Unique

# 2c. Selecao de plugins opcionais
Write-Host ""
Show-PluginPrompt

# 2d. Configuracao interativa do Microsoft SQL Server (MSSQL)
$SqlPort                   = "1433"
$SqlAddress                = "localhost"
$SqlPassword               = ""
$SqlDatabase               = "master"
$SqlEncrypt                = "true"
$SqlTrustServerCertificate = "false"
$SqlTimeout                = "10"
$SqlUri                    = ""
$SqlUser                   = "zbx_monitor"  # Fixo, sem possibilidade de alteracao

if ($SelectedPlugins -contains "mssql") {
    Write-Host "`n----------------------------------------------"
    Write-Host "  Configuracao do Microsoft SQL Server (MSSQL)" -ForegroundColor White
    Write-Host "----------------------------------------------"
    Write-Host "  Usuario do SQL Server: zbx_monitor (fixo, nao editavel)" -ForegroundColor DarkGray
    Write-Host ""

    # 1. Porta do SQL Server (padrao 1433)
    do {
        $RawSqlPort = (Read-Host "  Porta do SQL Server [Enter = 1433]").Trim()
        $SqlPort = if ($RawSqlPort) { $RawSqlPort } else { "1433" }
        $SqlPortValid = ($SqlPort -match '^\d{1,5}$') -and ([int64]$SqlPort -ge 1) -and ([int64]$SqlPort -le 65535)
        if (-not $SqlPortValid) {
            Write-Host "  Porta invalida. Informe um numero inteiro entre 1 e 65535." -ForegroundColor Yellow
        }
    } while (-not $SqlPortValid)
    $SqlPort = [string][int]$SqlPort

    # 2. Endereco/instancia do SQL Server (padrao localhost)
    $RawSqlAddress = (Read-Host "  Endereco/instancia do SQL Server [Enter = localhost]").Trim()
    $SqlAddress = if ($RawSqlAddress) { $RawSqlAddress } else { "localhost" }

    # 3. Senha do usuario SQL (zbx_monitor - entrada segura)
    do {
        $SqlPasswordSecure = Read-Host "  Senha do usuario SQL (zbx_monitor)" -AsSecureString
        $SqlPassword = [System.Net.NetworkCredential]::new("", $SqlPasswordSecure).Password
        if ([string]::IsNullOrEmpty($SqlPassword)) {
            Write-Host "  A senha do usuario SQL nao pode ficar vazia." -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrEmpty($SqlPassword))

    # 4. Banco de dados (padrao master)
    $RawSqlDb = (Read-Host "  Banco de dados [Enter = master]").Trim()
    $SqlDatabase = if ($RawSqlDb) { $RawSqlDb } else { "master" }

    # 5. Criptografia (Encrypt, padrao true)
    do {
        $RawSqlEncrypt = (Read-Host "  Criptografia (Encrypt: true/false/strict/disable) [Enter = true]").Trim().ToLowerInvariant()
        $SqlEncrypt = if ($RawSqlEncrypt) { $RawSqlEncrypt } else { "true" }
        if ($SqlEncrypt -in @("s", "sim", "y", "yes", "true", "t")) { $SqlEncrypt = "true" }
        elseif ($SqlEncrypt -in @("n", "nao", "não", "no", "false", "f")) { $SqlEncrypt = "false" }

        $EncryptValid = $SqlEncrypt -in @("true", "false", "strict", "disable")
        if (-not $EncryptValid) {
            Write-Host "  Opcao invalida. Use true, false, strict ou disable." -ForegroundColor Yellow
        }
    } while (-not $EncryptValid)

    # 6. Validacao do certificado (TrustServerCertificate, padrao false)
    do {
        $RawSqlTrust = (Read-Host "  Validar certificado (TrustServerCertificate: true/false) [Enter = false]").Trim().ToLowerInvariant()
        $SqlTrustServerCertificate = if ($RawSqlTrust) { $RawSqlTrust } else { "false" }
        if ($SqlTrustServerCertificate -in @("s", "sim", "y", "yes", "true", "t")) { $SqlTrustServerCertificate = "true" }
        elseif ($SqlTrustServerCertificate -in @("n", "nao", "não", "no", "false", "f")) { $SqlTrustServerCertificate = "false" }

        $TrustValid = $SqlTrustServerCertificate -in @("true", "false")
        if (-not $TrustValid) {
            Write-Host "  Opcao invalida. Use true ou false." -ForegroundColor Yellow
        }
    } while (-not $TrustValid)

    # 7. Timeout (padrao 10)
    do {
        $RawSqlTimeout = (Read-Host "  Timeout do plugin MSSQL em segundos (1-30) [Enter = 10]").Trim()
        $SqlTimeout = if ($RawSqlTimeout) { $RawSqlTimeout } else { "10" }
        $SqlTimeoutValid = ($SqlTimeout -match '^\d{1,2}$') -and ([int]$SqlTimeout -ge 1) -and ([int]$SqlTimeout -le 30)
        if (-not $SqlTimeoutValid) {
            Write-Host "  Timeout invalido. Informe um numero inteiro entre 1 e 30." -ForegroundColor Yellow
        }
    } while (-not $SqlTimeoutValid)
    $SqlTimeout = [string][int]$SqlTimeout

    # Normalizacao e composicao do URI (schema sqlserver://)
    $CleanAddress = $SqlAddress.Trim()
    if ($CleanAddress -match '^sqlserver://(.*)$') {
        $CleanAddress = $Matches[1]
    }
    $CleanAddress = $CleanAddress -replace '\\', '/'

    if ($CleanAddress -match ':\d+$') {
        $SqlUri = "sqlserver://$CleanAddress"
    } else {
        $SqlUri = "sqlserver://${CleanAddress}:${SqlPort}"
    }
}

Write-Host "`nResumo:"
Write-Host "  Host Zabbix   : $ZabbixHostname"
Write-Host "  Servidor      : $ZabbixServer"
Write-Host "  Porta ativa   : TCP 10051"
Write-Host "  Porta passiva : TCP $ZabbixAgentPort"
Write-Host "  Plugins       : $(Get-PluginSelectionLabel)"
if ($SelectedPlugins -contains "mssql") {
    Write-Host "  SQL Server    : $SqlAddress"
    Write-Host "  Porta SQL     : $SqlPort"
    Write-Host "  Usuario SQL   : zbx_monitor (fixo)"
    Write-Host "  Banco SQL     : $SqlDatabase"
    Write-Host "  Encrypt       : $SqlEncrypt"
    Write-Host "  TrustCert     : $SqlTrustServerCertificate"
    Write-Host "  Timeout SQL   : ${SqlTimeout}s"
}
Write-Host ""

# 3. Teste de conectividade com o Zabbix Server (TCP 10051, timeout curto)
Write-Host "Testando conectividade com $ZabbixServer na porta 10051..." -ForegroundColor Cyan

$tcp = New-Object System.Net.Sockets.TcpClient
try {
    $iar = $tcp.BeginConnect($ZabbixServer, 10051, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne(3000)) {
        throw "Timeout"
    }
    $tcp.EndConnect($iar)
    Write-Host "Conectividade OK." -ForegroundColor Green
} catch {
    Write-Host "ATENCAO: nao foi possivel conectar em $ZabbixServer:10051." -ForegroundColor Yellow
    $resp = Read-Host "Deseja continuar mesmo assim? (s/N)"
    if ($resp -notmatch '^[sS]$') {
        Stop-Installer "Instalacao cancelada pelo usuario. Verifique o IP do Zabbix Server."
    }
} finally {
    $tcp.Close()
}

# 4. Diretorio de trabalho
try {
    New-Item -Path $BaseDir -ItemType Directory -Force | Out-Null
} catch {
    Stop-Installer "Nao foi possivel criar o diretorio de trabalho: $($_.Exception.Message)"
}

# 5. Download do MSI do Zabbix Agent 2
try {
    Write-Host "[1/6] Baixando o Zabbix Agent 2..." -ForegroundColor Cyan

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing

    if (-not (Test-Path $MsiPath) -or (Get-Item $MsiPath).Length -lt 1MB) {
        Stop-Installer "O instalador baixado esta ausente ou incompleto."
    }

    $Signature = Get-AuthenticodeSignature -FilePath $MsiPath
    if ($Signature.Status -ne "Valid") {
        Stop-Installer "Assinatura digital do MSI invalida (Status: $($Signature.Status)). Instalacao cancelada."
    }

    Write-Host "Download e assinatura digital validados." -ForegroundColor Green
} catch {
    Stop-Installer "Falha ao baixar ou validar o MSI: $($_.Exception.Message)"
}

# 6. Instalacao silenciosa do agente base
try {
    Write-Host "[2/6] Instalando o agente base..." -ForegroundColor Cyan

    # Verifica se o produto ja esta registrado no Windows Installer
    $ExistingApp = Get-ItemProperty -Path @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    ) -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '(?i)Zabbix Agent 2' } | Select-Object -First 1

    $ReinstallParams = ""
    if ($ExistingApp) {
        Write-Host "Instalacao anterior do Zabbix Agent 2 detectada ($($ExistingApp.DisplayVersion)). Forcando reinstalacao/reparo..." -ForegroundColor Cyan
        $ReinstallParams = "REINSTALL=ALL REINSTALLMODE=amus "
    }

    $InstallArgs = "/i `"$MsiPath`" /qn /norestart /l*v `"$MsiLog`" " +
                   $ReinstallParams +
                   "SERVER=$ZabbixServer SERVERACTIVE=$ZabbixServer " +
                   "HOSTNAME=`"$ZabbixHostname`" LISTENPORT=$ZabbixAgentPort " +
                   "STARTUPTYPE=automatic SKIP=fw ENABLEPATH=1"

    $Process = Start-Process -FilePath "msiexec.exe" `
        -ArgumentList $InstallArgs -Wait -PassThru

    if ($Process.ExitCode -notin @(0, 3010)) {
        Stop-Installer "O MSI terminou com codigo $($Process.ExitCode). Consulte o log."
    }

    if ($Process.ExitCode -eq 3010) {
        Write-Host "O MSI indicou que pode ser necessario reiniciar o Windows." -ForegroundColor Yellow
    }
} catch {
    Stop-Installer "Falha durante a instalacao: $($_.Exception.Message)"
}

# 6b. Localizar o servico e a pasta de instalacao do agente
Write-Host "[3/6] Localizando o servico e caminhos do agente..." -ForegroundColor Cyan

$Service = $null
# Aguarda o servico estar disponivel no SCM / WMI (retry loop de ate 10s)
for ($retry = 0; $retry -lt 10; $retry++) {
    $Service = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -match '(?i)zabbix_agent2\.exe' } |
        Select-Object -First 1

    if (-not $Service) {
        $SvcByName = Get-Service -Name "Zabbix Agent 2", "*zabbix*agent*2*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($SvcByName) {
            $Service = Get-CimInstance Win32_Service -Filter "Name = '$($SvcByName.Name)'" -ErrorAction SilentlyContinue
        }
    }

    if ($Service) { break }
    Start-Sleep -Seconds 1
}

# Auto-recuperacao: se o binario existe no disco mas o servico nao foi registrado
if (-not $Service) {
    $CandidateExes = @(
        "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe",
        "C:\Program Files (x86)\Zabbix Agent 2\zabbix_agent2.exe"
    )
    $FoundExe = $null
    foreach ($cExe in $CandidateExes) {
        if (Test-Path $cExe) { $FoundExe = $cExe; break }
    }

    if ($FoundExe) {
        Write-Host "Binario do agente localizado em '$FoundExe', mas o servico Windows nao estava registrado." -ForegroundColor Yellow
        Write-Host "Registrando o servico do Zabbix Agent 2 nativamente..." -ForegroundColor Cyan
        $TempInstallDir = [string](Split-Path $FoundExe)
        $TempConfPath   = Join-Path $TempInstallDir "zabbix_agent2.conf"
        if (-not (Test-Path $TempConfPath)) {
            $BasicConf = "Server=$ZabbixServer`nServerActive=$ZabbixServer`nHostname=$ZabbixHostname`nListenPort=$ZabbixAgentPort`n"
            [System.IO.File]::WriteAllText($TempConfPath, $BasicConf, (New-Object System.Text.UTF8Encoding($false)))
        }

        & $FoundExe --config "$TempConfPath" --install | Out-Null
        Start-Sleep -Seconds 2

        $Service = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
            Where-Object { $_.PathName -match '(?i)zabbix_agent2\.exe' } |
            Select-Object -First 1
        if (-not $Service) {
            $SvcByName = Get-Service -Name "Zabbix Agent 2", "*zabbix*agent*2*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($SvcByName) {
                $Service = Get-CimInstance Win32_Service -Filter "Name = '$($SvcByName.Name)'" -ErrorAction SilentlyContinue
            }
        }
    }
}

# Se ainda assim nao encontrou e nao tinha tentado reinstalar, tenta reparo forcado do MSI
if (-not $Service -and -not $ExistingApp) {
    Write-Host "Servico nao encontrado. Tentando reparo forcado do pacote MSI..." -ForegroundColor Yellow
    $RepairArgs = "/fa `"$MsiPath`" /qn /norestart /l*v `"$MsiLog`" " +
                  "SERVER=$ZabbixServer SERVERACTIVE=$ZabbixServer " +
                  "HOSTNAME=`"$ZabbixHostname`" LISTENPORT=$ZabbixAgentPort " +
                  "STARTUPTYPE=automatic SKIP=fw ENABLEPATH=1"
    $RepairProc = Start-Process -FilePath "msiexec.exe" -ArgumentList $RepairArgs -Wait -PassThru
    Start-Sleep -Seconds 2

    $Service = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.PathName -match '(?i)zabbix_agent2\.exe' } |
        Select-Object -First 1
}

if (-not $Service) {
    Stop-Installer "O servico do Zabbix Agent 2 nao foi encontrado apos a instalacao."
}

$AgentExe = $null
if ($Service.PathName) {
    $ExeMatch = [regex]::Match($Service.PathName, '(?i)"?([^"]*zabbix_agent2\.exe)"?')
    if ($ExeMatch.Success) {
        $AgentExe = $ExeMatch.Groups[1].Value
    }
}
if (-not $AgentExe) {
    $DefaultExe = "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe"
    if (Test-Path $DefaultExe) {
        $AgentExe = $DefaultExe
    } else {
        Stop-Installer "Nao foi possivel determinar a pasta de instalacao do agente."
    }
}
$InstallDir = [string](Split-Path $AgentExe)

if ($Service.PathName -match '(?i)(?:--config|-c)\s+"([^"]+\.conf)"') {
    $ConfigPath = $Matches[1]
} elseif ($Service.PathName -match '(?i)(?:--config|-c)\s+(\S+\.conf)') {
    $ConfigPath = $Matches[1]
} else {
    $ConfigPath = Join-Path $InstallDir "zabbix_agent2.conf"
}

if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
    $DefaultConfPath = Join-Path $InstallDir "zabbix_agent2.conf"
    if (Test-Path $DefaultConfPath) {
        $ConfigPath = $DefaultConfPath
    } else {
        $BasicConf = "Server=$ZabbixServer`nServerActive=$ZabbixServer`nHostname=$ZabbixHostname`nListenPort=$ZabbixAgentPort`n"
        [System.IO.File]::WriteAllText($DefaultConfPath, $BasicConf, (New-Object System.Text.UTF8Encoding($false)))
        $ConfigPath = $DefaultConfPath
    }
}
Write-Host "Agente: $AgentExe" -ForegroundColor DarkGray
Write-Host "Config: $ConfigPath" -ForegroundColor DarkGray

# 6c. Pacote de plugins LOADABLE (PostgreSQL / MongoDB / MSSQL)
$PluginsInstalled = $false
$PluginsMsiLog    = Join-Path $BaseDir "msi_plugins_install.log"
$LoadableSelected = @($SelectedPlugins | Where-Object { $LoadablePluginKeys -contains $_ })

if ($LoadableSelected.Count -gt 0) {
    $LoadableLabels = ($LoadableSelected | ForEach-Object { Get-PluginLabel $_ }) -join ", "
    Write-Host "[3b/6] Instalando pacote de plugins ($LoadableLabels)..." -ForegroundColor Cyan

    $AgentVersionNum = $null
    try {
        $VerLine = (& $AgentExe -V 2>&1 | Select-Object -First 1)
        if ("$VerLine" -match '(\d+\.\d+\.\d+)') { $AgentVersionNum = $Matches[1] }
    } catch { }

    if ($AgentVersionNum) {
        $PluginsFolder  = $AgentVersionNum
        $PluginsVersion = $AgentVersionNum
    } else {
        $PluginsFolder  = "latest"
        $PluginsVersion = "7.0-latest"
    }

    $PluginsMsiName = "zabbix_agent2_plugins-$PluginsVersion-windows-amd64.msi"
    $PluginsMsiUrl  = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/$PluginsFolder/$PluginsMsiName"
    $PluginsMsiPath = Join-Path $env:TEMP $PluginsMsiName

    $PluginsDownloaded = $false
    try {
        Invoke-WebRequest -Uri $PluginsMsiUrl -OutFile $PluginsMsiPath -UseBasicParsing
        if ((Test-Path $PluginsMsiPath) -and (Get-Item $PluginsMsiPath).Length -gt 100KB) {
            $PluginsDownloaded = $true
        }
    } catch {
        Write-Host "Falha ao baixar pacote pela versao detectada ($PluginsMsiUrl): $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Fallback para latest se necessario
    if (-not $PluginsDownloaded -and $PluginsFolder -ne "latest") {
        try {
            $FallbackUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/latest/zabbix_agent2_plugins-7.0-latest-windows-amd64.msi"
            Write-Host "Tentando download de fallback ($FallbackUrl)..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $FallbackUrl -OutFile $PluginsMsiPath -UseBasicParsing
            if ((Test-Path $PluginsMsiPath) -and (Get-Item $PluginsMsiPath).Length -gt 100KB) {
                $PluginsDownloaded = $true
            }
        } catch {
            Write-Host "Falha no download de fallback: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if (-not $PluginsDownloaded) {
        Write-Host "O agente base ja esta instalado e funcional." -ForegroundColor Yellow
        Write-Host "Os plugins ($LoadableLabels) precisarao ser instalados manualmente depois." -ForegroundColor Yellow
    } else {
        try {
            $PluginsArgs = "/i `"$PluginsMsiPath`" /qn /norestart /l*v `"$PluginsMsiLog`" " +
                           "INSTALLFOLDER=`"$InstallDir`""
            $PluginsProc = Start-Process -FilePath "msiexec.exe" `
                -ArgumentList $PluginsArgs -Wait -PassThru

            if ($PluginsProc.ExitCode -in @(0, 3010)) {
                $PluginsInstalled = $true
                Write-Host "Pacote de plugins instalado com sucesso. Log: $PluginsMsiLog" -ForegroundColor Green
            } else {
                Write-Host "O MSI de plugins terminou com codigo $($PluginsProc.ExitCode). Consulte: $PluginsMsiLog" -ForegroundColor Yellow
                Write-Host "O agente base continua instalado e funcional." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Falha ao instalar o pacote de plugins: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "O agente base continua instalado e funcional." -ForegroundColor Yellow
        }
    }

    Remove-Item -Path $PluginsMsiPath -Force -ErrorAction SilentlyContinue
}

# Verificacao de compatibilidade e binario do MSSQL
$MssqlPluginExe = $null
if ($SelectedPlugins -contains "mssql") {
    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Host "AVISO DE COMPATIBILIDADE: Sistema operacional nao e 64 bits. O plugin MSSQL exige x64." -ForegroundColor Yellow
    }

    $MssqlBinaryCandidates = @(
        (Join-Path $InstallDir "zabbix-agent2-plugin-mssql.exe"),
        (Join-Path $InstallDir "plugins\zabbix-agent2-plugin-mssql.exe"),
        (Join-Path $InstallDir "zabbix_agent2.d\plugins.d\zabbix-agent2-plugin-mssql.exe")
    )
    foreach ($cand in $MssqlBinaryCandidates) {
        if (Test-Path $cand) {
            $MssqlPluginExe = $cand
            break
        }
    }

    if ($MssqlPluginExe) {
        Write-Host "Plugin MSSQL compativel: binario localizado em '$MssqlPluginExe'." -ForegroundColor Green
    } else {
        $MssqlPluginExe = Join-Path $InstallDir "zabbix-agent2-plugin-mssql.exe"
        Write-Host "AVISO: Executavel zabbix-agent2-plugin-mssql.exe nao detectado de imediato. Configurando caminho padrao: $MssqlPluginExe" -ForegroundColor Yellow
    }
}

# 6d. Configuracao dos plugins (MSSQL automatica e stubs para os demais)
$MssqlConfPath = $null
if ($SelectedPlugins.Count -gt 0) {
    Write-Host "[3c/6] Gerando configuracoes dos plugins..." -ForegroundColor Cyan

    $AgentConfD   = Join-Path $InstallDir "zabbix_agent2.d"
    $PluginsConfD = Join-Path $AgentConfD "plugins.d"
    New-Item -Path $AgentConfD -ItemType Directory -Force | Out-Null
    New-Item -Path $PluginsConfD -ItemType Directory -Force | Out-Null

    $ConfEncoding = New-Object System.Text.UTF8Encoding($false)

    # 1. Configuracao completa do plugin MSSQL
    if ($SelectedPlugins -contains "mssql") {
        # Localiza o arquivo correto do plugin: o MSI instala em zabbix_agent2.d\mssql.conf (CONFIGFOLDER)
        if (Test-Path (Join-Path $AgentConfD "mssql.conf")) {
            $MssqlConfPath = Join-Path $AgentConfD "mssql.conf"
        } elseif (Test-Path (Join-Path $PluginsConfD "mssql.conf")) {
            $MssqlConfPath = Join-Path $AgentConfD "mssql.conf"
        } else {
            $MssqlConfPath = Join-Path $AgentConfD "mssql.conf"
        }

        Write-Host "Configurando parametros do MSSQL em '$MssqlConfPath'..." -ForegroundColor Cyan

        try {
            $MssqlLines = [System.Collections.Generic.List[string]]::new()
            if (Test-Path $MssqlConfPath) {
                $MssqlBak = "$MssqlConfPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -Path $MssqlConfPath -Destination $MssqlBak -Force
                [System.IO.File]::ReadAllLines($MssqlConfPath) | ForEach-Object { [void]$MssqlLines.Add($_) }
            } else {
                [void]$MssqlLines.Add("### Configuracao do Plugin MSSQL - Zabbix Agent 2 (2LOCK)")
                [void]$MssqlLines.Add("")
            }

            # Caminho do plugin e timeout
            if ($MssqlPluginExe) {
                Set-AgentParameter $MssqlLines "Plugins.MSSQL.System.Path" $MssqlPluginExe
            }
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Timeout"                $SqlTimeout

            # Parametros padrao (Default.*)
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Default.Uri"            $SqlUri
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Default.User"           $SqlUser
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Default.Password"       $SqlPassword
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Default.Database"       $SqlDatabase
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Default.Encrypt"        $SqlEncrypt
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Default.TrustServerCertificate" $SqlTrustServerCertificate

            # Parametros de sessao nomeada MSSQL (compatibilidade com templates que usam nome de sessao)
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Sessions.MSSQL.Uri"     $SqlUri
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Sessions.MSSQL.User"    $SqlUser
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Sessions.MSSQL.Password" $SqlPassword
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Sessions.MSSQL.Database" $SqlDatabase
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Sessions.MSSQL.Encrypt" $SqlEncrypt
            Set-AgentParameter $MssqlLines "Plugins.MSSQL.Sessions.MSSQL.TrustServerCertificate" $SqlTrustServerCertificate

            [System.IO.File]::WriteAllLines($MssqlConfPath, [string[]]$MssqlLines.ToArray(), $ConfEncoding)

            # Validacao pos-escrita (garante que nao ha BOM)
            $mBytes = [System.IO.File]::ReadAllBytes($MssqlConfPath)
            if ($mBytes.Length -ge 3 -and $mBytes[0] -eq 0xEF -and $mBytes[1] -eq 0xBB -and $mBytes[2] -eq 0xBF) {
                Stop-Installer "O arquivo $MssqlConfPath foi gravado com BOM. Abortando para evitar falha no servico."
            }

            Write-Host "Parametros do MSSQL configurados com sucesso (sem BOM)." -ForegroundColor Green

            # Remove stub legado se existir para evitar confusao ou instrucoes obsoletas
            $LegacyStub = Join-Path $AgentConfD "2lock_mssql.conf"
            if (Test-Path (Join-Path $PluginsConfD "mssql.conf")) {
                Remove-Item -Path (Join-Path $PluginsConfD "mssql.conf") -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $LegacyStub) {
                Remove-Item -Path $LegacyStub -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Host "Falha ao gravar configuracao do MSSQL: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # 2. Stubs dos demais plugins selecionados (apenas informativos)
    $OtherPlugins = @($SelectedPlugins | Where-Object { $_ -ne "mssql" })
    $PkgLine = if ($PluginsInstalled) {
        "O pacote zabbix_agent2_plugins ja foi instalado por este script"
    } else {
        "ATENCAO: o pacote zabbix_agent2_plugins NAO foi instalado por este script (instale manualmente)"
    }

    foreach ($plugin in $OtherPlugins) {
        $label    = Get-PluginLabel $plugin
        $kind     = Get-PluginKind $plugin
        $stubFile = Join-Path $AgentConfD "2lock_$plugin.conf"

        if ($kind -eq "loadable") {
            $stubContent = @"
# =============================================================================
# Plugin $label (loadable) -- Zabbix Agent 2 -- 2LOCK
# $PkgLine
# e ele deve ter gerado seu proprio arquivo .conf em $PluginsConfD, com o caminho
# do binario (Plugins.$($label).System.Path) ja preenchido. Este arquivo e so um
# lembrete das credenciais de sessao, ainda pendentes de preenchimento la.
# Consulte a documentacao oficial do Zabbix para a sintaxe de
# Plugins.$($label.ToUpper()).Sessions.<nome>.*
# =============================================================================
"@
            Write-Host "  ${label}: o pacote de plugins gera a configuracao em plugins.d." -ForegroundColor DarkGray
        } else {
            $stubContent = @"
# =============================================================================
# Plugin $label (built-in) -- Zabbix Agent 2 -- 2LOCK
# Ja vem compilado no zabbix_agent2.exe, nenhuma instalacao adicional foi
# necessaria. Configure a sessao abaixo:
# =============================================================================
# Plugins.$label.Sessions.<nome_sessao>.Uri=tcp://127.0.0.1:<porta>
# Plugins.$label.Sessions.<nome_sessao>.User=<usuario_monitoramento>
# Plugins.$label.Sessions.<nome_sessao>.Password=<senha>
"@
            Write-Host "  ${label}: built-in, ja vem no zabbix_agent2.exe." -ForegroundColor DarkGray
        }

        try {
            [System.IO.File]::WriteAllText($stubFile, $stubContent, $ConfEncoding)
            Write-Host "Stub gerado: $stubFile" -ForegroundColor Green
        } catch {
            Write-Host "Nao foi possivel gerar o stub de ${label}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# 8. Ajustar arquivo principal de configuracao (zabbix_agent2.conf)
Write-Host "[4/6] Configurando o agente base..." -ForegroundColor Cyan

try {
    $BackupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -Path $ConfigPath -Destination $BackupPath -Force

    $Lines = [System.Collections.Generic.List[string]]::new()
    [System.IO.File]::ReadAllLines($ConfigPath) | ForEach-Object { [void]$Lines.Add($_) }

    Set-AgentParameter $Lines "Server"       $ZabbixServer
    Set-AgentParameter $Lines "ServerActive" $ZabbixServer
    Set-AgentParameter $Lines "Hostname"     $ZabbixHostname
    Set-AgentParameter $Lines "ListenPort"   $ZabbixAgentPort
    Set-AgentParameter $Lines "Timeout"      "10"

    # Garante inclusao dos diretorios de plugins em zabbix_agent2.conf
    if ($SelectedPlugins.Count -gt 0) {
        $HasIncludePluginD = $false
        $HasIncludeConfD   = $false
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ($Lines[$i] -match '^\s*Include\s*=.*plugins\.d') { $HasIncludePluginD = $true }
            if ($Lines[$i] -match '^\s*Include\s*=.*zabbix_agent2\.d[\\/]\*\.conf') { $HasIncludeConfD = $true }
        }

        if (-not $HasIncludePluginD) {
            $UncommentedP = $false
            for ($i = 0; $i -lt $Lines.Count; $i++) {
                if ($Lines[$i] -match '^\s*#\s*(Include\s*=.*plugins\.d[\\/]\*\.conf)') {
                    $Lines[$i] = $Matches[1]
                    $UncommentedP = $true
                    break
                }
            }
            if (-not $UncommentedP) {
                [void]$Lines.Add("Include=.\zabbix_agent2.d\plugins.d\*.conf")
            }
        }

        if (-not $HasIncludeConfD) {
            $UncommentedC = $false
            for ($i = 0; $i -lt $Lines.Count; $i++) {
                if ($Lines[$i] -match '^\s*#\s*(Include\s*=.*zabbix_agent2\.d[\\/]\*\.conf)') {
                    $Lines[$i] = $Matches[1]
                    $UncommentedC = $true
                    break
                }
            }
            if (-not $UncommentedC) {
                [void]$Lines.Add("Include=.\zabbix_agent2.d\*.conf")
            }
        }
    }

    # Grava SEM BOM (obrigatorio: o agente rejeita BOM no conf)
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($ConfigPath, [string[]]$Lines.ToArray(), $Utf8NoBom)

    # Validacao pos-escrita: garante que nao ha BOM
    $bytes = [System.IO.File]::ReadAllBytes($ConfigPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Stop-Installer "O arquivo de configuracao foi gravado com BOM. Abortando para evitar falha no servico."
    }

    Write-Host "Configuracao salva (sem BOM). Backup: $BackupPath" -ForegroundColor Green
} catch {
    Stop-Installer "Falha ao alterar a configuracao: $($_.Exception.Message)"
}

# 9. Firewall (Liberacao das portas 10050 e 10051)
Write-Host "[5/6] Configurando o firewall (portas 10050 e 10051)..." -ForegroundColor Cyan

try {
    # Remove regras anteriores da 2LOCK para evitar duplicatas ou conflitos
    Get-NetFirewallRule -DisplayName "2LOCK - Zabbix Agent 2*" -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule

    # 1. Regras de Entrada (Inbound): 10050 (consultas passivas) e 10051 (comunicacao Zabbix)
    foreach ($port in $FwInboundPorts) {
        $inDesc = if ($port -eq $ZabbixAgentPort -or $port -eq "10050") {
            "Permite consultas passivas do Zabbix Server ($ZabbixServer) ao agente na porta $port."
        } else {
            "Permite comunicacao do Zabbix Server ($ZabbixServer) na porta $port."
        }

        New-NetFirewallRule `
            -DisplayName "2LOCK - Zabbix Agent 2 - Entrada TCP $port" `
            -Description $inDesc `
            -Direction Inbound -Action Allow -Protocol TCP -LocalPort $port `
            -RemoteAddress $ZabbixServer -Profile Any | Out-Null
    }

    # 2. Regras de Saida (Outbound): 10051 (checagens ativas do agente para o Zabbix Server)
    New-NetFirewallRule `
        -DisplayName "2LOCK - Zabbix Agent 2 - Saida TCP 10051" `
        -Description "Permite conexoes ativas e envio de dados do agente para o Zabbix Server ($ZabbixServer) na porta 10051." `
        -Direction Outbound -Action Allow -Protocol TCP -RemotePort "10051" `
        -RemoteAddress $ZabbixServer -Profile Any | Out-Null

    # Se a porta do agente for customizada, garante tambem saida correspondente
    if ($ZabbixAgentPort -ne "10050") {
        New-NetFirewallRule `
            -DisplayName "2LOCK - Zabbix Agent 2 - Saida TCP $ZabbixAgentPort" `
            -Description "Permite conexoes do agente para o servidor na porta $ZabbixAgentPort." `
            -Direction Outbound -Action Allow -Protocol TCP -RemotePort $ZabbixAgentPort `
            -RemoteAddress $ZabbixServer -Profile Any | Out-Null
    }

    Write-Host "Regras de firewall criadas com sucesso (Entrada: $(($FwInboundPorts) -join ', ') | Saida: 10051), restritas a $ZabbixServer." -ForegroundColor Green
} catch {
    Stop-Installer "Falha ao configurar as regras de firewall: $($_.Exception.Message)"
}

# 10. Reiniciar servico e validar funcionamento
Write-Host "[6/6] Reiniciando e validando o servico..." -ForegroundColor Cyan

try {
    $CurrentSvc = Get-Service -Name $Service.Name
    if ($CurrentSvc.Status -eq "Running") {
        Restart-Service -Name $Service.Name -Force
    } else {
        Start-Service -Name $Service.Name
    }

    $FinalService = $null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $FinalService = Get-Service -Name $Service.Name
        if ($FinalService.Status -eq "Running") { break }
    }

    if ($FinalService.Status -ne "Running") {
        Stop-Installer "O servico nao iniciou. Consulte o log MSI e o log do agente."
    }
    Write-Host "Servico do Zabbix Agent 2 em execucao." -ForegroundColor Green

    # Validacao do agente base
    try {
        $AgentPing = (& $AgentExe -c $ConfigPath -t "agent.ping" 2>&1 | Out-String).Trim()
        Write-Host "Validacao agent.ping: $AgentPing" -ForegroundColor DarkGray
    } catch { }

    # Validacao do plugin MSSQL se configurado
    if ($SelectedPlugins -contains "mssql") {
        Write-Host "`nValidando funcionamento do plugin MSSQL..." -ForegroundColor Cyan

        $MssqlPingRes = $null
        try {
            $MssqlPingRes = (& $AgentExe -c $ConfigPath -t "mssql.ping" 2>&1 | Out-String).Trim()
        } catch {
            $MssqlPingRes = $_.Exception.Message
        }
        Write-Host "Teste 'mssql.ping' (Default): $MssqlPingRes" -ForegroundColor DarkGray

        $SessionPingRes = $null
        try {
            $SessionPingRes = (& $AgentExe -c $ConfigPath -t "mssql.ping[MSSQL]" 2>&1 | Out-String).Trim()
        } catch { }
        if ($SessionPingRes) {
            Write-Host "Teste 'mssql.ping[MSSQL]': $SessionPingRes" -ForegroundColor DarkGray
        }

        if ($MssqlPingRes -match '\[(?:u|s|m)\|1\]' -or $MssqlPingRes -match '\[1\]' -or
            $SessionPingRes -match '\[(?:u|s|m)\|1\]' -or $SessionPingRes -match '\[1\]') {
            Write-Host "[OK] Conexao com Microsoft SQL Server validada com sucesso! (ping = 1)" -ForegroundColor Green
        } elseif ($MssqlPingRes -match '\[(?:u|s|m)\|0\]' -or $MssqlPingRes -match '\[0\]' -or
                  $SessionPingRes -match '\[(?:u|s|m)\|0\]' -or $SessionPingRes -match '\[0\]') {
            Write-Host "[AVISO] Plugin MSSQL ativo, mas o SQL Server retornou status 0." -ForegroundColor Yellow
            Write-Host "Dica: Verifique se a instancia SQL esta ativa em ${SqlAddress}:${SqlPort} e as credenciais do zbx_monitor." -ForegroundColor Yellow
        } elseif ($MssqlPingRes -match '(?i)Unknown metric') {
            Write-Host "[ALERTA] O agente nao reconheceu a metrica mssql.ping. Verifique Plugins.MSSQL.System.Path." -ForegroundColor Red
        } else {
            Write-Host "[INFO] Resposta do teste MSSQL: $MssqlPingRes" -ForegroundColor Yellow
        }
    }
} catch {
    Stop-Installer "Falha ao iniciar ou validar o servico: $($_.Exception.Message)"
}

# 11. Resultado da instalacao
Write-Host "`n=============================================="
Write-Host "         RESULTADO DA INSTALACAO"
Write-Host "=============================================="
Write-Host "Servico         : $($FinalService.Status)"
Write-Host "Nome do servico : $($Service.Name)"
Write-Host "Host Zabbix     : $ZabbixHostname"
Write-Host "Servidor        : $ZabbixServer"
Write-Host "Porta do agente : $ZabbixAgentPort"
Write-Host "Plugins         : $(Get-PluginSelectionLabel)"
Write-Host "Configuracao    : $ConfigPath"
$FwSummaryLabel = if ($ZabbixAgentPort -eq "10050") {
    "TCP 10050 e 10051 (Entrada e Saida) restrito a $ZabbixServer"
} else {
    "TCP $ZabbixAgentPort, 10050 e 10051 (Entrada e Saida) restrito a $ZabbixServer"
}
Write-Host "Firewall        : $FwSummaryLabel"
Write-Host "Log MSI         : $MsiLog"
if ($LoadableSelected.Count -gt 0) {
    Write-Host "Log plugins     : $PluginsMsiLog"
}
if ($SelectedPlugins -contains "mssql") {
    Write-Host "----------------------------------------------"
    Write-Host "Config MSSQL    : $MssqlConfPath"
    Write-Host "Instancia SQL   : $SqlAddress"
    Write-Host "Porta SQL       : $SqlPort"
    Write-Host "Usuario SQL     : zbx_monitor (fixo)"
    Write-Host "Banco SQL       : $SqlDatabase"
    Write-Host "Criptografia    : $SqlEncrypt"
    Write-Host "TrustCert       : $SqlTrustServerCertificate"
    Write-Host "Timeout SQL     : ${SqlTimeout}s"
}

if ($FinalService.Status -eq "Running") {
    Write-Host "`nSTATUS FINAL: AGENTE EM EXECUCAO" -ForegroundColor Green
} else {
    Write-Host "`nSTATUS FINAL: FALHA AO INICIAR O AGENTE" -ForegroundColor Red
}

if ($SelectedPlugins -contains "mssql") {
    Write-Host "`nPlugin MSSQL configurado automaticamente em $MssqlConfPath." -ForegroundColor Green
    Write-Host "No frontend Zabbix, associe o template oficial 'Microsoft SQL by Zabbix agent 2'." -ForegroundColor DarkGray
}

$OtherStubs = @($SelectedPlugins | Where-Object { $_ -ne "mssql" })
if ($OtherStubs.Count -gt 0) {
    Write-Host "`nDemais plugins ($($OtherStubs -join ', ')): preencha as credenciais/sessoes nos stubs de $AgentConfD e reinicie o servico." -ForegroundColor Yellow
}

Write-Host "`nA instalacao foi concluida. Cadastre o host '$ZabbixHostname' no frontend do Zabbix se ainda nao existir."