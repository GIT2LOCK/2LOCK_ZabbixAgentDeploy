#requires -Version 5.1

# ============================================================
# 2LOCK - Instalador automatico do Zabbix Agent 2
# Windows Server 64 bits | Zabbix 7.0 LTS
# Uso: colar no PowerShell como Administrador e responder 2 perguntas
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

$BaseDir  = Join-Path $env:ProgramData "2LOCK\ZabbixAgent2"
$MsiPath  = Join-Path $BaseDir "zabbix_agent2.msi"
$MsiLog   = Join-Path $BaseDir "install-msi.log"
$RuleName = "2LOCK - Zabbix Agent 2 - TCP 10050"
$MsiUrl   = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/latest/zabbix_agent2-7.0-latest-windows-amd64-openssl.msi"

function Stop-Installer {
    param([string]$Message)
    Write-Host "`nERRO: $Message" -ForegroundColor Red
    Write-Host "Log MSI: $MsiLog" -ForegroundColor Yellow
    throw "Instalacao abortada."
}

Write-Host "=============================================="
Write-Host "  2LOCK - Zabbix Agent 2 para Windows Server"
Write-Host "==============================================`n"

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

Write-Host "`nResumo:"
Write-Host "  Host Zabbix   : $ZabbixHostname"
Write-Host "  Servidor      : $ZabbixServer"
Write-Host "  Porta ativa   : TCP 10051"
Write-Host "  Porta passiva : TCP 10050`n"

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

# 5. Download do MSI
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

# 6. Instalacao silenciosa
try {
    Write-Host "[2/6] Instalando o agente..." -ForegroundColor Cyan

    $InstallArgs = "/i `"$MsiPath`" /qn /norestart /l*v `"$MsiLog`" " +
                   "SERVER=$ZabbixServer SERVERACTIVE=$ZabbixServer " +
                   "HOSTNAME=`"$ZabbixHostname`" LISTENPORT=10050 " +
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

# 7. Localizar servico e config
Write-Host "[3/6] Localizando o servico e a configuracao..." -ForegroundColor Cyan

$Service = Get-CimInstance Win32_Service |
    Where-Object { $_.PathName -match '(?i)zabbix_agent2\.exe' } |
    Select-Object -First 1

if (-not $Service) {
    Stop-Installer "O servico do Zabbix Agent 2 nao foi encontrado apos a instalacao."
}

$ConfigPath = $null

if ($Service.PathName -match '(?i)(?:--config|-c)\s+"([^"]+\.conf)"') {
    $ConfigPath = $Matches[1]
}
elseif ($Service.PathName -match '(?i)(?:--config|-c)\s+(\S+\.conf)') {
    $ConfigPath = $Matches[1]
}
else {
    $ExeMatch = [regex]::Match($Service.PathName, '(?i)"?([^"]*zabbix_agent2\.exe)"?')
    if ($ExeMatch.Success) {
        $ConfigPath = Join-Path (Split-Path $ExeMatch.Groups[1].Value) "zabbix_agent2.conf"
    }
}

if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
    Stop-Installer "Nao foi possivel localizar o arquivo de configuracao. Caminho detectado: $ConfigPath"
}

# 8. Ajustar config
Write-Host "[4/6] Configurando o agente..." -ForegroundColor Cyan

try {
    $BackupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -Path $ConfigPath -Destination $BackupPath -Force

    $Lines = [System.Collections.Generic.List[string]]::new()
    [System.IO.File]::ReadAllLines($ConfigPath) | ForEach-Object { [void]$Lines.Add($_) }

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

    Set-AgentParameter $Lines "Server"       $ZabbixServer
    Set-AgentParameter $Lines "ServerActive" $ZabbixServer
    Set-AgentParameter $Lines "Hostname"     $ZabbixHostname
    Set-AgentParameter $Lines "ListenPort"   "10050"
    Set-AgentParameter $Lines "Timeout"      "10"

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

# 9. Firewall
Write-Host "[5/6] Configurando o firewall..." -ForegroundColor Cyan

try {
    Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule

    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Description "Permite consultas passivas somente do servidor Zabbix informado no instalador." `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 10050 `
        -RemoteAddress $ZabbixServer -Profile Any | Out-Null

    Write-Host "Regra de entrada criada, restrita a $ZabbixServer." -ForegroundColor Green
} catch {
    Stop-Installer "Falha ao configurar a regra de firewall: $($_.Exception.Message)"
}

# 10. Iniciar servico
Write-Host "[6/6] Iniciando o servico..." -ForegroundColor Cyan

try {
    Start-Service -Name $Service.Name

    $FinalService = $null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $FinalService = Get-Service -Name $Service.Name
        if ($FinalService.Status -eq "Running") { break }
    }

    if ($FinalService.Status -ne "Running") {
        Stop-Installer "O servico nao iniciou. Consulte o log MSI e o log do agente."
    }
} catch {
    Stop-Installer "Falha ao iniciar o servico: $($_.Exception.Message)"
}

# 11. Resultado
Write-Host "`n=============================================="
Write-Host "         RESULTADO DA INSTALACAO"
Write-Host "=============================================="
Write-Host "Servico         : $($FinalService.Status)"
Write-Host "Nome do servico : $($Service.Name)"
Write-Host "Host Zabbix     : $ZabbixHostname"
Write-Host "Servidor        : $ZabbixServer"
Write-Host "Configuracao    : $ConfigPath"
Write-Host "Firewall        : TCP 10050 limitado ao IP informado"
Write-Host "Log MSI         : $MsiLog"

if ($FinalService.Status -eq "Running") {
    Write-Host "`nSTATUS FINAL: AGENTE EM EXECUCAO" -ForegroundColor Green
} else {
    Write-Host "`nSTATUS FINAL: FALHA AO INICIAR O AGENTE" -ForegroundColor Red
}

Write-Host "`nA instalacao foi concluida. Cadastre o host '$ZabbixHostname' no frontend do Zabbix se ainda nao existir."