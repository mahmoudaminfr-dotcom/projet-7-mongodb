# scripts/04_start_sharding_cluster.ps1 - Orchestration robuste du cluster sharde avec test TCP et gestion des logs

$ErrorActionPreference = "Stop"

# 1. Detection universelle des binaires MongoDB
$mongod = (Get-Command mongod -ErrorAction SilentlyContinue).Source
$mongos = (Get-Command mongos -ErrorAction SilentlyContinue).Source

if (-not $mongod) {
    $candidatesMongod = @(
        "$env:ProgramFiles\MongoDB\Server\*\bin\mongod.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\*\bin\mongod.exe"
    )
    foreach ($pattern in $candidatesMongod) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $mongod = $found.FullName; break }
    }
}

if (-not $mongos) {
    $candidatesMongos = @(
        "$env:ProgramFiles\MongoDB\Server\*\bin\mongos.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\*\bin\mongos.exe"
    )
    foreach ($pattern in $candidatesMongos) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $mongos = $found.FullName; break }
    }
}

if (-not $mongod -or -not $mongos) {
    Write-Error "[ERREUR] Binaires mongod ou mongos introuvables."
    exit 1
}

Write-Host "[INFO] Mongod : $mongod" -ForegroundColor Cyan
Write-Host "[INFO] Mongos : $mongos" -ForegroundColor Cyan

# 2. Fonction de readiness polling par socket TCP (rapide et infaillible)
function Wait-MongoPort {
    param([int]$Port, [int]$TimeoutSec = 45)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $connect = $client.ConnectAsync("127.0.0.1", $Port)
            if ($connect.Wait(500) -and $client.Connected) {
                $client.Close()
                Start-Sleep -Milliseconds 500
                return $true
            }
            if ($client) { $client.Dispose() }
        } catch {}
        Start-Sleep -Milliseconds 800
    }
    return $false
}

function Test-And-CleanPath {
    param([string]$Path)
    if (Test-Path $Path) {
        $lockFile = Join-Path $Path "mongod.lock"
        if (Test-Path $lockFile) {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

# 3. Arret propre et securise des processus precedents
Write-Host "[0/4] Arret des instances precedentes..." -ForegroundColor Cyan
Get-Process mongod, mongos -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike "*Service*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Preparation des dossiers de donnees et de logs
$baseDir = "C:\data\sharding"
$logDir = "$baseDir\logs"
foreach ($d in @($baseDir, $logDir, "$baseDir\cfg", "$baseDir\shard_paris", "$baseDir\shard_lyon")) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

Test-And-CleanPath "$baseDir\cfg"
Test-And-CleanPath "$baseDir\shard_paris"
Test-And-CleanPath "$baseDir\shard_lyon"

# 4. Demarrage Config Server (csrs) sur port 27021 avec log dedie
Write-Host "[1/4] Demarrage Config Server (csrs) sur port 27021..." -ForegroundColor Cyan
$cfgLog = "$logDir\csrs.log"
Start-Process -FilePath $mongod -ArgumentList "--configsvr --replSet csrs --port 27021 --dbpath $baseDir\cfg --bind_ip localhost --logpath $cfgLog" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27021)) {
    Write-Error "[ECHEC] Le Config Server (port 27021) n'a pas demarre. Consultez le log : $cfgLog"
    exit 1
}

Write-Host "      Initialisation du replica set csrs..." -ForegroundColor Cyan
mongosh --port 27021 --eval "try { rs.initiate({ _id: 'csrs', configsvr: true, members: [{ _id: 0, host: 'localhost:27021' }] }) } catch(e) { print('deja init') }" --quiet

# 5. Demarrage des Shards (rs_paris et rs_lyon)
Write-Host "`n[2/4] Demarrage Shards Paris (27022) et Lyon (27023)..." -ForegroundColor Cyan
Start-Process -FilePath $mongod -ArgumentList "--shardsvr --replSet rs_paris --port 27022 --dbpath $baseDir\shard_paris --bind_ip localhost --logpath $logDir\shard_paris.log" -WindowStyle Hidden
Start-Process -FilePath $mongod -ArgumentList "--shardsvr --replSet rs_lyon --port 27023 --dbpath $baseDir\shard_lyon --bind_ip localhost --logpath $logDir\shard_lyon.log" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27022) -or -not (Wait-MongoPort -Port 27023)) {
    Write-Error "[ECHEC] L'un des shards n'a pas demarre a temps."
    exit 1
}

Write-Host "      Initialisation des replica sets des shards..." -ForegroundColor Cyan
mongosh --port 27022 --eval "try { rs.initiate({ _id: 'rs_paris', members: [{ _id: 0, host: 'localhost:27022' }] }) } catch(e) { print('deja init') }" --quiet
mongosh --port 27023 --eval "try { rs.initiate({ _id: 'rs_lyon', members: [{ _id: 0, host: 'localhost:27023' }] }) } catch(e) { print('deja init') }" --quiet

# 6. Demarrage du Routeur mongos
Write-Host "`n[3/4] Demarrage Routeur mongos sur port 27024..." -ForegroundColor Cyan
Start-Process -FilePath $mongos -ArgumentList "--configdb csrs/localhost:27021 --port 27024 --bind_ip localhost --logpath $logDir\mongos.log" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27024)) {
    Write-Error "[ECHEC] mongos (port 27024) n'a pas demarre a temps."
    exit 1
}

# 7. Ajout des shards au routeur mongos
Write-Host "`n[4/4] Enregistrement des shards aupres du routeur mongos..." -ForegroundColor Cyan
Start-Sleep -Seconds 3 
mongosh --port 27024 --eval "sh.addShard('rs_paris/localhost:27022'); sh.addShard('rs_lyon/localhost:27023');" --quiet

Write-Host "`n[OK] Cluster sharde entierement mis en place et operationnel sur localhost:27024 !" -ForegroundColor Green
exit 0