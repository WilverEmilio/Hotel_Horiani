-- =============================================================================
-- 001_extensiones.sql
-- Hotel Horiani - Extensiones, esquema interno, control de versiones y
-- funciones comunes de trigger.
-- Ejecutar sobre una base de datos vacía, en orden numérico.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA IF NOT EXISTS interno;

CREATE TABLE version_esquema (
    id_version_esquema  INTEGER GENERATED ALWAYS AS IDENTITY,
    script              VARCHAR(100) NOT NULL,
    aplicado_en         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_version_esquema PRIMARY KEY (id_version_esquema),
    CONSTRAINT uq_version_esquema_script UNIQUE (script)
);

CREATE OR REPLACE FUNCTION tg_comun_actualizado_en()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.actualizado_en := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tg_comun_bloquear_cambios()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'La tabla % es de solo inserción: no se permite %', TG_TABLE_NAME, TG_OP
        USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE OR REPLACE FUNCTION tg_comun_no_eliminar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Los registros de % no se eliminan; deben desactivarse o cancelarse', TG_TABLE_NAME
        USING ERRCODE = 'restrict_violation';
END;
$$;

INSERT INTO version_esquema (script) VALUES ('001_extensiones.sql');