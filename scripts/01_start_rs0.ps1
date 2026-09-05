# scripts/01_start_rs0.ps1 - Demarrage de rs0 avec readiness polling actif et detection universelle

$ErrorActionPreference = "Stop"

# Detection universelle et dynamique du binaire mongod
$mongod = (Get-Command mongod -ErrorAction SilentlyContinue).Source
if (-not $mongod) {
    $candidates = @(
        "$env:ProgramFiles\MongoDB\Server\*\bin\mongod.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\*\bin\mongod.exe"
    )
    foreach ($pattern in $candidates) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $mongod = $found.FullName
            break
        }
    }
}

if (-not $mongod) {
    Write-Error "Binaire mongod.exe introuvable. Veuillez verifier l'installation de MongoDB."
    exit 1
}

Write-Host "[INFO] Binaire mongod detecte : $mongod" -ForegroundColor Cyan

# Fonction de verification active de disponibilite
function Wait-MongoPort {
    param([int]$Port, [int]$TimeoutSec = 30)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $res = mongosh --port $Port --eval "db.adminCommand('ping').ok" --quiet 2>$null
        if ($res -match "1") {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

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

# Attente active de disponibilite sur les 3 ports
if (-not (Wait-MongoPort -Port 27018) -or -not (Wait-MongoPort -Port 27019) -or -not (Wait-MongoPort -Port 27020)) {
    Write-Error "[ECHEC] L'une des instances mongod de rs0 n'a pas demarre a temps."
    exit 1
}

Write-Host "`n[OK] Les 3 instances rs0 sont pretes et operationnelles sur leurs ports." -ForegroundColor Green
exit 0