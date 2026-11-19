-- =============================================================================
-- 025_sp_estancia.sql
-- Check-in, check-out y no presentado (RN-03.5, RN-03.11, RN-09.1).
-- Check-in a cualquier hora del día de llegada; check-out a las 11:00
-- (hotel_configuracion.hora_checkout, solo informativo: el sistema no
-- bloquea un check-out tardío).
-- =============================================================================

CREATE OR REPLACE FUNCTION sp_reservaciones_hacer_checkin(p_id_usuario_actor BIGINT, p_id_reservacion BIGINT)
RETURNS TABLE (id_reservacion BIGINT, estado VARCHAR, habitaciones TEXT, saldo DECIMAL(10,2))
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor       interno.tp_actor;
    v_id_hotel    BIGINT;
    v_res         reservacion%ROWTYPE;
    v_hoy         DATE;
    v_no_listas   TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVACIONES_GESTIONAR');
    v_id_hotel := interno.sp_reservaciones_exigir_acceso(v_actor, p_id_reservacion);
    v_hoy := interno.sp_comun_hoy();

    SELECT r.* INTO v_res FROM reservacion r WHERE r.id_reservacion = p_id_reservacion FOR UPDATE;
    IF v_res.estado <> 'confirmada' THEN
        PERFORM interno.sp_comun_error('HH409', 'checkin_no_permitido',
            'Solo se hace check-in de reservaciones confirmadas (con anticipo pagado)');
    END IF;
    IF v_hoy < v_res.fecha_entrada THEN
        PERFORM interno.sp_comun_error('HH409', 'checkin_anticipado',
            format('El check-in de esta reservación es a partir del %s', to_char(v_res.fecha_entrada, 'DD/MM/YYYY')));
    END IF;
    IF v_hoy >= v_res.fecha_salida THEN
        PERFORM interno.sp_comun_error('HH409', 'checkin_vencido', 'La fecha de salida de esta reservación ya pasó');
    END IF;

    PERFORM 1 FROM habitacion h
      JOIN reservacion_habitacion rh ON rh.id_habitacion = h.id_habitacion
     WHERE rh.id_reservacion = p_id_reservacion
     ORDER BY h.id_habitacion
       FOR UPDATE OF h;

    SELECT string_agg(h.numero || ' (' || replace(h.estado, '_', ' ') || ')', ', ' ORDER BY h.numero)
      INTO v_no_listas
      FROM reservacion_habitacion rh
      JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
     WHERE rh.id_reservacion = p_id_reservacion
       AND h.estado <> 'disponible';
    IF v_no_listas IS NOT NULL THEN
        PERFORM interno.sp_comun_error('HH409', 'habitacion_no_lista',
            'Habitaciones que aún no están listas: ' || v_no_listas || '. Reasígnelas o espere a limpieza');
    END IF;

    UPDATE habitacion h SET estado = 'ocupada'
      FROM reservacion_habitacion rh
     WHERE rh.id_habitacion = h.id_habitacion AND rh.id_reservacion = p_id_reservacion;

    PERFORM interno.sp_reservaciones_cambiar_estado(p_id_reservacion, 'en_curso', p_id_usuario_actor, 'Check-in');

    RETURN QUERY
    SELECT p_id_reservacion, 'en_curso'::varchar,
           (SELECT string_agg(h.numero, ', ' ORDER BY h.numero) FROM reservacion_habitacion rh
              JOIN habitacion h ON h.id_habitacion = rh.id_habitacion WHERE rh.id_reservacion = p_id_reservacion),
           s.saldo
      FROM interno.sp_pagos_resumen(p_id_reservacion) s;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_hacer_checkout(p_id_usuario_actor BIGINT, p_id_reservacion BIGINT)
RETURNS TABLE (id_reservacion BIGINT, estado VARCHAR, tareas_limpieza INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_estado    VARCHAR;
    v_saldo     NUMERIC;
    v_tareas    INTEGER;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVACIONES_GESTIONAR');
    PERFORM interno.sp_reservaciones_exigir_acceso(v_actor, p_id_reservacion);

    SELECT r.estado INTO v_estado FROM reservacion r WHERE r.id_reservacion = p_id_reservacion FOR UPDATE;
    IF v_estado <> 'en_curso' THEN
        PERFORM interno.sp_comun_error('HH409', 'checkout_no_permitido',
            'Solo se hace check-out de reservaciones en curso');
    END IF;

    SELECT s.saldo INTO v_saldo FROM interno.sp_pagos_resumen(p_id_reservacion) s;
    IF v_saldo > 0 THEN
        PERFORM interno.sp_comun_error('HH409', 'saldo_pendiente',
            format('Hay un saldo pendiente de Q%s. Regístrelo antes del check-out', to_char(v_saldo, 'FM999999990.00')));
    END IF;

    PERFORM 1 FROM habitacion h
      JOIN reservacion_habitacion rh ON rh.id_habitacion = h.id_habitacion
     WHERE rh.id_reservacion = p_id_reservacion
     ORDER BY h.id_habitacion
       FOR UPDATE OF h;

    UPDATE habitacion h SET estado = 'en_limpieza'
      FROM reservacion_habitacion rh
     WHERE rh.id_habitacion = h.id_habitacion AND rh.id_reservacion = p_id_reservacion
       AND h.estado = 'ocupada';

    INSERT INTO tarea_limpieza (id_habitacion, id_reservacion, creado_por)
    SELECT rh.id_habitacion, p_id_reservacion, p_id_usuario_actor
      FROM reservacion_habitacion rh
     WHERE rh.id_reservacion = p_id_reservacion
       AND NOT EXISTS (SELECT 1 FROM tarea_limpieza t
                        WHERE t.id_habitacion = rh.id_habitacion AND t.estado <> 'completada');
    GET DIAGNOSTICS v_tareas = ROW_COUNT;

    PERFORM interno.sp_reservaciones_cambiar_estado(p_id_reservacion, 'finalizada', p_id_usuario_actor, 'Check-out');

    RETURN QUERY SELECT p_id_reservacion, 'finalizada'::varchar, v_tareas;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_marcar_no_presentado(
    p_id_usuario_actor  BIGINT,
    p_id_reservacion    BIGINT,
    p_observacion       TEXT)
RETURNS TABLE (id_reservacion BIGINT, estado VARCHAR, anticipo_pagado DECIMAL(10,2), pierde_anticipo BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_id_hotel  BIGINT;
    v_res       reservacion%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVACIONES_GESTIONAR');
    v_id_hotel := interno.sp_reservaciones_exigir_acceso(v_actor, p_id_reservacion);

    SELECT r.* INTO v_res FROM reservacion r WHERE r.id_reservacion = p_id_reservacion FOR UPDATE;
    IF v_res.estado <> 'confirmada' THEN
        PERFORM interno.sp_comun_error('HH409', 'no_presentado_no_permitido',
            'Solo se marca como no presentada una reservación confirmada');
    END IF;
    IF interno.sp_comun_hoy() <= v_res.fecha_entrada THEN
        PERFORM interno.sp_comun_error('HH409', 'aun_puede_llegar',
            'El cliente todavía puede llegar hoy; márquelo a partir de mañana');
    END IF;

    PERFORM interno.sp_reservaciones_cambiar_estado(p_id_reservacion, 'no_presentado', p_id_usuario_actor,
        COALESCE(NULLIF(btrim(p_observacion), ''), 'El cliente no se presentó'));

    RETURN QUERY
    SELECT p_id_reservacion, 'no_presentado'::varchar, s.pagado,
           (SELECT hc.no_presentacion_pierde_anticipo FROM hotel_configuracion hc WHERE hc.id_hotel = v_id_hotel)
      FROM interno.sp_pagos_resumen(p_id_reservacion) s;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_reservaciones_hacer_checkin(BIGINT, BIGINT),
    sp_reservaciones_hacer_checkout(BIGINT, BIGINT),
    sp_reservaciones_marcar_no_presentado(BIGINT, BIGINT, TEXT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('025_sp_estancia.sql');