# =============================================================================
#  Reset da senha do PostgreSQL local (postgresql-x64-16) - v2
#  Esperas robustas (sem race de stop/start) e escrita ASCII sem BOM.
#  Sempre restaura o pg_hba.conf original ao final (finally).
# =============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$NewPassword
)

$ErrorActionPreference = 'Stop'

$Service  = 'postgresql-x64-16'
$PgData   = 'C:\Program Files\PostgreSQL\16\data'
$PgHba    = Join-Path $PgData 'pg_hba.conf'
$PgHbaBak = "$PgHba.jobclass-bak"
$Psql     = 'C:\Program Files\PostgreSQL\16\bin\psql.exe'

function Wait-ServiceStatus([string]$Name, [string]$Status, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-Service -Name $Name).Status -eq $Status) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return ((Get-Service -Name $Name).Status -eq $Status)
}

function Wait-PortReady([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $c = Get-NetTCPConnection -LocalPort 5432 -State Listen -ErrorAction SilentlyContinue
        if ($c) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

Write-Host '[1/5] Parando o servico PostgreSQL...'
Stop-Service -Name $Service -Force -ErrorAction SilentlyContinue
if (-not (Wait-ServiceStatus $Service 'Stopped' 30)) { throw 'Servico nao parou a tempo.' }
Start-Sleep -Seconds 2

Write-Host '[2/5] Backup + ajustando pg_hba.conf (trust no loopback, sem BOM)...'
Copy-Item $PgHba $PgHbaBak -Force
$lines  = Get-Content $PgHba
$new = foreach ($line in $lines) {
    if ($line -match '^\s*host\s' -and $line -match '127\.0\.0\.1|::1') {
        $parts = $line -split '\s+'
        $parts[-1] = 'trust'
        ($parts -join ' ')
    } else { $line }
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($PgHba, [string[]]$new, $utf8NoBom)

try {
    Write-Host '[3/5] Iniciando o servico com trust...'
    Start-Service -Name $Service
    if (-not (Wait-ServiceStatus $Service 'Running' 30)) { throw 'Servico nao subiu a tempo.' }
    if (-not (Wait-PortReady 20)) { throw 'Porta 5432 nao respondeu a tempo.' }

    Write-Host '[4/5] Alterando as senhas (postgres e jobclass)...'
    & $Psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER USER postgres WITH PASSWORD '$NewPassword';"
    & $Psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -c "DO `$$ BEGIN IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='jobclass') THEN ALTER USER jobclass WITH PASSWORD '$NewPassword'; ELSE CREATE ROLE jobclass LOGIN PASSWORD '$NewPassword'; END IF; END `$$;"
    & $Psql -h 127.0.0.1 -U postgres -d postgres -c "SELECT rolname FROM pg_roles WHERE rolname IN ('postgres','jobclass');"

    Write-Host '[5/5] Restaurando pg_hba.conf original...'
}
finally {
    if (Test-Path $PgHbaBak) { Copy-Item $PgHbaBak $PgHba -Force }
    if ((Get-Service -Name $Service).Status -eq 'Running') {
        Restart-Service -Name $Service -Force
    } else {
        Start-Service -Name $Service
    }
    [void](Wait-ServiceStatus $Service 'Running' 30)
    [void](Wait-PortReady 20)
}

Write-Host ''
Write-Host 'OK - senha redefinida para postgres e jobclass. pg_hba.conf restaurado.'
Write-Host ('Servico: ' + (Get-Service -Name $Service).Status)
