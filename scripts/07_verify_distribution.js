// scripts/07_verify_distribution.js - Audit structurel, volumétrique et d'étanchéité physique par shard

const dbName = "noscites";
const collName = "listings";
const ns = `${dbName}.${collName}`;

const dbTarget = db.getSiblingDB(dbName);
const configDB = db.getSiblingDB("config");

print("\n=======================================================");
print("          AUDIT DE DISTRIBUTION DES SHARDS             ");
print("=======================================================");

// 1. Vérification de l'activation du sharding sur la collection
const collConfig = configDB.collections.findOne({ _id: ns });
if (!collConfig || collConfig.dropped) {
    throw new Error(`[ECHEC AUDIT] La collection ${ns} n'est pas shardée sur le cluster.`);
}
print(`[OK] Collection shardée détectée : clé = ${JSON.stringify(collConfig.key)}`);

// 2. Audit de la répartition physique sur les Shards
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

// 3. Audit métier de la répartition par ville globale (depuis mongos)
print("\n=======================================================");
print("          RÉPARTITION MÉTIER GLOBALE PAR VILLE         ");
print("=======================================================");

const cityAgg = dbTarget[collName].aggregate([
    { $group: { _id: "$city", total: { $sum: 1 } } },
    { $sort: { total: -1 } }
]).toArray();

printjson(cityAgg);

const countParis = (cityAgg.find(c => c._id === "Paris") || {}).total || 0;
const countLyon = (cityAgg.find(c => c._id === "Lyon") || {}).total || 0;
const totalIngested = countParis + countLyon;

// 4. Assertions strictes sur les volumes attendus (Dataset OpenClassrooms figé)
const EXPECTED_PARIS = 95885;
const EXPECTED_LYON = 9973;
const EXPECTED_TOTAL = EXPECTED_PARIS + EXPECTED_LYON; // 105 858

if (countParis !== EXPECTED_PARIS) {
    throw new Error(`[ECHEC AUDIT] Volume Paris incorrect : attendu ${EXPECTED_PARIS}, obtenu ${countParis}.`);
}
if (countLyon !== EXPECTED_LYON) {
    throw new Error(`[ECHEC AUDIT] Volume Lyon incorrect : attendu ${EXPECTED_LYON}, obtenu ${countLyon}.`);
}
if (totalIngested !== EXPECTED_TOTAL) {
    throw new Error(`[ECHEC AUDIT] Volume total incorrect : attendu ${EXPECTED_TOTAL}, obtenu ${totalIngested}.`);
}

// 5. Vérification physique stricte de l'isolation géographique par shard (Exigence du mentor)
print("\n=======================================================");
print("       VÉRIFICATION PHYSIQUE DE L'ISOLATION PAR SHARD  ");
print("=======================================================");

const shardParisDocs = shardStats["rs_paris"] ? shardStats["rs_paris"].count : 0;
const shardLyonDocs = shardStats["rs_lyon"] ? shardStats["rs_lyon"].count : 0;

if (shardParisDocs !== EXPECTED_PARIS) {
    throw new Error(`[ECHEC AUDIT] Fuite physique sur rs_paris : contient ${shardParisDocs} documents (attendu exactement ${EXPECTED_PARIS}).`);
}

if (shardLyonDocs !== EXPECTED_LYON) {
    throw new Error(`[ECHEC AUDIT] Fuite physique sur rs_lyon : contient ${shardLyonDocs} documents (attendu exactement ${EXPECTED_LYON}).`);
}

print(`[OK] Étanchéité physique validée : rs_paris (${shardParisDocs} documents Paris) | rs_lyon (${shardLyonDocs} documents Lyon).`);
print("[OK] Validation de l'isolation géographique et de l'intégrité volumétrique terminée avec succès.\n");