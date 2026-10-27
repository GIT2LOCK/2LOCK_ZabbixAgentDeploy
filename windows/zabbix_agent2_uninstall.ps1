#requires -Version 5.1

# ============================================================
# 2LOCK - Desinstalador Completo do Zabbix Agent 2 e Plugins
# Windows Server 64 bits
# Remove: Servico, MSI do Agente, MSI dos Plugins (MSSQL, etc.),
#         Arquivos residuais, Regras de Firewall e Diretorios
# ============================================================

$ErrorActionPreference = "Continue"

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "   2LOCK - Remocao Completa do Zabbix Agent 2 e Plugins" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

# 1. Verificacao de permissao de administrador
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "ERRO: execute este script em um PowerShell como Administrador." -ForegroundColor Red
    Write-Host "Feche esta janela, abra o PowerShell como admin e execute novamente." -ForegroundColor Yellow
    return
}

# 2. Interromper processos em execucao do Zabbix e plugins
Write-Host "[1/6] Finalizando processos do Zabbix e plugins..." -ForegroundColor Cyan
$ProcessNames = @("zabbix_agent2", "zabbix_agentd", "zabbix-agent2-plugin-*")
foreach ($pName in $ProcessNames) {
    $running = Get-Process -Name $pName -ErrorAction SilentlyContinue
    if ($running) {
        $running | ForEach-Object {
            Write-Host "  Encerrando processo: $($_.ProcessName) (PID: $($_.Id))" -ForegroundColor Yellow
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

# 3. Interromper servicos do Windows
Write-Host "[2/6] Interrompendo servicos do Zabbix..." -ForegroundColor Cyan
$Services = Get-Service -Name "*zabbix*" -ErrorAction SilentlyContinue
foreach ($svc in $Services) {
    if ($svc.Status -eq "Running") {
        Write-Host "  Parando servico: $($svc.DisplayName) ($($svc.Name))..." -ForegroundColor Yellow
        Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

# 4. Desinstalacao dos pacotes MSI via Windows Installer (Agente e Plugins)
Write-Host "[3/6] Desinstalando pacotes MSI registrados no Windows..." -ForegroundColor Cyan
$UninstallRegistryPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$InstalledPackages = Get-ItemProperty -Path $UninstallRegistryPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match '(?i)Zabbix' }

if ($InstalledPackages) {
    foreach ($pkg in $InstalledPackages) {
        $prodName = $pkg.DisplayName
        $prodCode = $null

        # Tenta capturar o ProductCode (GUID)
        if ($pkg.PSChildName -match '^\{[A-F0-9\-]+\}$') {
            $prodCode = $pkg.PSChildName
        } elseif ($pkg.UninstallString -match '(?i)\{[A-F0-9\-]+\}') {
            $prodCode = $Matches[0]
        }

        if ($prodCode) {
            Write-Host "  Removendo pacote MSI: $prodName ($prodCode)..." -ForegroundColor Yellow
            $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$prodCode`" /qn /norestart" -Wait -PassThru
            if ($proc.ExitCode -in @(0, 3010)) {
                Write-Host "  [OK] $prodName desinstalado com sucesso." -ForegroundColor Green
            } else {
                Write-Host "  [AVISO] msiexec retornou codigo $($proc.ExitCode) para $prodName." -ForegroundColor DarkYellow
            }
        } else {
            Write-Host "  [INFO] Pacote $prodName encontrado sem ProductCode MSI direto." -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  Nenhum pacote MSI do Zabbix encontrado no Registro." -ForegroundColor DarkGray
}

# 5. Exclusao forcada do servico no Windows (caso o MSI tenha deixado orfao)
Write-Host "[4/6] Verificando remocao do servico Windows..." -ForegroundColor Cyan
$RemainingServices = Get-Service -Name "*zabbix*" -ErrorAction SilentlyContinue
if ($RemainingServices) {
    foreach ($svc in $RemainingServices) {
        Write-Host "  Removendo servico residual: $($svc.Name)..." -ForegroundColor Yellow
        & sc.exe delete "$($svc.Name)" | Out-Null
        Start-Sleep -Seconds 1
    }
} else {
    Write-Host "  Nenhum servico residual encontrado." -ForegroundColor Green
}

# 6. Remocao das regras de Firewall criadas para o Zabbix
Write-Host "[5/6] Removendo regras de firewall..." -ForegroundColor Cyan
try {
    $FwRules = Get-NetFirewallRule -DisplayName "2LOCK - Zabbix Agent 2*" -ErrorAction SilentlyContinue
    if ($FwRules) {
        $FwRules | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        Write-Host "  Regras de firewall '2LOCK - Zabbix Agent 2*' removidas." -ForegroundColor Green
    }

    $ZbxDefaultRules = Get-NetFirewallRule -DisplayName "*Zabbix Agent*" -ErrorAction SilentlyContinue
    if ($ZbxDefaultRules) {
        $ZbxDefaultRules | Remove-NetFirewallRule -ErrorAction SilentlyContinue
        Write-Host "  Regras padrao de firewall do Zabbix removidas." -ForegroundColor Green
    }
} catch {
    Write-Host "  Nao foi possivel remover regras de firewall: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# 7. Limpeza de pastas e arquivos residuais
Write-Host "[6/6] Limpando pastas e arquivos residuais..." -ForegroundColor Cyan
$DirsToClean = @(
    "C:\Program Files\Zabbix Agent 2",
    "C:\Program Files (x86)\Zabbix Agent 2",
    "C:\ProgramData\2LOCK\ZabbixAgent2"
)

foreach ($dir in $DirsToClean) {
    if (Test-Path $dir) {
        try {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
            Write-Host "  [OK] Diretorio removido: $dir" -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] Nao foi possivel excluir $dir completamente: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Diretorio nao existe (ja limpo): $dir" -ForegroundColor DarkGray
    }
}

# Limpeza de arquivos temporarios MSI no %TEMP%
Get-ChildItem -Path $env:TEMP -Filter "zabbix*" -File -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue }

# Limpeza do PATH do sistema (caso ENABLEPATH=1 tenha inserido)
try {
    $RegKeyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $CurrentPath = (Get-ItemProperty -Path $RegKeyPath -Name Path -ErrorAction SilentlyContinue).Path
    if ($CurrentPath -match '(?i)C:\\Program Files\\Zabbix Agent 2;?') {
        $NewPath = $CurrentPath -replace '(?i)C:\\Program Files\\Zabbix Agent 2;?', ''
        Set-ItemProperty -Path $RegKeyPath -Name Path -Value $NewPath
        Write-Host "  Caminho do Zabbix Agent 2 removido do PATH do sistema." -ForegroundColor Green
    }
} catch { }

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "   Remocao concluida com sucesso!" -ForegroundColor Green
Write-Host "   O Zabbix Agent 2 e seus plugins (MSSQL, etc.) foram apagados." -ForegroundColor Green
Write-Host "============================================================`n" -ForegroundColor Green
