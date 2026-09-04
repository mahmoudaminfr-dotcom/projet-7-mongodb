// A executer dans mongosh sur le routeur : mongosh "mongodb://localhost:27024"
use noscites;
db.listings.getShardDistribution();
db.listings.aggregate([ { $group: { _id: "$city", total: { $sum: 1 } } } ]);
