import pandas as pd

path_paris = r"data\listings_Paris.csv"
path_lyon = r"data\listings_Lyon.csv"
output_file = r"data\listings_all.csv"

print("Lecture des fichiers sources...")
df_paris = pd.read_csv(path_paris, low_memory=False)
df_paris["city"] = "Paris"

df_lyon = pd.read_csv(path_lyon, low_memory=False)
df_lyon["city"] = "Lyon"

print("Fusion et export...")
df_all = pd.concat([df_paris, df_lyon], ignore_index=True)
df_all.to_csv(output_file, index=False, encoding="utf-8")

print(f"Export terminé : {len(df_all)} lignes écrites dans {output_file}")
print(f"-> Paris : {len(df_paris)} | Lyon : {len(df_lyon)}")