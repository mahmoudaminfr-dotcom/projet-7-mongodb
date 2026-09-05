import sys
import os
import polars as pl

# Forcer UTF-8 sur Windows console
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

path_paris = os.path.join("data", "listings_Paris.csv")
path_lyon = os.path.join("data", "listings_Lyon.csv")
output_file = os.path.join("data", "listings_all.csv")

# Verification de l'existence des fichiers sources
for path in [path_paris, path_lyon]:
    if not os.path.exists(path):
        print(f"[ERREUR] Fichier source introuvable : {path}")
        print("Veuillez telecharger les fichiers sources et les placer dans data/ conformement au README.")
        sys.exit(1)

print("Chargement et fusion des fichiers sources...")

try:
    df_paris = pl.read_csv(path_paris, infer_schema_length=10000, ignore_errors=True)
    df_paris = df_paris.with_columns(pl.lit("Paris").alias("city"))

    df_lyon = pl.read_csv(path_lyon, infer_schema_length=10000, ignore_errors=True)
    df_lyon = df_lyon.with_columns(pl.lit("Lyon").alias("city"))

    # Alignement strict des schemas
    common_cols = [c for c in df_paris.columns if c in df_lyon.columns]
    df_all = pl.concat([df_paris.select(common_cols), df_lyon.select(common_cols)])

    total_rows = df_all.height
    print(f"Lignes Paris: {df_paris.height} | Lignes Lyon: {df_lyon.height} | Total: {total_rows}")

    df_all.write_csv(output_file)
    print(f"[OK] Fichier unifie genere avec succes : {output_file} ({total_rows} lignes)")

except Exception as e:
    print(f"[ERREUR] Echec lors du traitement : {e}")
    sys.exit(1)