# Gera todos os instaladores do BarclayFlix com nomes prontos na pasta "dist".
# Uso (PowerShell, na pasta do projeto):  .\build_all.ps1
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$app  = Join-Path $root 'app'
$dist = Join-Path $root 'dist'
Set-Location $app

# Versão lida do pubspec.yaml (ex.: 3.0.0+1 -> 3.0.0)
$ver = ((Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value -split '\+')[0]

Write-Host "== Analisando e testando ==" -ForegroundColor Cyan
flutter analyze --no-fatal-infos; if ($LASTEXITCODE -ne 0) { throw 'flutter analyze falhou' }
flutter test;    if ($LASTEXITCODE -ne 0) { throw 'flutter test falhou' }

Write-Host "== APKs Android ==" -ForegroundColor Cyan
flutter build apk --release --split-per-abi --dart-define-from-file=config.local.json
if ($LASTEXITCODE -ne 0) { throw 'build apk falhou' }

Write-Host "== Windows ==" -ForegroundColor Cyan
flutter build windows --release --dart-define-from-file=config.local.json
if ($LASTEXITCODE -ne 0) { throw 'build windows falhou' }

New-Item -ItemType Directory -Force -Path $dist | Out-Null
# Limpa versões anteriores: a pasta dist fica só com a versão atual.
Get-ChildItem $dist -Force | Remove-Item -Recurse -Force
$apkDir = Join-Path $app 'build\app\outputs\flutter-apk'
Copy-Item "$apkDir\app-armeabi-v7a-release.apk" "$dist\BarclayFlix-$ver-TV-antiga-32bit.apk" -Force
Copy-Item "$apkDir\app-arm64-v8a-release.apk"   "$dist\BarclayFlix-$ver-Celular-TV-nova-64bit.apk" -Force

# Nomes fixos para a release do GitHub: o link .../releases/latest/download/<nome> nunca muda.
$gh = Join-Path $dist 'github'
New-Item -ItemType Directory -Force -Path $gh | Out-Null
Copy-Item "$apkDir\app-armeabi-v7a-release.apk" "$gh\BarclayFlix-armeabi-v7a.apk" -Force
Copy-Item "$apkDir\app-arm64-v8a-release.apk"   "$gh\BarclayFlix-arm64-v8a.apk" -Force

$zip = "$dist\BarclayFlix-$ver-Windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$app\build\windows\x64\runner\Release\*" -DestinationPath $zip

Write-Host "`nPronto! Arquivos em: $dist" -ForegroundColor Green
Get-ChildItem $dist | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,1)}}
Invoke-Item $dist
