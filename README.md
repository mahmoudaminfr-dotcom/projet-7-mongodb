# Projet 7 - Architecture MongoDB : Haute Disponibilité & Sharding par Zones

Ce dépôt contient l'infrastructure MongoDB déployée pour l'association **NosCités**, répondant aux exigences de haute disponibilité applicative, de scalabilité horizontale et de confinement territorial strict des données (Paris et Lyon).

---

## 1. Topologie de l'Architecture

### Environnement Haute Disponibilité (`rs0`)
* **Nœud 1 (Primary)** : `localhost:27018` — Écritures et réplication continue
* **Nœud 2 (Secondary)** : `localhost:27019` — Réplication asynchrone de l'oplog
* **Nœud 3 (Arbiter)** : `localhost:27020` — Quorum et arbitrage d'élection (aucun stockage de données métier)
* **Mécanisme validé** : Basculement automatique (*failover*) défensif vers le port 27019 lors de l'arrêt forcé du primaire, avec réintégration transparente sans perte de données.

### Environnement Shardé Multi-Zones (`cluster`)
* **Config Database (`csrs`)** : `localhost:27021` (Replica Set stockant métadonnées et routage de chunks)
* **Shard Paris (`rs_paris`)** : `localhost:27022` — Taggé `ZONE_PARIS`
* **Shard Lyon (`rs_lyon`)** : `localhost:27023` — Taggé `ZONE_LYON`
* **Routeur Stateless (`mongos`)** : `localhost:27024` — Point d'accès unique transparent
* **Clé de Sharding Composite** : `{ city: 1, _id: 1 }` (orientation géographique stricte par `city` et cardinalité granulaire par `_id`)

> **Note d'architecture (Environnement de démonstration)** :  
> Dans ce banc de test local sur une machine unique, `csrs`, `rs_paris` et `rs_lyon` sont instanciés sous forme de Replica Sets mono-nœuds afin d'optimiser l'empreinte mémoire tout en validant rigoureusement les protocoles de sharding par zone. La haute disponibilité multi-nœuds avec quorum et élection automatique est démontrée séparément sur `rs0`.

---

## 2. Structure du Dépôt

```text
projet-7-mongodb/
├── scripts/
│   ├── 01_start_rs0.ps1                 # Lancement direct des 3 mongod rs0
│   ├── 02_init_rs0.js                   # Initialisation du quorum rs0
│   ├── 03_test_failover.ps1             # Simulation automatisée et defensive du failover
│   ├── 04_start_sharding_cluster.ps1    # Orchestration avec readiness polling (csrs -> shards -> mongos)
│   ├── 05_setup_zones.js                # Configuration du sharding et des tags de zone
│   ├── 06_import_listings.bat           # Ingestion batch unifiee avec --drop et gestion d'erreurs
│   └── 07_verify_distribution.js        # Audit strict d'etancheite physique et volumetrique
├── data/
│   └── listings_all.csv                 # Dataset unifie (105 858 lignes, ignore par Git)
├── fusion_villes.py                     # Pipeline Python de fusion defensive des CSV sources
├── analyse_stats.py                     # Statistiques descriptives Polars sur le cluster (port 27024)
├── requirements.txt                     # Dependances Python verrouillees
├── .gitignore
└── README.md
```

---

## 3. Prérequis et Dépendances

* **Système d'exploitation** : Windows 10/11 avec PowerShell 5.1+
* **SGBD** : MongoDB Server 7.x ou 8.x (`mongod`, `mongos`, `mongosh`, `mongoimport`)
* **Python** : Python 3.10+

### Installation de l'environnement Python

```PowerShell
pip install -r requirements.txt
```

### Données sources (OpenClassrooms)

Les fichiers bruts volumineux sont ignorés par Git (`.gitignore`). Téléchargez les datasets sources et placez-les dans le dossier `data/` :

* **Paris** : [Télécharger listings_Paris.csv](https://s3.eu-west-1.amazonaws.com/course.oc-static.com/projects/922_Data+Engineer/922_P7/listings_Paris+(1).csv)  
  * Nom attendu dans `data/` : `listings_Paris.csv`
* **Lyon** : [Télécharger listings_Lyon.csv](https://s3.eu-west-1.amazonaws.com/course.oc-static.com/projects/922_Data+Engineer/922_P7/listings_Lyon+(1).csv)  
  * Nom attendu dans `data/` : `listings_Lyon.csv`

> **Remarque :** Si le navigateur télécharge les fichiers avec le suffixe `+(1)`, retirez-le impérativement. Le script `python fusion_villes.py` les combinera ensuite automatiquement pour produire `data/listings_all.csv` (105 858 lignes), utilisé par `06_import_listings.bat`.

---

## 4. Procédure d'Exécution Pas-à-Pas

### A. Validation de la Haute Disponibilité (`rs0`)

#### 1. Démarrer les 3 démons mongod
```PowerShell
.\scripts\01_start_rs0.ps1
```

#### 2. Initialiser le Replica Set
```PowerShell
mongosh "mongodb://localhost:27018" --file .\scripts\02_init_rs0.js
```

#### 3. Contrôler le quorum initial
```PowerShell
mongosh "mongodb://localhost:27018" --eval "rs.status().members.map(m => ({ host: m.name, state: m.stateStr }))"
```

#### 4. Lancer le test de failover automatisé (crash 27018 -> élection 27019)
```PowerShell
.\scripts\03_test_failover.ps1
```

#### 5. Arrêter les processus rs0
```PowerShell
Get-Process mongod -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike "*Service*" } | Stop-Process -Force
```

---

### B. Déploiement du Cluster Shardé, Ingestion & Traitements

#### 1. Démarrer et initialiser le cluster dans l'ordre strict
```PowerShell
.\scripts\04_start_sharding_cluster.ps1
```

#### 2. Configurer le sharding et les plages de zones sur mongos
```PowerShell
mongosh "mongodb://localhost:27024" --file .\scripts\05_setup_zones.js
```

#### 3. Préparer les données et lancer l'ingestion batch
```PowerShell
python fusion_villes.py
.\scripts\06_import_listings.bat
```

#### 4. Exécuter l'audit de distribution et d'étanchéité géographique
```PowerShell
mongosh "mongodb://localhost:27024" --file .\scripts\07_verify_distribution.js
```

#### 5. Exécuter l'analyse statistique Polars sur mongos (port 27024)
```PowerShell
python analyse_stats.py
```

---

## 5. Preuves d'Audit : Étanchéité Territoriale

Sortie officielle de l'audit strict `07_verify_distribution.js` sur `mongos:27024` :

```text
=======================================================
          AUDIT DE DISTRIBUTION DES SHARDS             
=======================================================
[OK] Collection shardee detectee : cle = {"city":1,"_id":1}

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

[OK] Validation de l'isolation geographique et de l'integrite volumetrique terminee avec succes.
```

---

## 6. Arrêt et Nettoyage des Processus Locaux

```PowerShell
Get-Process mongod, mongos -ErrorAction SilentlyContinue | Where-Object { $_.Path -notlike "*Service*" } | Stop-Process -Force
```