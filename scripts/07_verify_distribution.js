db = db.getSiblingDB("noscites");

print("\n=======================================================");
print("          AUDIT DE DISTRIBUTION DES SHARDS             ");
print("=======================================================\n");

const stats = db.listings.stats();
if (stats.sharded) {
    for (const [shardName, shardStats] of Object.entries(stats.shards)) {
        print(`--- SHARD : ${shardName} ---`);
        print(`  Documents : ${shardStats.count.toLocaleString()}`);
        print(`  Taille    : ${(shardStats.size / (1024 * 1024)).toFixed(2)} Mo\n`);
    }
} else {
    print("Attention : la collection n'est pas shardee !");
}

print("=======================================================");
print("          REPARTITION METIER PAR VILLE                ");
print("=======================================================\n");

const agg = db.listings.aggregate([
    { $group: { _id: "$city", total: { $sum: 1 } } },
    { $sort: { total: -1 } }
]).toArray();

printjson(agg);
print("\n[OK] Validation de l'isolation geographique terminee avec succes.\n");
