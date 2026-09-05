// scripts/07_verify_distribution.js - Audit strict de distribution et d'isolation geographique

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

// 3. Audit metier de la repartition par ville
print("\n=======================================================");
print("          REPARTITION METIER PAR VILLE                 ");
print("=======================================================");

const cityAgg = dbTarget[collName].aggregate([
    { $group: { _id: "$city", total: { $sum: 1 } } },
    { $sort: { total: -1 } }
]).toArray();

printjson(cityAgg);

// 4. Assertions strictes sur les volumes et le confinement geographique
const EXPECTED_PARIS = 95885;
const EXPECTED_LYON = 9973;
const EXPECTED_TOTAL = EXPECTED_PARIS + EXPECTED_LYON; // 105 858

const parisDoc = cityAgg.find(c => c._id === "Paris");
const lyonDoc = cityAgg.find(c => c._id === "Lyon");

const countParis = parisDoc ? parisDoc.total : 0;
const countLyon = lyonDoc ? lyonDoc.total : 0;
const totalIngested = countParis + countLyon;

// Assertion Volume Total
if (totalIngested !== EXPECTED_TOTAL) {
    throw new Error(`[ECHEC AUDIT] Volume total incorrect : attendu ${EXPECTED_TOTAL}, obtenu ${totalIngested}.`);
}

// Assertion Isolation Paris
if (countParis !== EXPECTED_PARIS) {
    throw new Error(`[ECHEC AUDIT] Repartition Paris non conforme : attendu ${EXPECTED_PARIS}, obtenu ${countParis}.`);
}

// Assertion Isolation Lyon
if (countLyon !== EXPECTED_LYON) {
    throw new Error(`[ECHEC AUDIT] Repartition Lyon non conforme : attendu ${EXPECTED_LYON}, obtenu ${countLyon}.`);
}

// Assertion Placement Physique sur les Shards
const shardParisDocs = shardStats["rs_paris"] ? shardStats["rs_paris"].count : 0;
const shardLyonDocs = shardStats["rs_lyon"] ? shardStats["rs_lyon"].count : 0;

if (shardParisDocs !== EXPECTED_PARIS || shardLyonDocs !== EXPECTED_LYON) {
    throw new Error(`[ECHEC AUDIT] Etancheite physique violee : rs_paris a ${shardParisDocs} (attendu ${EXPECTED_PARIS}), rs_lyon a ${shardLyonDocs} (attendu ${EXPECTED_LYON}).`);
}

print("\n[OK] Validation de l'isolation geographique et de l'integrite volumetrique terminee avec succes.\n");