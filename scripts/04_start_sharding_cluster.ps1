# 1. Config Server
Start-Process mongod -ArgumentList "--configsvr --replSet csrs --port 27021 --dbpath C:\data\sharding\cfg"

# 2. Shards Paris et Lyon
Start-Process mongod -ArgumentList "--shardsvr --replSet rs_paris --port 27022 --dbpath C:\data\sharding\shard_paris"
Start-Process mongod -ArgumentList "--shardsvr --replSet rs_lyon --port 27023 --dbpath C:\data\sharding\shard_lyon"

# 3. Routeur mongos
Start-Process mongos -ArgumentList "--configdb csrs/localhost:27021 --port 27024"

Write-Host "Cluster de sharding demarre : Config (27021), Paris (27022), Lyon (27023), mongos (27024)."
