# Projet 7 : Architecture NoSQL Distribuée avec MongoDB

Ce dépôt contient les livrables d'architecture, scripts d'automatisation et supports de présentation pour le Projet 7.

## Contenu du dépôt
- `presentation/` : Support de soutenance (Schémas Prod & Maquette Locale, Tableaux de synthèse Réplication/Sharding).
- `scripts/` : Scripts de déploiement des Replica Sets (`rs0`), des Config Servers et du Zone Sharding Paris/Lyon (`noscites`).

## Architecture Validée
- **Haute Disponibilité** : Replica Set à 3 nœuds (`rs0`), validation du failover automatique sans perte de données.
- **Zone Sharding** : Partitionnement strict par clé composite `{ city: 1, _id: 1 }` (Paris: port 27022, Lyon: port 27023) via le routeur unifié `mongos` (port 27024).