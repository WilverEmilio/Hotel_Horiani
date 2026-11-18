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

-- Nadie, salvo el dueño de los objetos, toca tablas ni secuencias directamente.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM horiani_api;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM horiani_api;

GRANT USAGE ON SCHEMA public TO horiani_api;

-- Las rutinas que se creen a partir de aquí (scripts 020 en adelante) ya no
-- son ejecutables por cualquiera: cada script de stored procedures otorga
-- EXECUTE a horiani_api de forma explícita. Los stored procedures se crean
-- como SECURITY DEFINER para que operen sobre las tablas con los permisos del
-- dueño, sin dar acceso directo a la API.
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON ROUTINES FROM PUBLIC;
