# Projet 7 - Architecture MongoDB : Haute Disponibilité & Sharding par Zones

Ce dépôt contient l'infrastructure MongoDB déployée pour l'association **NosCités**, répondant aux exigences de haute disponibilité applicative, de scalabilité horizontale et de confinement territorial strict des données (Paris et Lyon).

---

## 1. Topologie de l'Architecture

### Environnement Haute Disponibilité (`rs0`)
* **Nœud 1 (Primary)** : `localhost:27018` — Écritures et réplication continue
* **Nœud 2 (Secondary)** : `localhost:27019` — Réplication asynchrone de l'oplog
* **Nœud 3 (Arbiter)** : `localhost:27020` — Quorum et arbitrage d'élection (aucun stockage de données métier)
* **Mécanisme validé** : Basculement automatique (*failover*) vers le port 27019 lors de l'arrêt forcé du primaire, avec réintégration transparente sans perte de données.

### Environnement Shardé Multi-Zones (`cluster`)
* **Config Database (`csrs`)** : `localhost:27021` (Replica Set stockant métadonnées et routage de chunks)
* **Shard Paris (`rs_paris`)** : `localhost:27022` — Taggé `ZONE_PARIS`
* **Shard Lyon (`rs_lyon`)** : `localhost:27023` — Taggé `ZONE_LYON`
* **Routeur Stateless (`mongos`)** : `localhost:27024` — Point d'accès unique transparent
* **Clé de Sharding Composite** : `{ city: 1, _id: 1 }` (orientation géographique stricte par `city` et cardinalité granulaire par `_id`)

---

## 2. Structure du Dépôt

```text
projet-7-mongodb/
├── scripts/
│   ├── 01_start_rs0.ps1                 # Lancement direct des 3 mongod rs0
│   ├── 02_init_rs0.js                   # Initialisation du quorum rs0
│   ├── 03_test_failover.ps1             # Simulation automatisée du crash et réélection
│   ├── 03_test_failover_rs0.js          # Commandes interactives de contrôle du failover
│   ├── 04_start_sharding_cluster.ps1    # Lancement direct csrs, shards et mongos
│   ├── 05_setup_zones.js                # Configuration du sharding et des tags de zone
│   ├── 06_import_listings.bat           # Ingestion batch unifiée via mongoimport
│   └── 07_verify_distribution.js        # Audit de conformité géographique physique
├── data/
│   └── listings_all.csv                 # Dataset unifié (105 858 lignes, ignoré par Git)
├── fusion_villes.py                     # Pipeline Python de fusion des CSV sources
├── analyse_stats.py                     # Statistiques descriptives sur le cluster (port 27024)
├── .gitignore
└── README.md
```

## 3. Prérequis et Dépendances

Système d'exploitation : Windows 10/11 avec PowerShell 5.1+

SGBD : MongoDB Server 7.x ou 8.x (mongod, mongos, mongosh, mongoimport)

Python : Python 3.10+ avec les bibliothèques d'analyse :

```
pip install pymongo polars pandas
```

## 4. Procédure d'Exécution & Évaluation Pas-à-Pas

### A. Validation de la Haute Disponibilité (rs0)

# 1. Démarrer les 3 démons mongod
```
.\scripts\01_start_rs0.ps1
```

# 2. Initialiser le Replica Set
```
mongosh "mongodb://localhost:27018" --file .\scripts\02_init_rs0.js
```

# 3. Contrôler le quorum initial
```
mongosh "mongodb://localhost:27018" --eval "rs.status().members.map(m => ({ host: m.name, state: m.stateStr }))"
```

# 4. Lancer le test de failover automatisé (crash 27018 -> élection 27019)
```
.\scripts\03_test_failover.ps1
```

# 5. Stopper les processus rs0
```
Get-Process mongod -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike "*Service*" } | Stop-Process -Force
```

### B. Déploiement du Cluster Shardé, Ingestion & Traitements Python

# 1. Créer les répertoires physiques de données
```
New-Item -ItemType Directory -Force -Path "C:\data\sharding\cfg", "C:\data\sharding\shard_paris", "C:\data\sharding\shard_lyon"
```

# 2. Démarrer les 4 processus du cluster
```
.\scripts\04_start_sharding_cluster.ps1
```

# 3. Initialiser les 3 Replica Sets sous-jacents
```
mongosh --port 27021 --eval "rs.initiate({ _id: 'csrs', configsvr: true, members: [{ _id: 0, host: 'localhost:27021' }] })"
mongosh --port 27022 --eval "rs.initiate({ _id: 'rs_paris', members: [{ _id: 0, host: 'localhost:27022' }] })"
mongosh --port 27023 --eval "rs.initiate({ _id: 'rs_lyon', members: [{ _id: 0, host: 'localhost:27023' }] })"
```

# 4. Enregistrer les shards, tags et plages de zones sur mongos
```
mongosh "mongodb://localhost:27024" --file .\scripts\05_setup_zones.js
```
# 5. Préparer les données et ingérer le dataset complet (105 858 documents)
```
python fusion_villes.py
.\scripts\06_import_listings.bat
```

# 6. Exécuter l'audit de distribution physique
```
mongosh "mongodb://localhost:27024" --file .\scripts\07_verify_distribution.js
```

# 7. Exécuter l'analyse statistique Polars sur le cluster unifié (port 27024)
```
python analyse_stats.py
```

## 5. Preuves d'Audit : Étanchéité Territoriale

Sortie officielle de 07_verify_distribution.js sur mongos:27024 :

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


6. Arrêt Propre du Banc de Test

```
Get-Process mongod, mongos -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike "*Service*" } | Stop-Process -Force
```