-- =============================================================================
-- 012_permisos.sql
-- Permisos: la API solo puede ejecutar stored procedures.
--
-- horiani_api es un rol SIN inicio de sesión y sin contraseña (no hay
-- credenciales en el repositorio). El usuario con el que se conecta la API se
-- crea aparte, con la contraseña del archivo .env, y se le asigna este rol:
--     CREATE ROLE <usuario_api> LOGIN PASSWORD '<desde .env>' IN ROLE horiani_api;
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'horiani_api') THEN
        CREATE ROLE horiani_api NOLOGIN;
    END IF;
END;
$$;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM horiani_api;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM horiani_api;

GRANT USAGE ON SCHEMA public TO horiani_api;

REVOKE ALL ON SCHEMA interno FROM PUBLIC;
REVOKE ALL ON SCHEMA interno FROM horiani_api;

ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

INSERT INTO version_esquema (script) VALUES ('012_permisos.sql');