// 1. Verifier le statut initial
rs.status();

// 2. Simuler la panne du primaire (depuis mongosh connecte sur le 27018)
// db.shutdownServer();

// 3. Verifier la bascule sur le secondaire (depuis mongosh connecte sur le 27019)
// rs.status(); // Verifier que localhost:27019 est devenu PRIMARY
