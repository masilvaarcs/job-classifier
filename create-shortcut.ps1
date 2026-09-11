# Cria o atalho "Job Classifier" na area de trabalho
$Desktop  = [Environment]::GetFolderPath('Desktop')
$LnkPath  = Join-Path $Desktop 'Job Classifier.lnk'
$Target   = 'C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\start-job-classifier.ps1'

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($LnkPath)
$lnk.TargetPath       = 'powershell.exe'
$lnk.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$Target`""
$lnk.WorkingDirectory = 'C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier'
$lnk.Description       = 'Job Classifier: inicia tudo (Atlas + .NET 8000/8003 + Python 8001/8002 + Frontend 5173) e abre o navegador'
$lnk.IconLocation      = 'C:\Windows\System32\shell32.dll,221'
$lnk.Save()

if (Test-Path $LnkPath) {
    Write-Host "Atalho criado com sucesso: $LnkPath"
} else {
    Write-Host 'ERRO: atalho nao foi criado.' -ForegroundColor Red
    exit 1
}
