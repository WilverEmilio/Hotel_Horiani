-- =============================================================================
-- 001_extensiones.sql
-- Hotel Horiani - Extensiones y funciones comunes de trigger.
-- Ejecutar sobre una base de datos vacía, en orden numérico.
-- =============================================================================

-- citext: correos y códigos sin distinguir mayúsculas de minúsculas.
CREATE EXTENSION IF NOT EXISTS citext;

-- btree_gist: permite restricciones EXCLUDE que combinan igualdad (id) con
-- traslape de rangos de fechas. Es la base de "no dar una habitación ya reservada".
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Mantiene la columna actualizado_en en las tablas editables.
CREATE OR REPLACE FUNCTION tg_comun_actualizado_en()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.actualizado_en := now();
    RETURN NEW;
END;
$$;

-- Vuelve una tabla de solo inserción (bitácora, movimientos de inventario).
CREATE OR REPLACE FUNCTION tg_comun_bloquear_cambios()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'La tabla % es de solo inserción: no se permite %', TG_TABLE_NAME, TG_OP
        USING ERRCODE = 'restrict_violation';
END;
$$;
