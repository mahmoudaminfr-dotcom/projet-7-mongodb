# Demarrage des 3 noeuds du Replica Set rs0
Start-Process mongod -ArgumentList "--port 27018 --dbpath C:\data\rs0_1 --replSet rs0"
Start-Process mongod -ArgumentList "--port 27019 --dbpath C:\data\rs0_2 --replSet rs0"
Start-Process mongod -ArgumentList "--port 27020 --dbpath C:\data\rs0_arb --replSet rs0"
Write-Host "Noeuds rs0 demarres sur les ports 27018, 27019 et 27020."
