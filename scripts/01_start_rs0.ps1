$ErrorActionPreference = "Stop"

# Detection automatique du binaire mongod
$mongod = (Get-Command mongod -ErrorAction SilentlyContinue).Source
if (-not $mongod) {
    $candidates = @(
        "$env:ProgramFiles\MongoDB\Server\8.0\bin\mongod.exe",
        "$env:ProgramFiles\MongoDB\Server\7.0\bin\mongod.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\8.0\bin\mongod.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\7.0\bin\mongod.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { $mongod = $path; break }
    }
}

if (-not $mongod) {
    Write-Error "Binaire mongod.exe introuvable. Verifiez l'installation de MongoDB."
}

Write-Host "[INFO] Binaire mongod detecte : $mongod" -ForegroundColor Cyan

# Creation des dossiers de donnees
$paths = @("C:\data\rs0_1", "C:\data\rs0_2", "C:\data\rs0_3")
foreach ($p in $paths) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Force -Path $p | Out-Null
    }
}

# Demarrage des 3 instances
Write-Host "[1/3] Lancement mongod Node 1 (Data) sur port 27018..." -ForegroundColor Green
Start-Process -FilePath $mongod -ArgumentList "--replSet rs0 --port 27018 --dbpath C:\data\rs0_1 --bind_ip localhost" -WindowStyle Hidden

Write-Host "[2/3] Lancement mongod Node 2 (Data) sur port 27019..." -ForegroundColor Green
Start-Process -FilePath $mongod -ArgumentList "--replSet rs0 --port 27019 --dbpath C:\data\rs0_2 --bind_ip localhost" -WindowStyle Hidden

Write-Host "[3/3] Lancement mongod Node 3 (Arbiter) sur port 27020..." -ForegroundColor Green
Start-Process -FilePath $mongod -ArgumentList "--replSet rs0 --port 27020 --dbpath C:\data\rs0_3 --bind_ip localhost" -WindowStyle Hidden

Start-Sleep -Seconds 3
Write-Host "[OK] Les 3 instances rs0 sont demarrees en arriere-plan." -ForegroundColor Yellow
