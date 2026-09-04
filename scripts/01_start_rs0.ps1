@'
# Detection automatique du binaire mongod
$mongodPath = (Get-Command mongod -ErrorAction SilentlyContinue).Source

if (-not $mongodPath) {
    $found = Get-ChildItem -Path "C:\Program Files\MongoDB\Server" -Filter "mongod.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $mongodPath = $found.FullName
    } else {
        Write-Error "mongod.exe est introuvable. Veuillez verifier l'installation de MongoDB."
        exit 1
    }
}

Write-Host "Utilisation de : $mongodPath"

# Demarrage des 3 instances du Replica Set
Start-Process $mongodPath -ArgumentList "--port 27018 --dbpath C:\data\rs0_1 --replSet rs0"
Start-Process $mongodPath -ArgumentList "--port 27019 --dbpath C:\data\rs0_2 --replSet rs0"
Start-Process $mongodPath -ArgumentList "--port 27020 --dbpath C:\data\rs0_arb --replSet rs0"

Write-Host "Noeuds rs0 demarres sur les ports 27018, 27019 et 27020."
'@ | Out-File -FilePath ".\scripts\01_start_rs0.ps1" -Encoding utf8