@'
# Detection des binaires
$binDir = (Get-ChildItem -Path "C:\Program Files\MongoDB\Server" -Filter "mongod.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).DirectoryName

if (-not $binDir) {
    Write-Error "Dossier bin de MongoDB introuvable."
    exit 1
}

$mongod = Join-Path $binDir "mongod.exe"
$mongos = Join-Path $binDir "mongos.exe"

# 1. Config Server
Start-Process $mongod -ArgumentList "--configsvr --replSet csrs --port 27021 --dbpath C:\data\sharding\cfg"

# 2. Shards
Start-Process $mongod -ArgumentList "--shardsvr --replSet rs_paris --port 27022 --dbpath C:\data\sharding\shard_paris"
Start-Process $mongod -ArgumentList "--shardsvr --replSet rs_lyon --port 27023 --dbpath C:\data\sharding\shard_lyon"

# 3. Routeur
Start-Process $mongos -ArgumentList "--configdb csrs/localhost:27021 --port 27024"

Write-Host "Cluster de sharding demarre : Config (27021), Paris (27022), Lyon (27023), mongos (27024)."
'@ | Out-File -FilePath ".\scripts\04_start_sharding_cluster.ps1" -Encoding utf8