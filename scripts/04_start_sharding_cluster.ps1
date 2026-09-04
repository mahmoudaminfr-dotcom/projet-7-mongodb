$ErrorActionPreference = "Stop"

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

$dirs = @("C:\data\sharding\cfg", "C:\data\sharding\shard_paris", "C:\data\sharding\shard_lyon")
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}

Write-Host "[1/4] Demarrage Config Server (csrs) sur port 27021..." -ForegroundColor Cyan
Start-Process -FilePath $mongod -ArgumentList "--configsvr --replSet csrs --port 27021 --dbpath C:\data\sharding\cfg --bind_ip localhost" -WindowStyle Hidden

Write-Host "[2/4] Demarrage Shard Paris (rs_paris) sur port 27022..." -ForegroundColor Cyan
Start-Process -FilePath $mongod -ArgumentList "--shardsvr --replSet rs_paris --port 27022 --dbpath C:\data\sharding\shard_paris --bind_ip localhost" -WindowStyle Hidden

Write-Host "[3/4] Demarrage Shard Lyon (rs_lyon) sur port 27023..." -ForegroundColor Cyan
Start-Process -FilePath $mongod -ArgumentList "--shardsvr --replSet rs_lyon --port 27023 --dbpath C:\data\sharding\shard_lyon --bind_ip localhost" -WindowStyle Hidden

Start-Sleep -Seconds 4

Write-Host "[4/4] Demarrage Routeur mongos sur port 27024..." -ForegroundColor Cyan
Start-Process -FilePath $mongos -ArgumentList "--configdb csrs/localhost:27021 --port 27024 --bind_ip localhost" -WindowStyle Hidden

Start-Sleep -Seconds 3
Write-Host "[OK] Tous les processus du cluster sharde sont operationnels." -ForegroundColor Green
