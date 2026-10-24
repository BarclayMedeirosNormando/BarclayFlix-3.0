# Roda o app em desenvolvimento passando app/config.local.json (API_URL).
# Uso:  .\scripts\run_dev.ps1            (Windows)
#       .\scripts\run_dev.ps1 -Device <id>   (veja os ids com: flutter devices)
param([string]$Device = "windows")

$ErrorActionPreference = "Stop"
$appDir = Join-Path $PSScriptRoot "..\app"
$config = Join-Path $appDir "config.local.json"

if (-not (Test-Path $config)) {
    Write-Error "Falta app\config.local.json. Copie app\config.example.json para app\config.local.json e coloque a URL do Apps Script."
    exit 1
}

Push-Location $appDir
try {
    flutter run -d $Device --dart-define-from-file=config.local.json
}
finally {
    Pop-Location
}
