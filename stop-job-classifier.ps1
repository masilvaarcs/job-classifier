# =====================================================================
#  Job Classifier - Para todos os servicos (RPC, Python HTTP/gRPC, Frontend)
# =====================================================================

$ErrorActionPreference = 'SilentlyContinue'

function Stop-Tree {
    param([int]$ProcId)
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcId" | ForEach-Object {
        Stop-Tree -ProcId $_.ProcessId
    }
    Stop-Process -Id $ProcId -Force
    Write-Host "encerrado pid $ProcId"
}

# 1) Processos ouvindo nas portas do projeto
foreach ($port in 8000, 8001, 8002, 8010, 57010, 5173) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        Stop-Tree -ProcId $c.OwningProcess
        Write-Host "porta $port liberada"
    }
}

# apphosts do .NET (o processo que escuta pode ser filho do apphost)
Get-Process -Name 'job-classifier-dotnet' -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Tree -ProcId $_.ProcessId
}

# 2) Orfaos do projeto (sem porta aberta, ex.: workers do uvicorn --reload)
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
    Where-Object { $_.CommandLine -match 'job-classifier|tsx watch' } | ForEach-Object {
        Stop-Tree -ProcId $_.ProcessId
    }
Get-CimInstance Win32_Process |
    Where-Object { $_.Name -match '^python' -and $_.CommandLine -match 'uvicorn|grpc_server|multiprocessing\.spawn' } | ForEach-Object {
        Stop-Tree -ProcId $_.ProcessId
    }

# 3) MongoDB local de desenvolvimento (somente o efemero, nunca um mongod instalado)
Get-Process mongod -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -match '\.cache' } | ForEach-Object {
        Stop-Tree -ProcId $_.ProcessId
    }

Start-Sleep -Seconds 2
Write-Host '--- estado final ---'
foreach ($port in 8000, 8001, 8002, 8010, 57010, 5173) {
    $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($c) { Write-Host "porta $port AINDA OCUPADA (pid $($c.OwningProcess | Select-Object -First 1))" -ForegroundColor Red }
    else    { Write-Host "porta $port livre" -ForegroundColor Green }
}
