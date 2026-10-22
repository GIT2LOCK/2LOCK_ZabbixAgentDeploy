#requires -Version 5.1

# ============================================================
# 2LOCK - Instalador automatico do Zabbix Agent 2
# Windows Server 64 bits | Zabbix 7.0 LTS
# Uso: colar no PowerShell como Administrador e responder as perguntas
# (NOVO) Termo de uso, porta do agente configuravel e plugins opcionais
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
# (NOVO) $RuleName agora e definido depois da pergunta da porta (inclui $ZabbixAgentPort)
$MsiUrl   = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/latest/zabbix_agent2-7.0-latest-windows-amd64-openssl.msi"

function Stop-Installer {
    param([string]$Message)
    Write-Host "`nERRO: $Message" -ForegroundColor Red
    Write-Host "Log MSI: $MsiLog" -ForegroundColor Yellow
    throw "Instalacao abortada."
}

# ------------------------------------------------------------
# (NOVO) PLUGINS OPCIONAIS
# Built-in  = ja compilado no zabbix_agent2.exe, nenhuma instalacao extra.
# Loadable  = exige o pacote separado zabbix_agent2_plugins-<versao>-windows-amd64.msi.
# A selecao decide (a) se o pacote de plugins e baixado/instalado e
# (b) quais stubs de configuracao sao gerados em zabbix_agent2.d\.
# Apenas MSSQL tem guia completo (windows\plugins\mssql.md).
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

# Retorna $true se a selecao e valida, $false se houver opcao invalida
# (diferente do script maior: em vez de abortar, avisa e deixa o prompt repetir)
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
    Write-Host "  deles for selecionado. Apenas MSSQL tem guia completo neste projeto" -ForegroundColor DarkGray
    Write-Host "  (windows\plugins\mssql.md)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Selecione os plugins a configurar (Enter = nenhum):"
    Write-Host ""
    Write-Host "  [1] MySQL       (built-in)"
    Write-Host "  [2] PostgreSQL  (loadable, instala pacote extra)"
    Write-Host "  [3] MongoDB     (loadable, instala pacote extra)"
    Write-Host "  [4] Memcached   (built-in)"
    Write-Host "  [5] MSSQL       (loadable, instala pacote extra)"
    Write-Host "  [6] Todos"
    Write-Host "  [0] Nenhum"
    Write-Host ""
    do {
        $raw = (Read-Host "  Opcoes (ex: 5 ou 0 para nenhum)").Trim()
        $ok  = Resolve-PluginSelection $raw
    } while (-not $ok)
    Write-Host "Plugins selecionados: $(Get-PluginSelectionLabel)." -ForegroundColor Green
}

Write-Host "=============================================="
Write-Host "  2LOCK - Zabbix Agent 2 para Windows Server"
Write-Host "==============================================`n"

# 0. (NOVO) Termo de uso - aceite obrigatorio
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

# 2b. (NOVO) Porta do agente (default 10050; a porta 10051 do Server NAO muda)
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

# Nome da regra de firewall inclui a porta (evita conflito entre portas diferentes)
$RuleName = "2LOCK - Zabbix Agent 2 - TCP $ZabbixAgentPort"

# 2c. (NOVO) Selecao de plugins opcionais
Write-Host ""
Show-PluginPrompt

Write-Host "`nResumo:"
Write-Host "  Host Zabbix   : $ZabbixHostname"
Write-Host "  Servidor      : $ZabbixServer"
Write-Host "  Porta ativa   : TCP 10051"
Write-Host "  Porta passiva : TCP $ZabbixAgentPort"
Write-Host "  Plugins       : $(Get-PluginSelectionLabel)`n"

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

    # (NOVO) LISTENPORT agora usa $ZabbixAgentPort
    $InstallArgs = "/i `"$MsiPath`" /qn /norestart /l*v `"$MsiLog`" " +
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

# 6b. (NOVO) Descobrir a pasta de instalacao do agente (so se houver plugins)
$InstallDir = $null
$AgentExe   = $null
if ($SelectedPlugins.Count -gt 0) {
    $SvcPre = Get-CimInstance Win32_Service |
        Where-Object { $_.PathName -match '(?i)zabbix_agent2\.exe' } |
        Select-Object -First 1
    if (-not $SvcPre) {
        Stop-Installer "O servico do Zabbix Agent 2 nao foi encontrado apos a instalacao."
    }
    $ExePre = [regex]::Match($SvcPre.PathName, '(?i)"?([^"]*zabbix_agent2\.exe)"?')
    if (-not $ExePre.Success) {
        Stop-Installer "Nao foi possivel determinar a pasta de instalacao do agente."
    }
    $AgentExe   = $ExePre.Groups[1].Value
    $InstallDir = Split-Path $AgentExe
}

# 6c. (NOVO) Pacote de plugins LOADABLE (PostgreSQL / MongoDB / MSSQL)
$PluginsInstalled = $false
$PluginsMsiLog    = Join-Path $BaseDir "msi_plugins_install.log"
$LoadableSelected = @($SelectedPlugins | Where-Object { $LoadablePluginKeys -contains $_ })

if ($LoadableSelected.Count -gt 0) {
    $LoadableLabels = ($LoadableSelected | ForEach-Object { Get-PluginLabel $_ }) -join ", "
    Write-Host "[2b/6] Instalando pacote de plugins ($LoadableLabels)..." -ForegroundColor Cyan

    # A versao do pacote de plugins deve ser a mesma do agente instalado
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
        Write-Host "Falha ao baixar o pacote de plugins: $($_.Exception.Message)" -ForegroundColor Yellow
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
                Write-Host "Pacote de plugins instalado. Log: $PluginsMsiLog" -ForegroundColor Green
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

# 6d. (NOVO) Stubs de configuracao dos plugins selecionados
# Apenas comentarios: NAO configura credenciais automaticamente.
if ($SelectedPlugins.Count -gt 0) {
    Write-Host "[2c/6] Gerando stubs de configuracao dos plugins..." -ForegroundColor Cyan

    $AgentConfD = Join-Path $InstallDir "zabbix_agent2.d"
    New-Item -Path $AgentConfD -ItemType Directory -Force | Out-Null

    # Sem BOM (o agente rejeita BOM em arquivos .conf, inclusive nos includes)
    $StubEncoding = New-Object System.Text.UTF8Encoding($false)

    $PkgLine = if ($PluginsInstalled) {
        "O pacote zabbix_agent2_plugins ja foi instalado por este script"
    } else {
        "ATENCAO: o pacote zabbix_agent2_plugins NAO foi instalado por este script (instale manualmente)"
    }

    foreach ($plugin in $SelectedPlugins) {
        $label    = Get-PluginLabel $plugin
        $kind     = Get-PluginKind $plugin
        $stubFile = Join-Path $AgentConfD "2lock_$plugin.conf"

        if ($plugin -eq "mssql") {
            $stubContent = @"
# =============================================================================
# Plugin MSSQL (loadable) -- Zabbix Agent 2 -- 2LOCK
# Ver guia completo: windows\plugins\mssql.md
#
# $PkgLine
# e ele deve ter gerado um .conf proprio em $AgentConfD com
# Plugins.MSSQL.System.Path apontando para o binario do plugin. Este arquivo
# aqui e so um lembrete das credenciais de sessao que ainda faltam preencher
# (no .conf oficial, nao aqui):
# =============================================================================
# Plugins.MSSQL.Sessions.<nome_sessao>.Uri=sqlserver://127.0.0.1:1433
# Plugins.MSSQL.Sessions.<nome_sessao>.User=<usuario_monitoramento>
# Plugins.MSSQL.Sessions.<nome_sessao>.Password=<senha>
#
# Apos configurar, valide com:
#   zabbix_agent2.exe -t mssql.ping[<nome_sessao>]
# Aplique o template oficial "MSSQL by Zabbix agent 2" no frontend.
"@
            Write-Host "  MSSQL: guia completo em windows\plugins\mssql.md" -ForegroundColor DarkGray
        } elseif ($kind -eq "loadable") {
            $stubContent = @"
# =============================================================================
# Plugin $label (loadable) -- Zabbix Agent 2 -- 2LOCK
# $PkgLine
# e ele deve ter gerado seu proprio arquivo .conf em $AgentConfD, com o caminho
# do binario (Plugins.$($label).System.Path) ja preenchido. Este arquivo e so um
# lembrete das credenciais de sessao, ainda pendentes de preenchimento la, nao aqui.
# Consulte a documentacao oficial do Zabbix para a sintaxe de
# Plugins.$($label.ToUpper()).Sessions.<nome>.*
# =============================================================================
"@
            Write-Host "  ${label}: o MSI de plugins ja gera o .conf oficial (Plugins.$label.System.Path)." -ForegroundColor DarkGray
        } else {
            $stubContent = @"
# =============================================================================
# Plugin $label (built-in) -- Zabbix Agent 2 -- 2LOCK
# Ja vem compilado no zabbix_agent2.exe, nenhuma instalacao adicional foi
# necessaria. So falta configurar a sessao abaixo:
# =============================================================================
# Plugins.$label.Sessions.<nome_sessao>.Uri=tcp://127.0.0.1:<porta>
# Plugins.$label.Sessions.<nome_sessao>.User=<usuario_monitoramento>
# Plugins.$label.Sessions.<nome_sessao>.Password=<senha>
"@
            Write-Host "  ${label}: built-in, ja vem no zabbix_agent2.exe." -ForegroundColor DarkGray
        }

        try {
            [System.IO.File]::WriteAllText($stubFile, $stubContent, $StubEncoding)
            Write-Host "Stub gerado: $stubFile" -ForegroundColor Green
        } catch {
            Write-Host "Nao foi possivel gerar o stub de ${label}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
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
    Set-AgentParameter $Lines "ListenPort"   $ZabbixAgentPort    # (NOVO) porta dinamica
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

    # (NOVO) -LocalPort usa $ZabbixAgentPort
    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Description "Permite consultas passivas somente do servidor Zabbix informado no instalador." `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort $ZabbixAgentPort `
        -RemoteAddress $ZabbixServer -Profile Any | Out-Null

    Write-Host "Regra de entrada criada (TCP $ZabbixAgentPort), restrita a $ZabbixServer." -ForegroundColor Green
} catch {
    Stop-Installer "Falha ao configurar a regra de firewall: $($_.Exception.Message)"
}

# 10. Iniciar servico
Write-Host "[6/6] Iniciando o servico..." -ForegroundColor Cyan

try {
    # (AJUSTE) Se o MSI ja deixou o servico rodando, reinicia para aplicar o .conf
    # editado e carregar os plugins; Start-Service nao faria nada nesse caso.
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
Write-Host "Porta do agente : $ZabbixAgentPort"                                  # (NOVO)
Write-Host "Plugins         : $(Get-PluginSelectionLabel)"                       # (NOVO)
Write-Host "Configuracao    : $ConfigPath"
Write-Host "Firewall        : TCP $ZabbixAgentPort limitado ao IP informado"     # (NOVO) porta dinamica
Write-Host "Log MSI         : $MsiLog"
if ($LoadableSelected.Count -gt 0) {
    Write-Host "Log plugins     : $PluginsMsiLog"                                # (NOVO)
}

if ($FinalService.Status -eq "Running") {
    Write-Host "`nSTATUS FINAL: AGENTE EM EXECUCAO" -ForegroundColor Green
} else {
    Write-Host "`nSTATUS FINAL: FALHA AO INICIAR O AGENTE" -ForegroundColor Red
}

if ($SelectedPlugins.Count -gt 0) {
    Write-Host "`nPlugins: preencha as sessoes (URI/usuario/senha) nos arquivos de $AgentConfD e reinicie o servico." -ForegroundColor Yellow   # (NOVO)
}

Write-Host "`nA instalacao foi concluida. Cadastre o host '$ZabbixHostname' no frontend do Zabbix se ainda nao existir."
