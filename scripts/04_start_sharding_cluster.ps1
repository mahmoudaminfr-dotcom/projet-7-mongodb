# scripts/04_start_sharding_cluster.ps1 - Orchestration ultra-robuste, nettoyage ciblé et attente active des Primary

$ErrorActionPreference = "Stop"

# 1. Détection universelle des binaires MongoDB
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

# 2. Fonction de readiness polling par socket TCP
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

# 3. Fonction d'attente active d'un nœud PRIMARY sur un Replica Set
function Wait-ReplicaSetPrimary {
    param([int]$Port, [int]$TimeoutSec = 30)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $res = mongosh --port $Port --eval "db.hello().isWritablePrimary" --quiet 2>$null
        if ($res -match "true") {
            return $true
        }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# 4. Nettoyage ciblé des processus du projet uniquement (Exigence du mentor)
Write-Host "[0/4] Arrêt ciblé des anciennes instances du projet (chemins C:\data\sharding)..." -ForegroundColor Cyan
$procs = Get-CimInstance Win32_Process -Filter "Name = 'mongod.exe' OR Name = 'mongos.exe'" -ErrorAction SilentlyContinue
foreach ($p in $procs) {
    if ($p.CommandLine -like "*C:\data\sharding*") {
        Write-Host "      Arrêt du processus PID $($p.ProcessId)..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 2

# Préparation des dossiers de données et de logs
$baseDir = "C:\data\sharding"
$logDir = "$baseDir\logs"
foreach ($d in @($baseDir, $logDir, "$baseDir\cfg", "$baseDir\shard_paris", "$baseDir\shard_lyon")) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

foreach ($sub in @("$baseDir\cfg", "$baseDir\shard_paris", "$baseDir\shard_lyon")) {
    $lockFile = Join-Path $sub "mongod.lock"
    if (Test-Path $lockFile) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
}

# 5. Démarrage Config Server (csrs) sur port 27021
Write-Host "[1/4] Démarrage Config Server (csrs) sur port 27021..." -ForegroundColor Cyan
$cfgLog = "$logDir\csrs.log"
Start-Process -FilePath $mongod -ArgumentList "--configsvr --replSet csrs --port 27021 --dbpath $baseDir\cfg --bind_ip localhost --logpath $cfgLog" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27021)) {
    Write-Error "[ECHEC] Le Config Server (port 27021) n'a pas démarré. Consultez le log : $cfgLog"
    exit 1
}

Write-Host "      Initialisation du replica set csrs..." -ForegroundColor Cyan
$initCsrs = mongosh --port 27021 --eval "try { rs.initiate({ _id: 'csrs', configsvr: true, members: [{ _id: 0, host: 'localhost:27021' }] }) } catch(e) { print(e.message); quit(1); }" --quiet
if ($LASTEXITCODE -ne 0) {
    if ($initCsrs -match "already initialized" -or $initCsrs -match "already instantiated") {
        Write-Host "      [INFO] csrs déjà initialisé." -ForegroundColor Yellow
    } else {
        Write-Error "[ECHEC CRITIQUE] Erreur lors de l'initialisation de csrs : $initCsrs"
        exit 1
    }
}

if (-not (Wait-ReplicaSetPrimary -Port 27021)) {
    Write-Error "[ECHEC] Le Config Server (27021) n'a pas élu de Primary dans le délai imparti."
    exit 1
}

# 6. Démarrage des Shards (rs_paris et rs_lyon)
Write-Host "`n[2/4] Démarrage Shards Paris (27022) et Lyon (27023)..." -ForegroundColor Cyan
Start-Process -FilePath $mongod -ArgumentList "--shardsvr --replSet rs_paris --port 27022 --dbpath $baseDir\shard_paris --bind_ip localhost --logpath $logDir\shard_paris.log" -WindowStyle Hidden
Start-Process -FilePath $mongod -ArgumentList "--shardsvr --replSet rs_lyon --port 27023 --dbpath $baseDir\shard_lyon --bind_ip localhost --logpath $logDir\shard_lyon.log" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27022) -or -not (Wait-MongoPort -Port 27023)) {
    Write-Error "[ECHEC] L'un des shards n'a pas démarré à temps."
    exit 1
}

Write-Host "      Initialisation des replica sets des shards..." -ForegroundColor Cyan
$initParis = mongosh --port 27022 --eval "try { rs.initiate({ _id: 'rs_paris', members: [{ _id: 0, host: 'localhost:27022' }] }) } catch(e) { print(e.message); quit(1); }" --quiet
if ($LASTEXITCODE -ne 0 -and $initParis -notmatch "already initialized") {
    Write-Error "[ECHEC CRITIQUE] Erreur initialisation rs_paris : $initParis"
    exit 1
}

$initLyon = mongosh --port 27023 --eval "try { rs.initiate({ _id: 'rs_lyon', members: [{ _id: 0, host: 'localhost:27023' }] }) } catch(e) { print(e.message); quit(1); }" --quiet
if ($LASTEXITCODE -ne 0 -and $initLyon -notmatch "already initialized") {
    Write-Error "[ECHEC CRITIQUE] Erreur initialisation rs_lyon : $initLyon"
    exit 1
}

if (-not (Wait-ReplicaSetPrimary -Port 27022) -or -not (Wait-ReplicaSetPrimary -Port 27023)) {
    Write-Error "[ECHEC] L'un des shards n'a pas élu son Primary à temps."
    exit 1
}

# 7. Démarrage du Routeur mongos
Write-Host "`n[3/4] Démarrage Routeur mongos sur port 27024..." -ForegroundColor Cyan
Start-Process -FilePath $mongos -ArgumentList "--configdb csrs/localhost:27021 --port 27024 --bind_ip localhost --logpath $logDir\mongos.log" -WindowStyle Hidden

if (-not (Wait-MongoPort -Port 27024)) {
    Write-Error "[ECHEC] mongos (port 27024) n'a pas démarré à temps."
    exit 1
}

# 8. Enregistrement strict et contrôlé des shards auprès du routeur mongos
Write-Host "`n[4/4] Enregistrement contrôlé des shards auprès du routeur mongos..." -ForegroundColor Cyan
Start-Sleep -Seconds 2

$addParis = mongosh --port 27024 --eval "try { sh.addShard('rs_paris/localhost:27022'); } catch(e) { print(e.message); quit(1); }" --quiet
if ($LASTEXITCODE -ne 0 -and $addParis -notmatch "already exists" -or $addParis -match "error") {
    # On valide si le shard est déjà ajouté ou s'il y a une vraie erreur
    $checkShard = mongosh --port 27024 --eval "printjson(db.getSiblingDB('config').shards.findOne({_id: 'rs_paris'}))" --quiet
    if (-not $checkShard -match "rs_paris") {
        Write-Error "[ECHEC CRITIQUE] Impossible d'ajouter le shard rs_paris : $addParis"
        exit 1
    }
}

$addLyon = mongosh --port 27024 --eval "try { sh.addShard('rs_lyon/localhost:27023'); } catch(e) { print(e.message); quit(1); }" --quiet
if ($LASTEXITCODE -ne 0 -and $addLyon -notmatch "already exists") {
    $checkShardLyon = mongosh --port 27024 --eval "printjson(db.getSiblingDB('config').shards.findOne({_id: 'rs_lyon'}))" --quiet
    if (-not $checkShardLyon -match "rs_lyon") {
        Write-Error "[ECHEC CRITIQUE] Impossible d'ajouter le shard rs_lyon : $addLyon"
        exit 1
    }
}

Write-Host "`n[OK] Cluster shardé entièrement mis en place, validé et opérationnel sur localhost:27024 !" -ForegroundColor Green
exit 0