// A executer dans mongosh sur le routeur : mongosh "mongodb://localhost:27024"

// 1. Initialiser le Config Server si necessaire
// rs.initiate({ _id: "csrs", configsvr: true, members: [{ _id: 0, host: "localhost:27021" }] })

// 2. Initialiser rs_paris et rs_lyon si necessaire
// mongosh --port 27022 -> rs.initiate({ _id: "rs_paris", members: [{ _id: 0, host: "localhost:27022" }] })
// mongosh --port 27023 -> rs.initiate({ _id: "rs_lyon", members: [{ _id: 0, host: "localhost:27023" }] })

// 3. Declaration des Shards
sh.addShard("rs_paris/localhost:27022");
sh.addShard("rs_lyon/localhost:27023");

// 4. Definition des Zones
sh.addShardToZone("rs_paris", "ZONE_PARIS");
sh.addShardToZone("rs_lyon", "ZONE_LYON");

// 5. Activation du sharding et cle composite
sh.enableSharding("noscites");
sh.shardCollection("noscites.listings", { city: 1, _id: 1 });

// 6. Plages de cles des zones
sh.updateZoneKeyRange("noscites.listings", { city: "Paris", _id: MinKey }, { city: "Paris", _id: MaxKey }, "ZONE_PARIS");
sh.updateZoneKeyRange("noscites.listings", { city: "Lyon", _id: MinKey }, { city: "Lyon", _id: MaxKey }, "ZONE_LYON");
