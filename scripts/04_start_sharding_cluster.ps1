$ErrorActionPreference = "Stop"

# 1. Detection des binaires MongoDB
$mongod = (Get-Command mongod -ErrorAction SilentlyContinue).Source
$mongos = (Get-Command mongos -ErrorAction SilentlyContinue).Source

if (-not $mongod) {
    $candidatesMongod = @(
        "$env:ProgramFiles\MongoDB\Server\8.0\bin\mongod.exe",
        "$env:ProgramFiles\MongoDB\Server\7.0\bin\mongod.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\8.0\bin\mongod.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\7.0\bin\mongod.exe"
    )
    foreach ($path in $candidatesMongod) {
        if (Test-Path $path) { $mongod = $path; break }
    }
}

if (-not $mongos) {
    $candidatesMongos = @(
        "$env:ProgramFiles\MongoDB\Server\8.0\bin\mongos.exe",
        "$env:ProgramFiles\MongoDB\Server\7.0\bin\mongos.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\8.0\bin\mongos.exe",
        "$env:LOCALAPPDATA\Programs\MongoDB\Server\7.0\bin\mongos.exe"
    )
    foreach ($path in $candidatesMongos) {
        if (Test-Path $path) { $mongos = $path; break }
    }
}

if (-not $mongod -or -not $mongos) {
    Write-Error "[ERREUR] Binaires mongod ou mongos introuvables sur la machine."
    exit 1
}

# 2. Fonction de verification active de disponibilite (readiness polling)
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

# 3. Preparation des dossiers physiques
$dirs = @("C:\data\sharding\cfg", "C:\data\sharding\shard_paris", "C:\data\sharding\shard_lyon")
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}

# 4. Demarrage et initialisation du Config Server (csrs)
Write-Host "[1/3] Demarrage Config Server (csrs) sur port 27021..." -ForegroundColor Cyan
Start-Process -FilePath $mongod -ArgumentList "--configsvr --replSet csrs --port 27021 --dbpath C:\data\sharding\cfg --bind_ip localhost" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27021)) {
    Write-Error "[ECHEC] Le Config Server (port 27021) n'a pas repondu a temps."
    exit 1
}

Write-Host "      Initialisation du replica set csrs..." -ForegroundColor Cyan
mongosh --port 27021 --eval "try { rs.initiate({ _id: 'csrs', configsvr: true, members: [{ _id: 0, host: 'localhost:27021' }] }) } catch(e) { rs.status().ok ? print('deja init') : quit(1) }" --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "[ECHEC] Erreur initialisation csrs"; exit 1 }

# 5. Demarrage et initialisation des Shards (rs_paris et rs_lyon)
Write-Host "`n[2/3] Demarrage Shards Paris (27022) et Lyon (27023)..." -ForegroundColor Cyan
Start-Process -FilePath $mongod -ArgumentList "--shardsvr --replSet rs_paris --port 27022 --dbpath C:\data\sharding\shard_paris --bind_ip localhost" -WindowStyle Hidden
Start-Process -FilePath $mongod -ArgumentList "--shardsvr --replSet rs_lyon --port 27023 --dbpath C:\data\sharding\shard_lyon --bind_ip localhost" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27022) -or -not (Wait-MongoPort -Port 27023)) {
    Write-Error "[ECHEC] L'un des shards (27022 ou 27023) n'a pas demarre a temps."
    exit 1
}

Write-Host "      Initialisation des replica sets rs_paris et rs_lyon..." -ForegroundColor Cyan
mongosh --port 27022 --eval "try { rs.initiate({ _id: 'rs_paris', members: [{ _id: 0, host: 'localhost:27022' }] }) } catch(e) { rs.status().ok ? print('deja init') : quit(1) }" --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "[ECHEC] Erreur initialisation rs_paris"; exit 1 }

mongosh --port 27023 --eval "try { rs.initiate({ _id: 'rs_lyon', members: [{ _id: 0, host: 'localhost:27023' }] }) } catch(e) { rs.status().ok ? print('deja init') : quit(1) }" --quiet
if ($LASTEXITCODE -ne 0) { Write-Error "[ECHEC] Erreur initialisation rs_lyon"; exit 1 }

# 6. Demarrage du Routeur mongos
Write-Host "`n[3/3] Demarrage Routeur mongos sur port 27024..." -ForegroundColor Cyan
Start-Process -FilePath $mongos -ArgumentList "--configdb csrs/localhost:27021 --port 27024 --bind_ip localhost" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27024)) {
    Write-Error "[ECHEC] mongos (port 27024) n'a pas demarre a temps."
    exit 1
}

Write-Host "`n[OK] Cluster sharde pret et routeur mongos operationnel sur localhost:27024." -ForegroundColor Green
exit 0