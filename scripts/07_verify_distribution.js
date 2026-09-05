// scripts/07_verify_distribution.js - Audit structurel et strict d'etancheite geographique

const dbName = "noscites";
const collName = "listings";
const ns = `${dbName}.${collName}`;

const dbTarget = db.getSiblingDB(dbName);
const configDB = db.getSiblingDB("config");

print("\n=======================================================");
print("          AUDIT DE DISTRIBUTION DES SHARDS             ");
print("=======================================================");

// 1. Verification de l'activation du sharding sur la collection
const collConfig = configDB.collections.findOne({ _id: ns });
if (!collConfig || collConfig.dropped) {
    throw new Error(`[ECHEC AUDIT] La collection ${ns} n'est pas shardee sur le cluster.`);
}
print(`[OK] Collection shardee detectee : cle = ${JSON.stringify(collConfig.key)}`);

// 2. Audit de la repartition physique sur les Shards
const collStats = dbTarget[collName].stats();
const shardStats = collStats.shards || {};

let totalDocsOnShards = 0;
for (const shardName in shardStats) {
    const s = shardStats[shardName];
    const sizeMo = (s.size / (1024 * 1024)).toFixed(2);
    print(`\n--- SHARD : ${shardName} ---`);
    print(`  Documents : ${s.count.toLocaleString("fr-FR")}`);
    print(`  Taille    : ${sizeMo} Mo`);
    totalDocsOnShards += s.count;
}

// 3. Audit metier de la repartition par ville (depuis le routeur mongos)
print("\n=======================================================");
print("          REPARTITION METIER PAR VILLE                 ");
print("=======================================================");

const cityAgg = dbTarget[collName].aggregate([
    { $group: { _id: "$city", total: { $sum: 1 } } },
    { $sort: { total: -1 } }
]).toArray();

printjson(cityAgg);

const countParis = (cityAgg.find(c => c._id === "Paris") || {}).total || 0;
const countLyon = (cityAgg.find(c => c._id === "Lyon") || {}).total || 0;
const totalIngested = countParis + countLyon;

// 4. Verification de l'etancheite physique stricte (directement sur chaque shard)
print("\n=======================================================");
print("       VERIFICATION DE L'ISOLATION TERRITORIALE        ");
print("=======================================================");

const shardParisDocs = shardStats["rs_paris"] ? shardStats["rs_paris"].count : 0;
const shardLyonDocs = shardStats["rs_lyon"] ? shardStats["rs_lyon"].count : 0;

// Assertion 1 : Conservation des volumes totaux
if (totalDocsOnShards !== totalIngested || totalIngested === 0) {
    throw new Error(`[ECHEC AUDIT] Incoherence volumetrique : documents sur shards (${totalDocsOnShards}) != documents metier (${totalIngested}).`);
}

// Assertion 2 : Confinement strict (rs_paris ne contient QUE Paris, rs_lyon ne contient QUE Lyon)
if (shardParisDocs !== countParis) {
    throw new Error(`[ECHEC AUDIT] Fuite territoriale sur Paris : le shard rs_paris contient ${shardParisDocs} docs, attendu ${countParis}.`);
}

if (shardLyonDocs !== countLyon) {
    throw new Error(`[ECHEC AUDIT] Fuite territoriale sur Lyon : le shard rs_lyon contient ${shardLyonDocs} docs, attendu ${countLyon}.`);
}

print(`[OK] Confinement territorial valide : rs_paris (${shardParisDocs} docs) | rs_lyon (${shardLyonDocs} docs).`);
print("[OK] Validation de l'isolation geographique et de l'integrite volumetrique terminee avec succes.\n");