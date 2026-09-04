// A executer dans mongosh sur le port 27018 : mongosh "mongodb://localhost:27018"
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "localhost:27018" },
    { _id: 1, host: "localhost:27019" },
    { _id: 2, host: "localhost:27020", arbiterOnly: true }
  ]
});
