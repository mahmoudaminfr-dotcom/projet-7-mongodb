import polars as pl
from pymongo import MongoClient

# 1. Connexion à la base locale MongoDB
client = MongoClient("mongodb://localhost:27017/")
db = client["noscites"]
collection = db["paris_listings"]

print("Extraction des données depuis MongoDB...")

# 2. Projection des colonnes cibles
projection = {
    "_id": 0,
    "id": 1,
    "room_type": 1,
    "neighbourhood_cleansed": 1,
    "host_is_superhost": 1,
    "number_of_reviews": 1,
    "availability_30": 1,
    "reviews_per_month": 1,
}

data = list(collection.find({}, projection))

# 3. Création du DataFrame Polars avec typage explicite
df = pl.DataFrame(data).with_columns(
    [
        pl.col("number_of_reviews").cast(pl.Int64, strict=False).fill_null(0),
        pl.col("availability_30").cast(pl.Float64, strict=False),
        pl.col("reviews_per_month").cast(pl.Float64, strict=False).fill_null(0.0),
        # Normalisation du statut Superhost (gère 't', 'true', True)
        pl.col("host_is_superhost")
        .cast(pl.Utf8)
        .is_in(["t", "true", "True"])
        .alias("is_superhost"),
    ]
)

# Ajout de l'estimation du taux de réservation mensuel basé sur l'occupation à 30 jours : (30 - availability_30) / 30 * 100
df = df.with_columns(
    pl.when(
        pl.col("availability_30").is_not_null()
        & (pl.col("availability_30") >= 0)
        & (pl.col("availability_30") <= 30)
    )
    .then((30.0 - pl.col("availability_30")) / 30.0 * 100.0)
    .otherwise(None)
    .alias("taux_reservation_30j_pct")
)

print("\n" + "=" * 60)
print("1. TAUX DE RÉSERVATION MOYEN PAR MOIS PAR TYPE DE LOGEMENT")
print("=" * 60)
stats_room_type = (
    df.group_by("room_type")
    .agg(
        [
            pl.count("id").alias("nb_annonces"),
            pl.col("taux_reservation_30j_pct")
            .mean()
            .round(2)
            .alias("taux_reservation_moyen_%"),
            pl.col("reviews_per_month")
            .mean()
            .round(2)
            .alias("avis_par_mois_moyen"),
        ]
    )
    .sort("nb_annonces", descending=True)
)
print(stats_room_type)

print("\n" + "=" * 60)
print("2. MÉDIANE DU NOMBRE D'AVIS POUR TOUS LES LOGEMENTS")
print("=" * 60)
mediane_avis_globale = df["number_of_reviews"].median()
print(f"Médiane globale du nombre d'avis : {mediane_avis_globale}")

print("\n" + "=" * 60)
print("3. MÉDIANE DU NOMBRE D'AVIS PAR CATÉGORIE D'HÔTE")
print("=" * 60)
stats_superhost = (
    df.group_by("is_superhost")
    .agg(
        [
            pl.count("id").alias("nb_annonces"),
            pl.col("number_of_reviews").median().alias("mediane_avis"),
            pl.col("number_of_reviews")
            .mean()
            .round(2)
            .alias("moyenne_avis"),
        ]
    )
    .sort("is_superhost", descending=True)
)
print(stats_superhost)

print("\n" + "=" * 60)
print("4. DENSITÉ DE LOGEMENTS PAR QUARTIER DE PARIS")
print("=" * 60)
densite_quartiers = (
    df.group_by("neighbourhood_cleansed")
    .agg(
        [
            pl.count("id").alias("nb_logements"),
            (pl.count("id") / df.height * 100).round(2).alias("part_%"),
        ]
    )
    .sort("nb_logements", descending=True)
)
print(densite_quartiers)

print("\n" + "=" * 60)
print("5. TOP QUARTIERS AVEC LE PLUS FORT TAUX DE RÉSERVATION PAR MOIS")
print("=" * 60)
top_quartiers_resa = (
    df.group_by("neighbourhood_cleansed")
    .agg(
        [
            pl.count("id").alias("nb_logements"),
            pl.col("taux_reservation_30j_pct")
            .mean()
            .round(2)
            .alias("taux_reservation_moyen_%"),
            pl.col("reviews_per_month")
            .mean()
            .round(2)
            .alias("avis_mensuels_moyen"),
        ]
    )
    .filter(pl.col("nb_logements") >= 100)  # Filtre pour éviter les biais sur volumes anecdotiques
    .sort("taux_reservation_moyen_%", descending=True)
)
print(top_quartiers_resa)