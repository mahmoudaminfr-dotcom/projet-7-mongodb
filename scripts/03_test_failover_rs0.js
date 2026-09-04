# 03_test_failover.ps1 - Test automatise de tolérance aux pannes

Write-Host "=== 1. VERIFICATION DE L'ETAT INITIAL DU REPLICA SET ===" -ForegroundColor Cyan
mongosh "mongodb://localhost:27018" --eval "rs.status().members.map(m => ({ host: m.name, state: m.stateStr }))"

Write-Host "`n=== 2. SIMULATION DU CRASH DU PRIMAIRE (PORT 27018) ===" -ForegroundColor Yellow
mongosh "mongodb://localhost:27018" --eval "db.shutdownServer({ force: true })" -ErrorAction SilentlyContinue

Write-Host "Attente de l'election automatique (5 secondes)..."
Start-Sleep -Seconds 5

Write-Host "`n=== 3. VERIFICATION DE LA REELECTION SUR LE NOEUD 27019 ===" -ForegroundColor Green
$isPrimary = mongosh "mongodb://localhost:27019" --eval "db.hello().isWritablePrimary"
Write-Host "Statut WritablePrimary sur port 27019 : $isPrimary"

if ($isPrimary -match "true") {
    Write-Host "[SUCCES] Le failover a fonctionne : port 27019 est le nouveau PRIMARY !" -ForegroundColor Green
} else {
    Write-Warning "[ATTENTION] Le noeud 27019 n'est pas encore confirme en primaire."
}
