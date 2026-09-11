$ErrorActionPreference = 'Stop'
$Root = 'C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier'
Set-Location "$Root\job-classifier-dotnet"

# Resolve MONGODB_URI se o launcher nao tiver passado: .env do dotnet > mongo local
if (-not $env:MONGODB_URI) {
    $envFile = "$Root\job-classifier-dotnet\.env"
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match '^\s*MONGODB_URI=.+' } | Select-Object -First 1
        if ($line) { $env:MONGODB_URI = ($line -split '=', 2)[1].Trim() }
    }
}
if (-not $env:MONGODB_URI) {
    $uriFile = "$Root\job-classifier-tools\.local-mongo-uri"
    if (Test-Path $uriFile) { $env:MONGODB_URI = (Get-Content $uriFile -Raw).Trim() }
}
if (-not $env:MONGODB_URI) { throw 'MONGODB_URI nao resolvida (.env do dotnet ou mongo local).' }

if (-not $env:PORT) { $env:PORT = '8000' }
dotnet run --no-build
