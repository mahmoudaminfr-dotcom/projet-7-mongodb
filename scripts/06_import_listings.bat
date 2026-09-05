@echo off
setlocal enabledelayedexpansion

set DATA_FILE=data\listings_all.csv

if not exist "%DATA_FILE%" (
    echo [ERREUR] Le fichier %DATA_FILE% n'existe pas.
    echo Veuillez d'abord executer : python fusion_villes.py
    exit /b 1
)

echo Ingestion des donnees dans MongoDB (port 27024)...
mongoimport --port 27024 --db noscites --collection listings --type csv --headerline --drop --file "%DATA_FILE%"

if errorlevel 1 (
    echo [ERREUR] L'importation des donnees a echoue.
    exit /b 1
)

echo [OK] Importation batch terminee avec succes.
exit /b 0