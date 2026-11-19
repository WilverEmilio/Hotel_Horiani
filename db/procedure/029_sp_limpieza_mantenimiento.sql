-- =============================================================================
-- 029_sp_limpieza_mantenimiento.sql
-- Tareas de limpieza, reportes de daños y bloqueos por mantenimiento (RN-09).
--
-- Limpieza: el check-out crea la tarea y deja la habitación 'en_limpieza'.
-- La habitación vuelve a 'disponible' solo cuando limpieza completa la tarea.
--
-- Mantenimiento: un bloqueo saca una habitación de la venta por fechas.
-- Bloquear y reservar se serializan con el mismo candado (la fila de la
-- habitación), así que nunca se cruzan una reservación y un bloqueo.
-- =============================================================================
CREATE OR REPLACE FUNCTION interno.sp_mantenimiento_estado_libre(p_id_habitacion BIGINT)
RETURNS VARCHAR
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM bloqueo_habitacion b
                              WHERE b.id_habitacion = p_id_habitacion AND b.activo
                                AND b.periodo @> interno.sp_comun_hoy())
                THEN 'en_mantenimiento' ELSE 'disponible' END::varchar;
$$;

CREATE OR REPLACE FUNCTION interno.sp_limpieza_tarea(p_actor interno.tp_actor, p_id_tarea BIGINT)
RETURNS tarea_limpieza
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_tarea     tarea_limpieza%ROWTYPE;
    v_id_hotel  BIGINT;
BEGIN
    SELECT t.* INTO v_tarea FROM tarea_limpieza t WHERE t.id_tarea_limpieza = p_id_tarea FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'tarea_no_encontrada', 'Tarea de limpieza no encontrada');
    END IF;
    SELECT h.id_hotel INTO v_id_hotel FROM habitacion h WHERE h.id_habitacion = v_tarea.id_habitacion;
    PERFORM interno.sp_comun_exigir_hotel(p_actor, v_id_hotel);
    RETURN v_tarea;
END;
$$;

CREATE OR REPLACE FUNCTION sp_limpieza_crear_tarea(
    p_id_usuario_actor  BIGINT,
    p_id_habitacion     BIGINT,
    p_observacion       TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor    interno.tp_actor;
    v_hab      habitacion%ROWTYPE;
    v_id       BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_ESTADO', 'LIMPIEZA_GESTIONAR');

    SELECT h.* INTO v_hab FROM habitacion h WHERE h.id_habitacion = p_id_habitacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'habitacion_no_encontrada', 'Habitación no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_hab.id_hotel);
    IF v_hab.estado IN ('en_mantenimiento', 'fuera_de_servicio') THEN
        PERFORM interno.sp_comun_error('HH409', 'habitacion_en_mantenimiento',
            'La habitación está en mantenimiento o fuera de servicio');
    END IF;

    INSERT INTO tarea_limpieza (id_habitacion, observacion, creado_por)
    VALUES (p_id_habitacion, NULLIF(btrim(p_observacion), ''), p_id_usuario_actor)
    RETURNING id_tarea_limpieza INTO v_id;

    IF v_hab.estado = 'disponible' THEN
        UPDATE habitacion h SET estado = 'en_limpieza' WHERE h.id_habitacion = p_id_habitacion;
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_hab.id_hotel, 'limpieza', 'tarea_limpieza',
        v_id::text, 'crear', NULL, jsonb_build_object('habitacion', v_hab.numero, 'observacion', p_observacion));
    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'tarea_abierta', 'Esa habitación ya tiene una tarea de limpieza abierta');
END;
$$;

CREATE OR REPLACE FUNCTION sp_limpieza_asignar_tarea(
    p_id_usuario_actor  BIGINT,
    p_id_tarea          BIGINT,
    p_id_empleado       BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_tarea     tarea_limpieza%ROWTYPE;
    v_id_hotel  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_ESTADO');
    v_tarea := interno.sp_limpieza_tarea(v_actor, p_id_tarea);
    IF v_tarea.estado = 'completada' THEN
        PERFORM interno.sp_comun_error('HH409', 'tarea_completada', 'La tarea ya está completada');
    END IF;

    SELECT h.id_hotel INTO v_id_hotel FROM habitacion h WHERE h.id_habitacion = v_tarea.id_habitacion;
    IF NOT EXISTS (SELECT 1 FROM empleado e JOIN empleado_hotel eh ON eh.id_empleado = e.id_empleado
                    WHERE e.id_empleado = p_id_empleado AND e.activo AND eh.id_hotel = v_id_hotel AND eh.activo) THEN
        PERFORM interno.sp_comun_error('HH422', 'empleado_invalido', 'El empleado no está activo en este hotel');
    END IF;

    UPDATE tarea_limpieza t SET id_empleado_asignado = p_id_empleado WHERE t.id_tarea_limpieza = p_id_tarea;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'limpieza', 'tarea_limpieza',
        p_id_tarea::text, 'modificar', jsonb_build_object('id_empleado_asignado', v_tarea.id_empleado_asignado),
        jsonb_build_object('id_empleado_asignado', p_id_empleado));
END;
$$;

CREATE OR REPLACE FUNCTION sp_limpieza_tomar_tarea(p_id_usuario_actor BIGINT, p_id_tarea BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  interno.tp_actor;
    v_tarea  tarea_limpieza%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'LIMPIEZA_GESTIONAR');
    IF v_actor.id_empleado IS NULL THEN
        PERFORM interno.sp_comun_error('HH403', 'sin_ficha_empleado', 'Su usuario no está ligado a un empleado');
    END IF;
    v_tarea := interno.sp_limpieza_tarea(v_actor, p_id_tarea);

    IF v_tarea.estado <> 'pendiente' THEN
        PERFORM interno.sp_comun_error('HH409', 'tarea_no_pendiente', 'La tarea ya está en proceso o completada');
    END IF;
    IF v_tarea.id_empleado_asignado IS NOT NULL AND v_tarea.id_empleado_asignado <> v_actor.id_empleado THEN
        PERFORM interno.sp_comun_error('HH409', 'tarea_de_otro', 'La tarea está asignada a otra persona');
    END IF;

    UPDATE tarea_limpieza t SET id_empleado_asignado = v_actor.id_empleado, estado = 'en_proceso'
     WHERE t.id_tarea_limpieza = p_id_tarea;
END;
$$;

CREATE OR REPLACE FUNCTION sp_limpieza_completar_tarea(
    p_id_usuario_actor  BIGINT,
    p_id_tarea          BIGINT,
    p_observacion       TEXT)
RETURNS TABLE (id_habitacion BIGINT, numero VARCHAR, estado_habitacion VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor   interno.tp_actor;
    v_tarea   tarea_limpieza%ROWTYPE;
    v_hab     habitacion%ROWTYPE;
    v_nuevo   VARCHAR;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'LIMPIEZA_GESTIONAR');
    v_tarea := interno.sp_limpieza_tarea(v_actor, p_id_tarea);
    IF v_tarea.estado = 'completada' THEN
        PERFORM interno.sp_comun_error('HH409', 'tarea_completada', 'La tarea ya está completada');
    END IF;
    IF v_actor.rol <> 'administrador' AND v_tarea.id_empleado_asignado IS NOT NULL
       AND v_tarea.id_empleado_asignado IS DISTINCT FROM v_actor.id_empleado THEN
        PERFORM interno.sp_comun_error('HH409', 'tarea_de_otro', 'La tarea está asignada a otra persona');
    END IF;

    SELECT h.* INTO v_hab FROM habitacion h WHERE h.id_habitacion = v_tarea.id_habitacion FOR UPDATE;

    UPDATE tarea_limpieza t
       SET estado = 'completada', completada_por = p_id_usuario_actor, completada_en = now(),
           id_empleado_asignado = COALESCE(t.id_empleado_asignado, v_actor.id_empleado),
           observacion = COALESCE(NULLIF(btrim(p_observacion), ''), t.observacion)
     WHERE t.id_tarea_limpieza = p_id_tarea;

    v_nuevo := v_hab.estado;
    IF v_hab.estado = 'en_limpieza' THEN
        v_nuevo := interno.sp_mantenimiento_estado_libre(v_hab.id_habitacion);
        UPDATE habitacion h SET estado = v_nuevo WHERE h.id_habitacion = v_hab.id_habitacion;
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_hab.id_hotel, 'limpieza', 'tarea_limpieza',
        p_id_tarea::text, 'cambio_estado', jsonb_build_object('estado', v_tarea.estado, 'habitacion', v_hab.estado),
        jsonb_build_object('estado', 'completada', 'habitacion', v_nuevo));

    RETURN QUERY SELECT v_hab.id_habitacion, v_hab.numero, v_nuevo;
END;
$$;

CREATE OR REPLACE FUNCTION sp_limpieza_listar_tareas(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_estado            TEXT,
    p_solo_mias         BOOLEAN,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_tarea_limpieza  BIGINT,
    id_habitacion      BIGINT,
    habitacion         VARCHAR,
    estado_habitacion  VARCHAR,
    estado             VARCHAR,
    asignada_a         TEXT,
    observacion        VARCHAR,
    proxima_llegada    DATE,
    creado_en          TIMESTAMPTZ,
    completada_en      TIMESTAMPTZ,
    total_registros    BIGINT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor  interno.tp_actor;
    v_hoy    DATE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'LIMPIEZA_GESTIONAR', 'HABITACIONES_VER');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    v_hoy := interno.sp_comun_hoy();

    RETURN QUERY
    SELECT t.id_tarea_limpieza, h.id_habitacion, h.numero, h.estado, t.estado,
           e.nombres || ' ' || e.apellidos, t.observacion,
           (SELECT min(lower(rh.periodo)) FROM reservacion_habitacion rh
             WHERE rh.id_habitacion = h.id_habitacion AND rh.activa AND lower(rh.periodo) >= v_hoy),
           t.creado_en, t.completada_en, count(*) OVER ()
      FROM tarea_limpieza t
      JOIN habitacion h ON h.id_habitacion = t.id_habitacion
      LEFT JOIN empleado e ON e.id_empleado = t.id_empleado_asignado
     WHERE h.id_hotel = p_id_hotel
       AND (p_estado IS NULL OR t.estado = p_estado)
       AND (NOT COALESCE(p_solo_mias, FALSE) OR t.id_empleado_asignado = v_actor.id_empleado)
     ORDER BY (t.estado = 'completada'), 8 NULLS LAST, t.creado_en, t.id_tarea_limpieza
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_mantenimiento_reportar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_id_habitacion     BIGINT,
    p_descripcion       TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  interno.tp_actor;
    v_id     BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'MANTENIMIENTO_REPORTAR', 'MANTENIMIENTO_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_exigir_texto(p_descripcion, 'descripción');

    INSERT INTO reporte_mantenimiento (id_hotel, id_habitacion, descripcion, reportado_por)
    VALUES (p_id_hotel, p_id_habitacion, btrim(p_descripcion), p_id_usuario_actor)
    RETURNING id_reporte_mantenimiento INTO v_id;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'mantenimiento',
        'reporte_mantenimiento', v_id::text, 'crear', NULL,
        jsonb_build_object('id_habitacion', p_id_habitacion, 'descripcion', btrim(p_descripcion)));
    RETURN v_id;
EXCEPTION
    WHEN foreign_key_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'habitacion_invalida', 'La habitación no es de este hotel');
END;
$$;

CREATE OR REPLACE FUNCTION sp_mantenimiento_cambiar_estado(
    p_id_usuario_actor  BIGINT,
    p_id_reporte        BIGINT,
    p_estado            TEXT,
    p_solucion          TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor    interno.tp_actor;
    v_rep      reporte_mantenimiento%ROWTYPE;
    v_hoy      DATE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'MANTENIMIENTO_GESTIONAR');

    SELECT r.* INTO v_rep FROM reporte_mantenimiento r WHERE r.id_reporte_mantenimiento = p_id_reporte FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'reporte_no_encontrado', 'Reporte no encontrado');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_rep.id_hotel);

    IF NOT ((v_rep.estado = 'reportado' AND p_estado IN ('en_proceso', 'resuelto'))
            OR (v_rep.estado = 'en_proceso' AND p_estado = 'resuelto')) THEN
        PERFORM interno.sp_comun_error('HH409', 'transicion_no_permitida',
            format('Un reporte %s no puede pasar a %s', v_rep.estado, COALESCE(p_estado, '(vacío)')));
    END IF;
    IF p_estado = 'resuelto' THEN
        PERFORM interno.sp_comun_exigir_texto(p_solucion, 'solución');
    END IF;

    UPDATE reporte_mantenimiento r
       SET estado = p_estado,
           solucion = CASE WHEN p_estado = 'resuelto' THEN btrim(p_solucion) ELSE r.solucion END,
           resuelto_por = CASE WHEN p_estado = 'resuelto' THEN p_id_usuario_actor END,
           resuelto_en = CASE WHEN p_estado = 'resuelto' THEN now() END
     WHERE r.id_reporte_mantenimiento = p_id_reporte;

    IF p_estado = 'resuelto' THEN
        v_hoy := interno.sp_comun_hoy();
        IF v_rep.id_habitacion IS NOT NULL THEN
            PERFORM 1 FROM habitacion h WHERE h.id_habitacion = v_rep.id_habitacion FOR UPDATE;
        END IF;
        UPDATE bloqueo_habitacion b SET activo = FALSE
         WHERE b.id_reporte_mantenimiento = p_id_reporte AND b.activo AND lower(b.periodo) >= v_hoy;
        UPDATE bloqueo_habitacion b SET periodo = daterange(lower(b.periodo), v_hoy, '[)')
         WHERE b.id_reporte_mantenimiento = p_id_reporte AND b.activo
           AND lower(b.periodo) < v_hoy AND (upper_inf(b.periodo) OR upper(b.periodo) > v_hoy);
        IF v_rep.id_habitacion IS NOT NULL THEN
            UPDATE habitacion h SET estado = interno.sp_mantenimiento_estado_libre(h.id_habitacion)
             WHERE h.id_habitacion = v_rep.id_habitacion AND h.estado = 'en_mantenimiento';
        END IF;
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_rep.id_hotel, 'mantenimiento',
        'reporte_mantenimiento', p_id_reporte::text, 'cambio_estado',
        jsonb_build_object('estado', v_rep.estado), jsonb_build_object('estado', p_estado, 'solucion', p_solucion));
END;
$$;

CREATE OR REPLACE FUNCTION sp_mantenimiento_listar_reportes(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_estado            TEXT,
    p_id_habitacion     BIGINT,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_reporte_mantenimiento  BIGINT,
    habitacion                VARCHAR,
    descripcion               TEXT,
    estado                    VARCHAR,
    reportado_por             CITEXT,
    creado_en                 TIMESTAMPTZ,
    solucion                  TEXT,
    resuelto_por              CITEXT,
    resuelto_en               TIMESTAMPTZ,
    bloqueos_activos          INTEGER,
    total_registros           BIGINT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'MANTENIMIENTO_REPORTAR', 'MANTENIMIENTO_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);

    RETURN QUERY
    SELECT r.id_reporte_mantenimiento, COALESCE(h.numero, 'Área común'), r.descripcion, r.estado,
           ur.correo, r.creado_en, r.solucion, us.correo, r.resuelto_en,
           (SELECT count(*)::int FROM bloqueo_habitacion b
             WHERE b.id_reporte_mantenimiento = r.id_reporte_mantenimiento AND b.activo),
           count(*) OVER ()
      FROM reporte_mantenimiento r
      LEFT JOIN habitacion h ON h.id_habitacion = r.id_habitacion
      JOIN usuario ur ON ur.id_usuario = r.reportado_por
      LEFT JOIN usuario us ON us.id_usuario = r.resuelto_por
     WHERE r.id_hotel = p_id_hotel
       AND (p_estado IS NULL OR r.estado = p_estado)
       AND (p_id_habitacion IS NULL OR r.id_habitacion = p_id_habitacion)
     ORDER BY (r.estado = 'resuelto'), r.creado_en DESC, r.id_reporte_mantenimiento DESC
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_mantenimiento_bloquear_habitacion(
    p_id_usuario_actor  BIGINT,
    p_id_habitacion     BIGINT,
    p_fecha_inicio      DATE,
    p_fecha_fin         DATE,
    p_motivo            TEXT,
    p_id_reporte        BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor      interno.tp_actor;
    v_hab        habitacion%ROWTYPE;
    v_periodo    DATERANGE;
    v_choques    TEXT;
    v_id         BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'MANTENIMIENTO_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_motivo, 'motivo');
    IF p_fecha_inicio IS NULL OR p_fecha_fin IS NULL OR p_fecha_fin < p_fecha_inicio THEN
        PERFORM interno.sp_comun_error('HH422', 'fechas_invalidas', 'La fecha final no puede ser anterior a la inicial');
    END IF;
    IF p_fecha_fin < interno.sp_comun_hoy() THEN
        PERFORM interno.sp_comun_error('HH422', 'fecha_pasada', 'No se bloquean fechas pasadas');
    END IF;

    SELECT h.* INTO v_hab FROM habitacion h WHERE h.id_habitacion = p_id_habitacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'habitacion_no_encontrada', 'Habitación no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_hab.id_hotel);
    IF p_id_reporte IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM reporte_mantenimiento r
         WHERE r.id_reporte_mantenimiento = p_id_reporte AND r.id_hotel = v_hab.id_hotel AND r.estado <> 'resuelto') THEN
        PERFORM interno.sp_comun_error('HH422', 'reporte_invalido', 'El reporte no existe, es de otro hotel o ya se resolvió');
    END IF;

    PERFORM sp_reservaciones_expirar_pendientes();
    v_periodo := daterange(p_fecha_inicio, p_fecha_fin + 1, '[)');

    SELECT string_agg(r.codigo || ' (' || to_char(lower(rh.periodo), 'DD/MM') || '-'
                      || to_char(upper(rh.periodo), 'DD/MM') || ')', ', ' ORDER BY lower(rh.periodo))
      INTO v_choques
      FROM reservacion_habitacion rh
      JOIN reservacion r ON r.id_reservacion = rh.id_reservacion
     WHERE rh.id_habitacion = p_id_habitacion AND rh.activa AND rh.periodo && v_periodo;
    IF v_choques IS NOT NULL THEN
        PERFORM interno.sp_comun_error('HH409', 'reservaciones_en_fechas',
            'La habitación tiene reservaciones en esas fechas: ' || v_choques || '. Reasígnelas primero');
    END IF;

    INSERT INTO bloqueo_habitacion (id_habitacion, periodo, motivo, id_reporte_mantenimiento, creado_por)
    VALUES (p_id_habitacion, v_periodo, btrim(p_motivo), p_id_reporte, p_id_usuario_actor)
    RETURNING id_bloqueo_habitacion INTO v_id;

    IF v_periodo @> interno.sp_comun_hoy() AND v_hab.estado = 'disponible' THEN
        UPDATE habitacion h SET estado = 'en_mantenimiento' WHERE h.id_habitacion = p_id_habitacion;
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_hab.id_hotel, 'mantenimiento',
        'bloqueo_habitacion', v_id::text, 'crear', NULL,
        jsonb_build_object('habitacion', v_hab.numero, 'desde', p_fecha_inicio, 'hasta', p_fecha_fin,
                           'motivo', btrim(p_motivo), 'id_reporte', p_id_reporte));
    RETURN v_id;
EXCEPTION
    WHEN exclusion_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'bloqueo_traslapado', 'Ya hay un bloqueo activo en esas fechas');
END;
$$;

CREATE OR REPLACE FUNCTION sp_mantenimiento_liberar_bloqueo(p_id_usuario_actor BIGINT, p_id_bloqueo BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  interno.tp_actor;
    v_b      bloqueo_habitacion%ROWTYPE;
    v_hab    habitacion%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'MANTENIMIENTO_GESTIONAR');

    SELECT b.* INTO v_b FROM bloqueo_habitacion b WHERE b.id_bloqueo_habitacion = p_id_bloqueo;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'bloqueo_no_encontrado', 'Bloqueo no encontrado');
    END IF;
    SELECT h.* INTO v_hab FROM habitacion h WHERE h.id_habitacion = v_b.id_habitacion FOR UPDATE;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_hab.id_hotel);
    IF NOT v_b.activo THEN
        RETURN;
    END IF;

    UPDATE bloqueo_habitacion b SET activo = FALSE WHERE b.id_bloqueo_habitacion = p_id_bloqueo;
    IF v_hab.estado = 'en_mantenimiento' THEN
        UPDATE habitacion h SET estado = interno.sp_mantenimiento_estado_libre(h.id_habitacion)
         WHERE h.id_habitacion = v_hab.id_habitacion;
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_hab.id_hotel, 'mantenimiento',
        'bloqueo_habitacion', p_id_bloqueo::text, 'desactivar', jsonb_build_object('activo', true),
        jsonb_build_object('activo', false));
END;
$$;

CREATE OR REPLACE FUNCTION sp_mantenimiento_listar_bloqueos(
    p_id_usuario_actor   BIGINT,
    p_id_hotel           BIGINT,
    p_fecha_desde        DATE,
    p_fecha_hasta        DATE,
    p_incluir_inactivos  BOOLEAN)
RETURNS TABLE (
    id_bloqueo_habitacion     BIGINT,
    id_habitacion             BIGINT,
    habitacion                VARCHAR,
    fecha_inicio              DATE,
    fecha_fin                 DATE,
    motivo                    VARCHAR,
    id_reporte_mantenimiento  BIGINT,
    activo                    BOOLEAN,
    creado_por                CITEXT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'MANTENIMIENTO_GESTIONAR', 'RESERVACIONES_GESTIONAR', 'HABITACIONES_VER');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);

    RETURN QUERY
    SELECT b.id_bloqueo_habitacion, h.id_habitacion, h.numero, lower(b.periodo), upper(b.periodo) - 1,
           b.motivo, b.id_reporte_mantenimiento, b.activo, u.correo
      FROM bloqueo_habitacion b
      JOIN habitacion h ON h.id_habitacion = b.id_habitacion
      JOIN usuario u ON u.id_usuario = b.creado_por
     WHERE h.id_hotel = p_id_hotel
       AND (b.activo OR COALESCE(p_incluir_inactivos, FALSE))
       AND b.periodo && daterange(COALESCE(p_fecha_desde, '-infinity'::date),
                                  COALESCE(p_fecha_hasta + 1, 'infinity'::date), '[)')
     ORDER BY lower(b.periodo), h.numero;
END;
$$;

CREATE OR REPLACE FUNCTION sp_mantenimiento_sincronizar_estados()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_total INTEGER;
BEGIN
    UPDATE habitacion h SET estado = 'en_mantenimiento'
     WHERE h.estado = 'disponible' AND h.activo
       AND EXISTS (SELECT 1 FROM bloqueo_habitacion b
                    WHERE b.id_habitacion = h.id_habitacion AND b.activo
                      AND b.periodo @> interno.sp_comun_hoy());
    GET DIAGNOSTICS v_total = ROW_COUNT;
    RETURN v_total;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_limpieza_crear_tarea(BIGINT, BIGINT, TEXT),
    sp_limpieza_asignar_tarea(BIGINT, BIGINT, BIGINT),
    sp_limpieza_tomar_tarea(BIGINT, BIGINT),
    sp_limpieza_completar_tarea(BIGINT, BIGINT, TEXT),
    sp_limpieza_listar_tareas(BIGINT, BIGINT, TEXT, BOOLEAN, INTEGER, INTEGER),
    sp_mantenimiento_reportar(BIGINT, BIGINT, BIGINT, TEXT),
    sp_mantenimiento_cambiar_estado(BIGINT, BIGINT, TEXT, TEXT),
    sp_mantenimiento_listar_reportes(BIGINT, BIGINT, TEXT, BIGINT, INTEGER, INTEGER),
    sp_mantenimiento_bloquear_habitacion(BIGINT, BIGINT, DATE, DATE, TEXT, BIGINT),
    sp_mantenimiento_liberar_bloqueo(BIGINT, BIGINT),
    sp_mantenimiento_listar_bloqueos(BIGINT, BIGINT, DATE, DATE, BOOLEAN),
    sp_mantenimiento_sincronizar_estados()
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('029_sp_limpieza_mantenimiento.sql');