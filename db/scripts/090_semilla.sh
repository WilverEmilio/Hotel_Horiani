#!/usr/bin/env bash
# =============================================================================
# 090_semilla.sh
# Carga los datos de prueba SOLO si CARGAR_DATOS_PRUEBA=true (en el .env).
# En producción se deja en false y la base queda sin datos falsos.
# Las contraseñas de los usuarios de prueba las pone el script de semillas
# del backend (sp_seguridad_establecer_contrasena_inicial), porque el hash
# Argon2id se calcula en la API.
# Fuera de Docker:
#   CARGAR_DATOS_PRUEBA=true SEMILLA_DIR=./db/scripts POSTGRES_USER=... POSTGRES_DB=... bash 090_semilla.sh
# =============================================================================

if [ "${CARGAR_DATOS_PRUEBA:-false}" != "true" ]; then
    echo "090_semilla.sh: CARGAR_DATOS_PRUEBA no es true; no se cargan datos de prueba"
    exit 0
fi

ARCHIVO="${SEMILLA_DIR:-/docker-entrypoint-initdb.d}/semilla/datos_prueba.sql"
echo "090_semilla.sh: cargando $ARCHIVO"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -q -f "$ARCHIVO"