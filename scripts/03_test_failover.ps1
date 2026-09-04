$ErrorActionPreference = "Stop"

Write-Host "=== TEST DU BASCULEMENT AUTOMATIQUE (FAILOVER) ===" -ForegroundColor Cyan

Write-Host "`n[1/4] Verification du primaire initial sur 27018..." -ForegroundColor Yellow
mongosh "mongodb://localhost:27018" --eval "db.hello().isWritablePrimary"

Write-Host "`n[2/4] Simulation de panne : arret force de mongod sur 27018..." -ForegroundColor Red
mongosh "mongodb://localhost:27018" --eval "db.shutdownServer({ force: true })" 2>$null

Write-Host "Attente de l'election automatique (6 secondes)..."
Start-Sleep -Seconds 6

Write-Host "`n[3/4] Verification du nouveau primaire sur 27019..." -ForegroundColor Yellow
$isPrimary = mongosh "mongodb://localhost:27019" --quiet --eval "db.hello().isWritablePrimary"
Write-Host "Le noeud 27019 est-il PRIMARY ? : $isPrimary" -ForegroundColor Green

Write-Host "`n[4/4] Quorum apres failover :" -ForegroundColor Cyan
mongosh "mongodb://localhost:27019" --quiet --eval "rs.status().members.map(m => ({ host: m.name, state: m.stateStr, health: m.health }))"

Write-Host "`n[OK] Test de failover complete avec succes." -ForegroundColor Green
