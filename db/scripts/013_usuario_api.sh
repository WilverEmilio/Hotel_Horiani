#!/usr/bin/env bash
# =============================================================================
# 013_usuario_api.sh
# Crea el usuario con el que se conecta la API, con la contraseña del .env.
# Es un .sh y no un .sql para que la contraseña nunca quede escrita en el repo.
# Docker lo ejecuta después de 012_permisos.sql. Fuera de Docker:
#   POSTGRES_USER=... POSTGRES_DB=... API_DB_USER=... API_DB_PASSWORD=... bash 013_usuario_api.sh
# =============================================================================

if [ -z "${API_DB_USER:-}" ] || [ -z "${API_DB_PASSWORD:-}" ]; then
    echo "013_usuario_api.sh: faltan API_DB_USER o API_DB_PASSWORD" >&2
    exit 1
fi

psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v usuario="$API_DB_USER" -v clave="$API_DB_PASSWORD" <<'SQL'
-- Hereda de horiani_api: sin acceso a tablas, solo EXECUTE sobre stored procedures.
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L IN ROLE horiani_api', :'usuario', :'clave')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'usuario') \gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'usuario') \gexec
SQL
