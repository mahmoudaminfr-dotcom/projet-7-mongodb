# scripts/03_test_failover.ps1 - Test automatise et defensif du failover rs0

Write-Host "=== 1. VERIFICATION DE L'ETAT INITIAL DU REPLICA SET ===" -ForegroundColor Cyan
mongosh "mongodb://localhost:27018" --eval "rs.status().members.map(m => ({ name: m.name, stateStr: m.stateStr }))" --quiet

# Verifier dynamiquement que le port 27018 est bien le PRIMARY actuel
$is27018Primary = (mongosh "mongodb://localhost:27018" --eval "db.hello().isWritablePrimary" --quiet 2>$null).Trim()
if ($is27018Primary -ne "true") {
    Write-Error "[ECHEC PRE-CONDITION] Le port 27018 n'est pas le noeud PRIMAIRE actuel. Verifiez l'etat initial de rs0."
    exit 1
}

Write-Host "`n=== 2. SIMULATION DU CRASH DU PRIMAIRE ACTUEL (PORT 27018) ===" -ForegroundColor Yellow
mongosh "mongodb://localhost:27018/admin" --eval "db.shutdownServer({ force: true })" --quiet 2>$null
Write-Host "Port 27018 arrete proprement."

Write-Host "`n=== 3. ATTENTE ACTIVE DE L'ELECTION DU NOUVEAU PRIMAIRE (PORT 27019) ===" -ForegroundColor Cyan

# Boucle active de detection de la re-election avec timeout (15 secondes max)
$timeoutSec = 15
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$newPrimaryFound = $false

while ($sw.Elapsed.TotalSeconds -lt $timeoutSec) {
    $check = (mongosh "mongodb://localhost:27019" --eval "db.hello().isWritablePrimary" --quiet 2>$null)
    if ($check -and $check.Trim() -eq "true") {
        $newPrimaryFound = $true
        break
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "`n=== 4. RESULTAT DU BASCULEMENT ===" -ForegroundColor Cyan

if ($newPrimaryFound) {
    Write-Host "[SUCCES] Basculement valide : le noeud localhost:27019 est devenu le nouveau PRIMAIRE." -ForegroundColor Green
    exit 0
} else {
    Write-Error "[ECHEC] Le failover a echoue : le noeud localhost:27019 n'est pas devenu primaire dans le delai imparti."
    exit 1
}