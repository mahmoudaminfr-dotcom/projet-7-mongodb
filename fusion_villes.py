import sys
import os
import polars as pl

# Forcer UTF-8 sur console Windows
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

path_paris = os.path.join("data", "listings_Paris.csv")
path_lyon = os.path.join("data", "listings_Lyon.csv")
output_file = os.path.join("data", "listings_all.csv")

# 1. Verification de presence des fichiers sources
for path in [path_paris, path_lyon]:
    if not os.path.exists(path):
        print(f"[ERREUR] Fichier source introuvable : {path}")
        print("Veuillez telecharger les fichiers sources et les placer dans data/ conformement au README.")
        sys.exit(1)

print("Chargement et controle des fichiers sources...")

try:
    # Fail-closed : pas de ignore_errors silencieux
    df_paris = pl.read_csv(path_paris, infer_schema_length=10000)
    df_paris = df_paris.with_columns(pl.lit("Paris").alias("city"))

    df_lyon = pl.read_csv(path_lyon, infer_schema_length=10000)
    df_lyon = df_lyon.with_columns(pl.lit("Lyon").alias("city"))

    # Controle volumetrique strict des sources
    EXPECTED_PARIS = 95885
    EXPECTED_LYON = 9973
    EXPECTED_TOTAL = EXPECTED_PARIS + EXPECTED_LYON

    if df_paris.height != EXPECTED_PARIS:
        print(f"[ERREUR] Volume Paris anormal : {df_paris.height} (attendu {EXPECTED_PARIS})")
        sys.exit(1)

    if df_lyon.height != EXPECTED_LYON:
        print(f"[ERREUR] Volume Lyon anormal : {df_lyon.height} (attendu {EXPECTED_LYON})")
        sys.exit(1)

    # Concaténation sur colonnes communes
    common_cols = [c for c in df_paris.columns if c in df_lyon.columns]
    df_all = pl.concat([df_paris.select(common_cols), df_lyon.select(common_cols)])

    if df_all.height != EXPECTED_TOTAL:
        print(f"[ERREUR] Volume total incoherent : {df_all.height} (attendu {EXPECTED_TOTAL})")
        sys.exit(1)

    print(f"Lignes Paris: {df_paris.height} | Lignes Lyon: {df_lyon.height} | Total valide: {df_all.height}")

    df_all.write_csv(output_file)
    print(f"[OK] Fichier unifie genere avec succes : {output_file} ({df_all.height} lignes)")

except Exception as e:
    print(f"[ERREUR CRITIQUE] Echec lors de la fusion : {e}")
    sys.exit(1)