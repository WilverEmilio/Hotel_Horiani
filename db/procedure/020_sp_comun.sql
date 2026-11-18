-- =============================================================================
-- 020_sp_comun.sql
-- Rutinas internas compartidas por todos los stored procedures. Viven en el
-- esquema interno: la API no puede ejecutarlas, solo otros stored procedures.
--
-- Convención de errores. Todo stored procedure falla con un SQLSTATE propio
-- (clase HH) y un código legible en DETAIL. La API los traduce así:
--   HH401 -> 401  sesión inválida o usuario desactivado
--   HH403 -> 403  sin permiso (permiso u hotel)
--   HH404 -> 404  no existe, o no pertenece al cliente que lo pide
--   HH409 -> 409  conflicto (habitación ocupada, duplicado, estado no lo permite)
--   HH422 -> 422  datos inválidos o regla de negocio no cumplida
--   HH423 -> 423  cuenta bloqueada temporalmente
-- Además la API debe reintentar una vez el error 40P01 (interbloqueo).
--
-- Dirección IP para la bitácora: la API puede ejecutar, dentro de la misma
-- transacción,  SELECT set_config('horiani.ip', '<ip del cliente>', true);
-- =============================================================================

CREATE TYPE interno.tp_actor AS (
    id_usuario   BIGINT,
    rol          VARCHAR(30),
    id_cliente   BIGINT,
    id_empleado  BIGINT,
    permisos     TEXT[]
);

CREATE OR REPLACE FUNCTION interno.sp_comun_error(p_sqlstate TEXT, p_codigo TEXT, p_mensaje TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE = p_sqlstate, MESSAGE = p_mensaje, DETAIL = p_codigo;
END;
$$;
CREATE OR REPLACE FUNCTION interno.sp_comun_hoy()
RETURNS DATE
LANGUAGE sql
STABLE
AS $$
    SELECT (now() AT TIME ZONE 'America/Guatemala')::date;
$$;

CREATE OR REPLACE FUNCTION interno.sp_comun_exigir_texto(p_valor TEXT, p_campo TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_valor IS NULL OR length(btrim(p_valor)) = 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'campo_requerido', format('El campo %s es obligatorio', p_campo));
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_comun_obtener_actor(p_id_usuario BIGINT)
RETURNS interno.tp_actor
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor interno.tp_actor;
BEGIN
    SELECT u.id_usuario, r.nombre, c.id_cliente, e.id_empleado,
           ARRAY(SELECT p.codigo::text
                   FROM rol_permiso rp
                   JOIN permiso p ON p.id_permiso = rp.id_permiso
                  WHERE rp.id_rol = u.id_rol
                  ORDER BY p.codigo)
      INTO v_actor
      FROM usuario u
      JOIN rol r ON r.id_rol = u.id_rol
      LEFT JOIN cliente c ON c.id_usuario = u.id_usuario AND c.activo
      LEFT JOIN empleado e ON e.id_usuario = u.id_usuario AND e.activo
     WHERE u.id_usuario = p_id_usuario
       AND u.activo;

    IF v_actor.id_usuario IS NULL THEN
        PERFORM interno.sp_comun_error('HH401', 'sesion_invalida',
            'La sesión no es válida o el usuario está desactivado');
    END IF;
    RETURN v_actor;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_comun_tiene_permiso(p_actor interno.tp_actor, p_permiso TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_permiso = ANY (p_actor.permisos);
$$;

CREATE OR REPLACE FUNCTION interno.sp_comun_exigir_permiso(p_actor interno.tp_actor, VARIADIC p_permisos TEXT[])
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT (p_actor.permisos && p_permisos) THEN
        PERFORM interno.sp_comun_error('HH403', 'sin_permiso', 'No tiene permiso para esta acción');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_comun_exigir_hotel(p_actor interno.tp_actor, p_id_hotel BIGINT)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_actor.rol = 'administrador' THEN
        RETURN;
    END IF;
    IF p_actor.id_empleado IS NULL OR NOT EXISTS (
        SELECT 1 FROM empleado_hotel eh
         WHERE eh.id_empleado = p_actor.id_empleado AND eh.id_hotel = p_id_hotel) THEN
        PERFORM interno.sp_comun_error('HH403', 'hotel_no_permitido', 'No tiene acceso a este hotel');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_comun_validar_paginacion(p_pagina INTEGER, p_tamano INTEGER)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_pagina IS NULL OR p_pagina < 1 OR p_tamano IS NULL OR p_tamano < 1 OR p_tamano > 100 THEN
        PERFORM interno.sp_comun_error('HH422', 'paginacion_invalida',
            'La página debe ser 1 o mayor y el tamaño de página entre 1 y 100');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_comun_validar_direccion(p_direccion TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_direccion IS NULL OR p_direccion NOT IN ('asc', 'desc') THEN
        PERFORM interno.sp_comun_error('HH422', 'direccion_invalida', 'La dirección de orden debe ser asc o desc');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_comun_registrar_bitacora(
    p_id_usuario      BIGINT,
    p_id_hotel        BIGINT,
    p_modulo          TEXT,
    p_entidad         TEXT,
    p_id_registro     TEXT,
    p_accion          TEXT,
    p_valor_anterior  JSONB,
    p_valor_nuevo     JSONB)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ip INET;
BEGIN
    BEGIN
        v_ip := NULLIF(current_setting('horiani.ip', true), '')::inet;
    EXCEPTION WHEN invalid_text_representation THEN
        v_ip := NULL;
    END;

    INSERT INTO bitacora (id_usuario, id_hotel, modulo, entidad, id_registro, accion,
                          valor_anterior, valor_nuevo, direccion_ip)
    VALUES (p_id_usuario, p_id_hotel, p_modulo, p_entidad, p_id_registro, p_accion,
            p_valor_anterior, p_valor_nuevo, v_ip);
END;
$$;

INSERT INTO version_esquema (script) VALUES ('020_sp_comun.sql');