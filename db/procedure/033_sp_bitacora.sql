-- =============================================================================
-- 033_sp_bitacora.sql
-- Consulta de la bitácora (RN-11). Solo con permiso BITACORA_VER
-- (administrador). La bitácora no se modifica ni se borra (triggers en 010).
-- =============================================================================

CREATE OR REPLACE FUNCTION sp_bitacora_listar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_modulo            TEXT,
    p_entidad           TEXT,
    p_id_registro       TEXT,
    p_id_usuario        BIGINT,
    p_accion            TEXT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_busqueda          TEXT,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_bitacora      BIGINT,
    fecha            TIMESTAMPTZ,
    usuario          TEXT,
    rol              VARCHAR,
    hotel            VARCHAR,
    modulo           VARCHAR,
    entidad          VARCHAR,
    id_registro      VARCHAR,
    accion           VARCHAR,
    valor_anterior   JSONB,
    valor_nuevo      JSONB,
    direccion_ip     INET,
    total_registros  BIGINT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_busqueda  TEXT := NULLIF(btrim(p_busqueda), '');
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'BITACORA_VER');
    IF p_id_hotel IS NOT NULL THEN
        PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    END IF;
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    IF p_accion IS NOT NULL AND p_accion NOT IN ('crear', 'modificar', 'desactivar', 'cambio_estado') THEN
        PERFORM interno.sp_comun_error('HH422', 'accion_invalida',
            'Acción no válida: crear, modificar, desactivar o cambio_estado');
    END IF;
    IF p_fecha_desde IS NOT NULL AND p_fecha_hasta IS NOT NULL AND p_fecha_hasta < p_fecha_desde THEN
        PERFORM interno.sp_comun_error('HH422', 'periodo_invalido', 'La fecha final no puede ser anterior a la inicial');
    END IF;

    RETURN QUERY
    SELECT b.id_bitacora, b.creado_en, COALESCE(u.correo::text, 'Sistema'), r.nombre, h.nombre,
           b.modulo, b.entidad, b.id_registro, b.accion, b.valor_anterior, b.valor_nuevo, b.direccion_ip,
           count(*) OVER ()
      FROM bitacora b
      LEFT JOIN usuario u ON u.id_usuario = b.id_usuario
      LEFT JOIN rol r ON r.id_rol = u.id_rol
      LEFT JOIN hotel h ON h.id_hotel = b.id_hotel
     WHERE (p_id_hotel IS NULL OR b.id_hotel = p_id_hotel)
       AND (p_modulo IS NULL OR b.modulo = p_modulo)
       AND (p_entidad IS NULL OR b.entidad = p_entidad)
       AND (p_id_registro IS NULL OR b.id_registro = p_id_registro)
       AND (p_id_usuario IS NULL OR b.id_usuario = p_id_usuario)
       AND (p_accion IS NULL OR b.accion = p_accion)
       AND (p_fecha_desde IS NULL OR b.creado_en >= (p_fecha_desde::timestamp AT TIME ZONE 'America/Guatemala'))
       AND (p_fecha_hasta IS NULL OR b.creado_en < ((p_fecha_hasta + 1)::timestamp AT TIME ZONE 'America/Guatemala'))
       AND (v_busqueda IS NULL
            OR b.valor_anterior::text ILIKE '%' || v_busqueda || '%'
            OR b.valor_nuevo::text ILIKE '%' || v_busqueda || '%')
     ORDER BY b.creado_en DESC, b.id_bitacora DESC
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_bitacora_historial_registro(
    p_id_usuario_actor  BIGINT,
    p_entidad           TEXT,
    p_id_registro       TEXT)
RETURNS TABLE (
    fecha           TIMESTAMPTZ,
    usuario         TEXT,
    modulo          VARCHAR,
    accion          VARCHAR,
    valor_anterior  JSONB,
    valor_nuevo     JSONB)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor interno.tp_actor;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'BITACORA_VER');
    PERFORM interno.sp_comun_exigir_texto(p_entidad, 'entidad');
    PERFORM interno.sp_comun_exigir_texto(p_id_registro, 'registro');

    RETURN QUERY
    SELECT b.creado_en, COALESCE(u.correo::text, 'Sistema'), b.modulo, b.accion, b.valor_anterior, b.valor_nuevo
      FROM bitacora b
      LEFT JOIN usuario u ON u.id_usuario = b.id_usuario
     WHERE b.entidad = p_entidad AND b.id_registro = p_id_registro
       AND (v_actor.rol = 'administrador' OR b.id_hotel IS NULL OR EXISTS (
                SELECT 1 FROM empleado_hotel eh
                 WHERE eh.id_empleado = v_actor.id_empleado AND eh.id_hotel = b.id_hotel AND eh.activo))
     ORDER BY b.creado_en, b.id_bitacora;
END;
$$;

CREATE OR REPLACE FUNCTION sp_bitacora_catalogo(p_id_usuario_actor BIGINT)
RETURNS TABLE (modulo VARCHAR, entidad VARCHAR, registros BIGINT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor interno.tp_actor;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'BITACORA_VER');

    RETURN QUERY
    SELECT b.modulo, b.entidad, count(*) FROM bitacora b GROUP BY b.modulo, b.entidad ORDER BY b.modulo, b.entidad;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_bitacora_listar(BIGINT, BIGINT, TEXT, TEXT, TEXT, BIGINT, TEXT, DATE, DATE, TEXT, INTEGER, INTEGER),
    sp_bitacora_historial_registro(BIGINT, TEXT, TEXT),
    sp_bitacora_catalogo(BIGINT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('033_sp_bitacora.sql');