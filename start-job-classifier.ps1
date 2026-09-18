# =====================================================================
#  Job Classifier - Inicializador rapido (gRPC .NET primario)
#  Inicia: .NET gRPC (8000) + Python HTTP (8001) + Python gRPC (8002)
#          + MongoDB local se necessario (57010) + Frontend (5173)
#  e abre o navegador.
# =====================================================================

$ErrorActionPreference = 'Stop'

# ------------------- Caminhos -------------------
$Root    = 'C:\__DEV__\__Projetos_2026\classificador-vaga'
$DotnetDir = Join-Path $Root 'job-classifier-dotnet'
$PyDir   = Join-Path $Root 'job-classifier-python'
$WebDir  = Join-Path $Root 'job-classifier-react'
$ToolsDir = Join-Path $Root 'job-classifier-tools'
$VenvPy  = Join-Path $PyDir 'venv\Scripts\python.exe'

$PortRpc  = 8000
$PortPy   = 8001
$PortGpc  = 8002
$PortMongo = 57010
$PortWeb  = 5173
$FrontUrl = "http://localhost:$PortWeb"

# ------------------- Funcoes -------------------
function Test-HttpOk {
    param([string]$Url, [int]$TimeoutSec = 5)
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
        return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500)
    } catch {
        return $false
    }
}

function Test-ServiceUp {
    param([string]$Url)
    for ($i = 0; $i -lt 2; $i++) {
        if (Test-HttpOk -Url $Url -TimeoutSec 2) { return $true }
        Start-Sleep -Milliseconds 600
    }
    return $false
}

function Wait-HttpOpen {
    param([string]$Url, [int]$TimeoutSec = 60)
    Write-Host "  Aguardando $Url (ate $TimeoutSec s)..." -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-HttpOk -Url $Url -TimeoutSec 2) { return $true }
        Start-Sleep -Milliseconds 900
    }
    return $false
}

function Test-PortOpen {
    param([int]$Port)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.ConnectAsync('127.0.0.1', $Port)
        $ok = ($async.Wait(500) -and $tcp.Connected)
        $tcp.Dispose()
        return $ok
    } catch { return $false }
}

function Ensure-NpmDeps {
    param([string]$Dir, [string]$Label)
    if (Test-Path (Join-Path $Dir 'node_modules')) { return }
    Write-Host "  Instalando dependencias de $Label (npm install)..." -ForegroundColor Yellow
    Push-Location $Dir
    try {
        npm install --no-fund --no-audit
        if ($LASTEXITCODE -ne 0) { throw "npm install falhou em $Dir" }
    } finally {
        Pop-Location
    }
}

function Start-DevWindow {
    param([string]$Title, [string]$Dir, [string]$Command)
    $inner  = "Set-Location -LiteralPath '$Dir'; `$Host.UI.RawUI.WindowTitle = '$Title'; $Command"
    $argStr = "-NoProfile -ExecutionPolicy Bypass -NoExit -Command $inner"
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argStr -WorkingDirectory $Dir | Out-Null
    Write-Host "  [OK] $Title -> nova janela iniciada." -ForegroundColor Green
}

function Show-ServiceStatus {
    param([string]$Label, [string]$Url)
    if (Test-HttpOk -Url $Url) {
        Write-Host ("   [OK]    {0,-10} {1}" -f $Label, $Url) -ForegroundColor Green
    } else {
        Write-Host ("   [FALHA] {0,-10} {1}" -f $Label, $Url) -ForegroundColor Red
    }
}

function Resolve-MongoUri {
    # 1) Atlas no .env do servico .NET  2) Atlas no rpc arquivado  3) mongo local
    $candidates = @(
        (Join-Path $DotnetDir '.env'),
        (Join-Path $Root '_archive\job-classifier-rpc\.env')
    )
    foreach ($f in $candidates) {
        if (Test-Path $f) {
            $line = Get-Content $f | Where-Object { $_ -match '^\s*MONGODB_URI=.+' } | Select-Object -First 1
            if ($line) { return ($line -split '=', 2)[1].Trim() }
        }
    }
    $uriFile = Join-Path $ToolsDir '.local-mongo-uri'
    if (Test-Path $uriFile) { return (Get-Content $uriFile -Raw).Trim() }
    return $null
}

# ------------------- Inicio -------------------
try {
    Write-Host ''
    Write-Host '=================================================' -ForegroundColor Cyan
    Write-Host '   Job Classifier (gRPC .NET) - inicializando...'   -ForegroundColor Cyan
    Write-Host '=================================================' -ForegroundColor Cyan
    Write-Host ''

    # Preflight
    foreach ($dir in @($DotnetDir, $PyDir, $WebDir)) {
        if (-not (Test-Path $dir)) { throw "Pasta nao encontrada: $dir" }
    }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'dotnet nao encontrado no PATH. Instale o .NET SDK.' }
    if (-not (Test-Path $VenvPy)) { throw "venv Python nao encontrado em $VenvPy. Veja COMO_SUBIR_O_PROJETO.md." }

    # 1) MongoDB (Atlas ou local efemero)
    Write-Host '[1/4] Banco de dados (MongoDB)...' -ForegroundColor White
    $mongoUri = Resolve-MongoUri
    if ($mongoUri -and $mongoUri -notmatch '127\.0\.0\.1:57010|localhost:57010') {
        Write-Host '  [OK] Usando MONGODB_URI configurada (Atlas).' -ForegroundColor Green
    } else {
        Write-Host '  [AVISO] Sem MONGODB_URI do Atlas. Subindo MongoDB local de desenvolvimento (porta 57010)...' -ForegroundColor Yellow
        if (-not (Test-PortOpen -Port $PortMongo)) {
            Ensure-NpmDeps -Dir $ToolsDir -Label 'job-classifier-tools'
            Start-DevWindow -Title 'Job Classifier - MongoDB Local (57010)' -Dir $ToolsDir -Command 'npm run dev:mongo'
            $deadline = (Get-Date).AddSeconds(180)
            while ((Get-Date) -lt $deadline -and -not (Test-PortOpen -Port $PortMongo)) { Start-Sleep -Milliseconds 800 }
        }
        $mongoUri = Resolve-MongoUri
        if (-not $mongoUri) { throw 'MongoDB local nao ficou pronto (.local-mongo-uri ausente). Veja MIGRACAO_MONGODB.md.' }
        Write-Host '  [OK] MongoDB local pronto (dados efemeros).' -ForegroundColor Green
    }

    # 2) Servico .NET gRPC (porta 8000) - primario
    Write-Host '[2/4] Servico .NET gRPC (porta 8000)...' -ForegroundColor White
    if (Test-ServiceUp -Url 'http://localhost:8000/healthz') {
        Write-Host '  [OK] Servico .NET ja esta rodando.' -ForegroundColor Green
    } else {
        if (-not (Test-Path (Join-Path $DotnetDir 'bin\Debug\net10.0\job-classifier-dotnet.dll'))) {
            Write-Host '  Compilando (dotnet build)...' -ForegroundColor DarkGray
            Push-Location $DotnetDir
            try {
                dotnet build --nologo -v q | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'dotnet build falhou no job-classifier-dotnet' }
            } finally { Pop-Location }
        }
        $env:MONGODB_URI = "$mongoUri"
        $env:MONGODB_DB  = 'job_tracker'
        $env:PORT        = "$PortRpc"
        Start-DevWindow -Title 'Job Classifier - .NET gRPC (8000)' -Dir $DotnetDir -Command "& '$Root\run-dotnet-dev.ps1'"
        if (-not (Wait-HttpOpen -Url 'http://localhost:8000/healthz' -TimeoutSec 60)) {
            throw 'Servico .NET nao respondeu na 8000. Veja a janela do servico.'
        }
    }

    # 3) Microservicos Python (gRPC 8002 + HTTP 8001)
    Write-Host '[3/4] Microservicos Python (gRPC 8002 + HTTP 8001)...' -ForegroundColor White
    $gpcUp = Test-PortOpen -Port $PortGpc
    if ($gpcUp) {
        Write-Host '  [OK] Python gRPC ja esta rodando.' -ForegroundColor Green
    } else {
        Start-DevWindow -Title 'Job Classifier - Python gRPC (8002)' -Dir $PyDir -Command "& '$VenvPy' -m src.grpc_server"
    }

    if (Test-ServiceUp -Url 'http://localhost:8001/health') {
        Write-Host '  [OK] Python HTTP ja esta rodando.' -ForegroundColor Green
    } else {
        Start-DevWindow -Title 'Job Classifier - Python HTTP (8001)' -Dir $PyDir -Command "& '$VenvPy' -m uvicorn src.main:app --reload --port 8001"
        Wait-HttpOpen -Url 'http://localhost:8001/health' -TimeoutSec 45 | Out-Null
    }

    # 4) Frontend Vite (porta 5173)
    Write-Host '[4/4] Frontend React + Vite (porta 5173)...' -ForegroundColor White
    if (Test-ServiceUp -Url $FrontUrl) {
        Write-Host '  [OK] Frontend ja esta rodando.' -ForegroundColor Green
    } else {
        Ensure-NpmDeps -Dir $WebDir -Label 'Frontend React'
        Start-DevWindow -Title 'Job Classifier - Frontend (5173)' -Dir $WebDir -Command 'npm run dev'
        if (Wait-HttpOpen -Url $FrontUrl -TimeoutSec 60) {
            Write-Host '  [OK] Frontend pronto.' -ForegroundColor Green
        } else {
            Write-Host '  [AVISO] Frontend nao respondeu a tempo. Abrindo o navegador mesmo assim...' -ForegroundColor Yellow
        }
    }

    # Verificacao final de saude
    Write-Host ''
    Write-Host 'Verificando servicos...' -ForegroundColor White
    Show-ServiceStatus -Label 'Frontend' -Url $FrontUrl
    Show-ServiceStatus -Label '.NET gRPC'-Url 'http://localhost:8000/healthz'
    Show-ServiceStatus -Label 'Py HTTP'  -Url 'http://localhost:8001/health'

    # Abre o frontend no navegador padrao
    Write-Host ''
    Write-Host "Abrindo o navegador: $FrontUrl" -ForegroundColor Cyan
    Start-Process $FrontUrl

    Write-Host ''
    Write-Host 'Tudo pronto! Servicos em execucao:' -ForegroundColor Green
    Write-Host "   - Frontend    : $FrontUrl"
    Write-Host '   - .NET gRPC   : http://localhost:8000 (primario, gRPC + gRPC-Web)'
    Write-Host '   - Python HTTP : http://localhost:8001/docs'
    Write-Host '   - Python gRPC : porta 8002 (ScrapingService)'
    Write-Host ''
    Write-Host 'Esta janela sera fechada em 8 segundos...'
    Start-Sleep -Seconds 8
} catch {
    Write-Host ''
    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
    Start-Sleep -Seconds 15
}