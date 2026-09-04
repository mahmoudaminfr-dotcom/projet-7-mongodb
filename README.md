# Projet 7 - Architecture MongoDB : Haute Disponibilité & Sharding par Zones

Ce dépôt contient l'implémentation complète d'une infrastructure MongoDB répondant aux exigences de haute disponibilité (Replica Set avec basculement automatique) et de scalabilité horizontale avec conformité de localisation des données (Sharding multi-zones géographique).

---

## 1. Topologie de l'Architecture

### Exercice 1 & 2 : Replica Set Haute Disponibilité (rs0)
* **Nœud Primaire initial** : localhost:27018 (Data)
* **Nœud Secondaire** : localhost:27019 (Data)
* **Arbitre** : localhost:27020 (Vote uniquement, sans données)
* **Mécanisme validé** : Tolérance aux pannes avec basculement automatique du quorum vers 27019 en cas d'arrêt forcé du primaire.

### Exercice 3 : Cluster Shardé avec Rétention Géographique (Zone Sharding)
* **Config Server Replica Set (csrs)** : localhost:27021
* **Shard Paris (rs_paris)** : localhost:27022 — Taggé ZONE_PARIS
* **Shard Lyon (rs_lyon)** : localhost:27023 — Taggé ZONE_LYON
* **Routeur (mongos)** : localhost:27024
* **Clé de sharding composée** : { city: 1, _id: 1 }

---

## 2. Structure du Dépôt

```text
projet-7-mongodb/
├── scripts/
│   ├── 01_start_rs0.ps1                 # Démarrage des 3 instances mongod rs0
│   ├── 02_init_rs0.js                   # Initialisation du quorum rs0
│   ├── 03_test_failover.ps1             # Arrêt forcé et contrôle de réélection
│   ├── 04_start_sharding_cluster.ps1    # Démarrage csrs, shards et mongos
│   ├── 05_setup_zones.js                # Enregistrement shards, tags et ranges
│   ├── 06_import_listings.bat           # Ingestion batch via mongoimport
│   └── 07_verify_distribution.js        # Audit physique et logique des données
├── data/
│   └── listings_all.csv                 # Jeu de données source (ignoré par Git)
├── .gitignore
└── README.md
```

## 3. Guide de Reproduction
Les scripts intègrent la détection automatique des binaires MongoDB (mongod, mongos, mongosh, mongoimport) sur les chemins standards Windows (Program Files et AppData\Local).

## A. Test du Replica Set (rs0) et Failover
PowerShell
# 1. Lancer les 3 instances mongod
```
.\scripts\01_start_rs0.ps1
```

# 2. Initialiser le Replica Set
```
mongosh "mongodb://localhost:27018" --file .\scripts\02_init_rs0.js
```

# 3. Vérifier le quorum initial

```
mongosh "mongodb://localhost:27018" --eval "rs.status().members.map(m => ({ host: m.name, state: m.stateStr }))"
```
# 4. Tester le failover (arrêt du primaire 27018 et vérification de la réélection sur 27019)
```mongosh "mongodb://localhost:27018" --eval "db.shutdownServer({ force: true })"
Start-Sleep -Seconds 5
mongosh "mongodb://localhost:27019" --eval "db.hello().isWritablePrimary" # Renvoie true
```
# 5. Nettoyage des processus rs0
```
Get-Process mongod -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike "*Service*" } | Stop-Process -Force
```
## B. Test du Cluster Shardé et Validation Géographique
PowerShell
# 1. Préparer les répertoires physiques
```
New-Item -ItemType Directory -Force -Path "C:\data\sharding\cfg", "C:\data\sharding\shard_paris", "C:\data\sharding\shard_lyon"
```

# 2. Démarrer les 4 processus du cluster
```
.\scripts\04_start_sharding_cluster.ps1
```
# 3. Initialiser les 3 Replica Sets sous-jacents
```mongosh --port 27021 --eval "rs.initiate({ _id: 'csrs', configsvr: true, members: [{ _id: 0, host: 'localhost:27021' }] })"
mongosh --port 27022 --eval "rs.initiate({ _id: 'rs_paris', members: [{ _id: 0, host: 'localhost:27022' }] })"
mongosh --port 27023 --eval "rs.initiate({ _id: 'rs_lyon', members: [{ _id: 0, host: 'localhost:27023' }] })"
```

# 4. Configurer le sharding et les zones sur mongos
```
mongosh "mongodb://localhost:27024" --file .\scripts\05_setup_zones.js
```
# 5. Importer le jeu de données Airbnb (105 858 documents)
```
.\scripts\06_import_listings.bat
```

# 6. Exécuter l'audit de distribution
```
mongosh "mongodb://localhost:27024" --file .\scripts\07_verify_distribution.js
```

## 4. Résultats d'Audit Validés
L'exécution de 07_verify_distribution.js sur mongos produit la preuve de confinement territorial sans orphelin :

Plaintext
=======================================================
          AUDIT DE DISTRIBUTION DES SHARDS             
=======================================================

--- SHARD : rs_paris ---
  Documents : 95 885
  Taille    : 328.49 Mo

--- SHARD : rs_lyon ---
  Documents : 9 973
  Taille    : 33.33 Mo

=======================================================
          REPARTITION METIER PAR VILLE                 
=======================================================

[
  { _id: 'Paris', total: 95885 },
  { _id: 'Lyon', total: 9973 }
]

[OK] Validation de l'isolation geographique terminee avec succes.

## 5. Arrêt Propre
Pour libérer les ressources :

PowerShell
```
Get-Process mongod, mongos -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike "*Service*" } | Stop-Process -Force
```
---