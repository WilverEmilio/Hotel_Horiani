-- =============================================================================
-- 027_sp_empleados.sql
-- Empleados, usuarios del personal, turnos fijos y asistencia (RN-07).
-- La asistencia es solo control (no calcula pago). La registran el
-- administrador o el oficinista (permiso ASISTENCIA_REGISTRAR).
-- =============================================================================

CREATE OR REPLACE FUNCTION interno.sp_empleados_rol_personal(p_rol TEXT)
RETURNS SMALLINT
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id_rol SMALLINT;
BEGIN
    SELECT r.id_rol INTO v_id_rol FROM rol r WHERE r.nombre = lower(btrim(p_rol)) AND r.nombre <> 'cliente';
    IF v_id_rol IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'rol_invalido',
            'Rol no válido para el personal: administrador, operador, oficinista, limpieza o lavanderia');
    END IF;
    RETURN v_id_rol;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_empleados_validar_no_ultimo_admin(p_id_usuario BIGINT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_id_usuario IS NULL OR NOT EXISTS (
        SELECT 1 FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
         WHERE u.id_usuario = p_id_usuario AND r.nombre = 'administrador' AND u.activo) THEN
        RETURN;
    END IF;
    PERFORM 1 FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
     WHERE r.nombre = 'administrador' AND u.activo
       FOR UPDATE OF u;
    IF NOT EXISTS (SELECT 1 FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
                    WHERE r.nombre = 'administrador' AND u.activo AND u.id_usuario <> p_id_usuario) THEN
        PERFORM interno.sp_comun_error('HH409', 'ultimo_administrador',
            'No se puede quitar el acceso al último administrador activo');
    END IF;
END;
$$;
CREATE OR REPLACE FUNCTION interno.sp_empleados_exigir_acceso(p_actor interno.tp_actor, p_id_empleado BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id_usuario  BIGINT;
    v_id_hotel    BIGINT;
BEGIN
    SELECT e.id_usuario INTO v_id_usuario FROM empleado e WHERE e.id_empleado = p_id_empleado;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'empleado_no_encontrado', 'Empleado no encontrado');
    END IF;
    FOR v_id_hotel IN SELECT eh.id_hotel FROM empleado_hotel eh WHERE eh.id_empleado = p_id_empleado AND eh.activo LOOP
        PERFORM interno.sp_comun_exigir_hotel(p_actor, v_id_hotel);
    END LOOP;
    RETURN v_id_usuario;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_asistencia_guardar(
    p_actor        interno.tp_actor,
    p_id_empleado  BIGINT,
    p_id_hotel     BIGINT,
    p_fecha        DATE,
    p_id_turno     BIGINT,
    p_estado       TEXT,
    p_observacion  TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_empleado     empleado%ROWTYPE;
    v_anterior     JSONB;
    v_id           BIGINT;
    v_restriccion  TEXT;
BEGIN
    PERFORM interno.sp_comun_exigir_hotel(p_actor, p_id_hotel);

    IF p_estado IS NULL OR p_estado NOT IN
        ('asistio', 'llegada_tarde', 'falto', 'permiso', 'descanso', 'vacaciones', 'suspension') THEN
        PERFORM interno.sp_comun_error('HH422', 'estado_invalido',
            'Estado no válido: asistio, llegada_tarde, falto, permiso, descanso, vacaciones o suspension');
    END IF;
    IF p_fecha IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'fecha_requerida', 'La fecha es obligatoria');
    END IF;

    SELECT e.* INTO v_empleado FROM empleado e WHERE e.id_empleado = p_id_empleado;
    IF NOT FOUND OR NOT EXISTS (
        SELECT 1 FROM empleado_hotel eh WHERE eh.id_empleado = p_id_empleado AND eh.id_hotel = p_id_hotel) THEN
        PERFORM interno.sp_comun_error('HH404', 'empleado_no_encontrado', 'El empleado no trabaja en este hotel');
    END IF;
    IF p_fecha < v_empleado.fecha_ingreso OR p_fecha > COALESCE(v_empleado.fecha_baja, 'infinity'::date) THEN
        PERFORM interno.sp_comun_error('HH422', 'fuera_de_contrato', 'La fecha está fuera del periodo laboral del empleado');
    END IF;

    IF p_estado IN ('asistio', 'llegada_tarde', 'falto') THEN
        IF p_id_turno IS NULL THEN
            PERFORM interno.sp_comun_error('HH422', 'turno_requerido', 'Indique el turno');
        END IF;
        IF p_fecha > interno.sp_comun_hoy() THEN
            PERFORM interno.sp_comun_error('HH422', 'fecha_futura', 'No se puede registrar asistencia de días futuros');
        END IF;
    END IF;
    IF p_estado IN ('descanso', 'vacaciones', 'suspension') AND p_id_turno IS NOT NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'estado_de_dia_completo',
            'Descanso, vacaciones y suspensión son por día completo; no indique turno');
    END IF;
    IF p_id_turno IS NULL AND EXISTS (
        SELECT 1 FROM asistencia a
         WHERE a.id_empleado = p_id_empleado AND a.id_hotel = p_id_hotel AND a.fecha = p_fecha
           AND a.id_turno IS NOT NULL) THEN
        PERFORM interno.sp_comun_error('HH409', 'asistencia_contradictoria',
            'Ese día ya tiene asistencia por turno; corríjala en vez de registrar el día completo');
    END IF;
    IF p_id_turno IS NOT NULL AND EXISTS (
        SELECT 1 FROM asistencia a
         WHERE a.id_empleado = p_id_empleado AND a.id_hotel = p_id_hotel AND a.fecha = p_fecha
           AND a.id_turno IS NULL) THEN
        PERFORM interno.sp_comun_error('HH409', 'asistencia_contradictoria',
            'Ese día ya está registrado como día completo (descanso, vacaciones, permiso o suspensión)');
    END IF;

    SELECT to_jsonb(a) INTO v_anterior FROM asistencia a
     WHERE a.id_empleado = p_id_empleado AND a.id_hotel = p_id_hotel AND a.fecha = p_fecha
       AND a.id_turno IS NOT DISTINCT FROM p_id_turno
       FOR UPDATE;

    INSERT INTO asistencia (id_empleado, id_hotel, id_turno, fecha, estado, observacion, registrado_por)
    VALUES (p_id_empleado, p_id_hotel, p_id_turno, p_fecha, p_estado, NULLIF(btrim(p_observacion), ''),
            p_actor.id_usuario)
    ON CONFLICT ON CONSTRAINT uq_asistencia_empleado_fecha_turno
    DO UPDATE SET estado = EXCLUDED.estado, observacion = EXCLUDED.observacion,
                  registrado_por = EXCLUDED.registrado_por
    RETURNING id_asistencia INTO v_id;

    PERFORM interno.sp_comun_registrar_bitacora(p_actor.id_usuario, p_id_hotel, 'asistencia', 'asistencia',
        v_id::text, CASE WHEN v_anterior IS NULL THEN 'crear' ELSE 'modificar' END, v_anterior,
        (SELECT to_jsonb(a) FROM asistencia a WHERE a.id_asistencia = v_id));
    RETURN v_id;
EXCEPTION
    WHEN foreign_key_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'turno_invalido', 'El turno no existe en este hotel');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'Los datos de asistencia no son válidos');
END;
$$;

CREATE OR REPLACE FUNCTION sp_empleados_crear(
    p_id_usuario_actor  BIGINT,
    p_nombres           TEXT,
    p_apellidos         TEXT,
    p_dpi               TEXT,
    p_telefono          TEXT,
    p_puesto            TEXT,
    p_fecha_ingreso     DATE,
    p_ids_hotel         BIGINT[],
    p_correo            TEXT,
    p_rol               TEXT,
    p_contrasena_hash   TEXT)
RETURNS TABLE (id_empleado BIGINT, id_usuario BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor        interno.tp_actor;
    v_hoteles      BIGINT[];
    v_id_hotel     BIGINT;
    v_id_usuario   BIGINT;
    v_id_empleado  BIGINT;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombres, 'nombres');
    PERFORM interno.sp_comun_exigir_texto(p_apellidos, 'apellidos');
    PERFORM interno.sp_comun_exigir_texto(p_dpi, 'DPI');
    PERFORM interno.sp_comun_exigir_texto(p_puesto, 'puesto');
    IF p_fecha_ingreso IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'campo_requerido', 'La fecha de ingreso es obligatoria');
    END IF;

    v_hoteles := ARRAY(SELECT DISTINCT unnest(COALESCE(p_ids_hotel, '{}')) ORDER BY 1);
    IF cardinality(v_hoteles) = 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'hotel_requerido', 'Asigne al menos un hotel');
    END IF;
    FOREACH v_id_hotel IN ARRAY v_hoteles LOOP
        IF NOT EXISTS (SELECT 1 FROM hotel h WHERE h.id_hotel = v_id_hotel AND h.activo) THEN
            PERFORM interno.sp_comun_error('HH422', 'hotel_invalido', 'Uno de los hoteles no existe o está inactivo');
        END IF;
        PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);
    END LOOP;

    IF NULLIF(btrim(p_correo), '') IS NOT NULL THEN
        PERFORM interno.sp_comun_exigir_texto(p_contrasena_hash, 'contraseña');
        IF EXISTS (SELECT 1 FROM usuario u WHERE u.correo = btrim(p_correo)::citext) THEN
            PERFORM interno.sp_comun_error('HH409', 'correo_registrado', 'Ya existe una cuenta con ese correo');
        END IF;
        INSERT INTO usuario (correo, contrasena_hash, id_rol)
        VALUES (lower(btrim(p_correo)), p_contrasena_hash, interno.sp_empleados_rol_personal(p_rol))
        RETURNING usuario.id_usuario INTO v_id_usuario;
    END IF;

    INSERT INTO empleado (id_usuario, nombres, apellidos, dpi, telefono, puesto, fecha_ingreso)
    VALUES (v_id_usuario, btrim(p_nombres), btrim(p_apellidos), btrim(p_dpi), NULLIF(btrim(p_telefono), ''),
            btrim(p_puesto), p_fecha_ingreso)
    RETURNING empleado.id_empleado INTO v_id_empleado;

    INSERT INTO empleado_hotel (id_empleado, id_hotel)
    SELECT v_id_empleado, x FROM unnest(v_hoteles) AS x;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_hoteles[1], 'empleados', 'empleado',
        v_id_empleado::text, 'crear', NULL,
        (SELECT to_jsonb(e) FROM empleado e WHERE e.id_empleado = v_id_empleado)
            || jsonb_build_object('hoteles', to_jsonb(v_hoteles), 'correo', lower(btrim(p_correo)),
                                  'rol', CASE WHEN v_id_usuario IS NOT NULL THEN lower(btrim(p_rol)) END));

    RETURN QUERY SELECT v_id_empleado, v_id_usuario;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'empleado_duplicado', 'Ya existe un empleado con ese DPI o ese correo');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'Los datos del empleado no tienen un formato válido');
END;
$$;

CREATE OR REPLACE FUNCTION sp_empleados_actualizar(
    p_id_usuario_actor  BIGINT,
    p_id_empleado       BIGINT,
    p_nombres           TEXT,
    p_apellidos         TEXT,
    p_telefono          TEXT,
    p_puesto            TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_anterior  JSONB;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
    PERFORM interno.sp_empleados_exigir_acceso(v_actor, p_id_empleado);
    PERFORM interno.sp_comun_exigir_texto(p_nombres, 'nombres');
    PERFORM interno.sp_comun_exigir_texto(p_apellidos, 'apellidos');
    PERFORM interno.sp_comun_exigir_texto(p_puesto, 'puesto');

    SELECT to_jsonb(e) INTO v_anterior FROM empleado e WHERE e.id_empleado = p_id_empleado FOR UPDATE;
    UPDATE empleado e
       SET nombres = btrim(p_nombres), apellidos = btrim(p_apellidos),
           telefono = NULLIF(btrim(p_telefono), ''), puesto = btrim(p_puesto)
     WHERE e.id_empleado = p_id_empleado;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'empleados', 'empleado',
        p_id_empleado::text, 'modificar', v_anterior,
        (SELECT to_jsonb(e) FROM empleado e WHERE e.id_empleado = p_id_empleado));
END;
$$;
CREATE OR REPLACE FUNCTION sp_empleados_asignar_hoteles(
    p_id_usuario_actor  BIGINT,
    p_id_empleado       BIGINT,
    p_ids_hotel         BIGINT[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_nuevos    BIGINT[];
    v_anterior  BIGINT[];
    v_id_hotel  BIGINT;
    v_hoy       DATE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
    PERFORM interno.sp_empleados_exigir_acceso(v_actor, p_id_empleado);
    v_hoy := interno.sp_comun_hoy();

    v_nuevos := ARRAY(SELECT DISTINCT unnest(COALESCE(p_ids_hotel, '{}')) ORDER BY 1);
    IF cardinality(v_nuevos) = 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'hotel_requerido',
            'El empleado debe quedar al menos en un hotel; para retirarlo use dar de baja');
    END IF;
    FOREACH v_id_hotel IN ARRAY v_nuevos LOOP
        IF NOT EXISTS (SELECT 1 FROM hotel h WHERE h.id_hotel = v_id_hotel AND h.activo) THEN
            PERFORM interno.sp_comun_error('HH422', 'hotel_invalido', 'Uno de los hoteles no existe o está inactivo');
        END IF;
        PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);
    END LOOP;

    PERFORM 1 FROM empleado e WHERE e.id_empleado = p_id_empleado FOR UPDATE;
    v_anterior := ARRAY(SELECT eh.id_hotel FROM empleado_hotel eh
                         WHERE eh.id_empleado = p_id_empleado AND eh.activo ORDER BY 1);

    IF EXISTS (SELECT 1 FROM empleado_turno et
                WHERE et.id_empleado = p_id_empleado
                  AND NOT (et.id_hotel = ANY (v_nuevos))
                  AND (upper_inf(et.vigencia) OR upper(et.vigencia) > v_hoy)) THEN
        PERFORM interno.sp_comun_error('HH409', 'turnos_vigentes',
            'Tiene turnos vigentes en un hotel que se le quita; finalícelos primero');
    END IF;

    UPDATE empleado_hotel eh SET activo = FALSE
     WHERE eh.id_empleado = p_id_empleado AND eh.activo AND NOT (eh.id_hotel = ANY (v_nuevos));
    UPDATE empleado_hotel eh SET activo = TRUE
     WHERE eh.id_empleado = p_id_empleado AND NOT eh.activo AND eh.id_hotel = ANY (v_nuevos);
    INSERT INTO empleado_hotel (id_empleado, id_hotel)
    SELECT p_id_empleado, x FROM unnest(v_nuevos) AS x
    ON CONFLICT DO NOTHING;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'empleados', 'empleado_hotel',
        p_id_empleado::text, 'modificar',
        jsonb_build_object('hoteles', to_jsonb(v_anterior)), jsonb_build_object('hoteles', to_jsonb(v_nuevos)));
END;
$$;
CREATE OR REPLACE FUNCTION sp_empleados_crear_usuario(
    p_id_usuario_actor  BIGINT,
    p_id_empleado       BIGINT,
    p_correo            TEXT,
    p_rol               TEXT,
    p_contrasena_hash   TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_actual       BIGINT;
    v_activo       BOOLEAN;
    v_id_usuario   BIGINT;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
    PERFORM interno.sp_empleados_exigir_acceso(v_actor, p_id_empleado);
    PERFORM interno.sp_comun_exigir_texto(p_correo, 'correo');
    PERFORM interno.sp_comun_exigir_texto(p_contrasena_hash, 'contraseña');

    SELECT e.id_usuario, e.activo INTO v_actual, v_activo FROM empleado e WHERE e.id_empleado = p_id_empleado FOR UPDATE;
    IF NOT v_activo THEN
        PERFORM interno.sp_comun_error('HH409', 'empleado_de_baja', 'El empleado está dado de baja');
    END IF;
    IF v_actual IS NOT NULL THEN
        PERFORM interno.sp_comun_error('HH409', 'empleado_con_usuario', 'El empleado ya tiene usuario');
    END IF;

    INSERT INTO usuario (correo, contrasena_hash, id_rol)
    VALUES (lower(btrim(p_correo)), p_contrasena_hash, interno.sp_empleados_rol_personal(p_rol))
    RETURNING id_usuario INTO v_id_usuario;
    UPDATE empleado e SET id_usuario = v_id_usuario WHERE e.id_empleado = p_id_empleado;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'usuarios', 'usuario',
        v_id_usuario::text, 'crear', NULL,
        jsonb_build_object('correo', lower(btrim(p_correo)), 'rol', lower(btrim(p_rol)), 'id_empleado', p_id_empleado));
    RETURN v_id_usuario;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'correo_registrado', 'Ya existe una cuenta con ese correo');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'El correo no tiene un formato válido');
END;
$$;

CREATE OR REPLACE FUNCTION sp_empleados_cambiar_rol(p_id_usuario_actor BIGINT, p_id_empleado BIGINT, p_rol TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       interno.tp_actor;
    v_id_usuario  BIGINT;
    v_id_rol      SMALLINT;
    v_anterior    VARCHAR;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
    v_id_usuario := interno.sp_empleados_exigir_acceso(v_actor, p_id_empleado);
    v_id_rol := interno.sp_empleados_rol_personal(p_rol);

    IF v_id_usuario IS NULL THEN
        PERFORM interno.sp_comun_error('HH409', 'empleado_sin_usuario', 'El empleado no tiene usuario');
    END IF;
    IF v_id_usuario = p_id_usuario_actor THEN
        PERFORM interno.sp_comun_error('HH409', 'no_cambiar_rol_propio', 'No puede cambiar su propio rol');
    END IF;

    SELECT r.nombre INTO v_anterior FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
     WHERE u.id_usuario = v_id_usuario FOR UPDATE OF u;
    IF v_anterior = lower(btrim(p_rol)) THEN
        RETURN;
    END IF;
    IF v_anterior = 'administrador' THEN
        PERFORM interno.sp_empleados_validar_no_ultimo_admin(v_id_usuario);
    END IF;

    UPDATE usuario u SET id_rol = v_id_rol WHERE u.id_usuario = v_id_usuario;
    UPDATE token_refresco t SET revocado_en = now() WHERE t.id_usuario = v_id_usuario AND t.revocado_en IS NULL;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'usuarios', 'usuario',
        v_id_usuario::text, 'modificar', jsonb_build_object('rol', v_anterior),
        jsonb_build_object('rol', lower(btrim(p_rol))));
END;
$$;

CREATE OR REPLACE FUNCTION sp_empleados_dar_baja(p_id_usuario_actor BIGINT, p_id_empleado BIGINT, p_fecha_baja DATE)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       interno.tp_actor;
    v_empleado    empleado%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
    PERFORM interno.sp_empleados_exigir_acceso(v_actor, p_id_empleado);

    SELECT e.* INTO v_empleado FROM empleado e WHERE e.id_empleado = p_id_empleado FOR UPDATE;
    IF NOT v_empleado.activo THEN
        PERFORM interno.sp_comun_error('HH409', 'empleado_de_baja', 'El empleado ya está dado de baja');
    END IF;
    IF p_fecha_baja IS NULL OR p_fecha_baja < v_empleado.fecha_ingreso THEN
        PERFORM interno.sp_comun_error('HH422', 'fecha_baja_invalida', 'La fecha de baja no puede ser anterior al ingreso');
    END IF;
    IF v_empleado.id_usuario = p_id_usuario_actor THEN
        PERFORM interno.sp_comun_error('HH409', 'no_darse_de_baja', 'No puede darse de baja a sí mismo');
    END IF;
    PERFORM interno.sp_empleados_validar_no_ultimo_admin(v_empleado.id_usuario);

    DELETE FROM empleado_turno et
     WHERE et.id_empleado = p_id_empleado AND lower(et.vigencia) > p_fecha_baja;
    UPDATE empleado_turno et SET vigencia = daterange(lower(et.vigencia), p_fecha_baja + 1, '[)')
     WHERE et.id_empleado = p_id_empleado
       AND (upper_inf(et.vigencia) OR upper(et.vigencia) > p_fecha_baja + 1);

    UPDATE empleado e SET activo = FALSE, fecha_baja = p_fecha_baja WHERE e.id_empleado = p_id_empleado;
    IF v_empleado.id_usuario IS NOT NULL THEN
        UPDATE usuario u SET activo = FALSE WHERE u.id_usuario = v_empleado.id_usuario;
        UPDATE token_refresco t SET revocado_en = now()
         WHERE t.id_usuario = v_empleado.id_usuario AND t.revocado_en IS NULL;
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'empleados', 'empleado',
        p_id_empleado::text, 'desactivar',
        jsonb_build_object('activo', true, 'fecha_baja', NULL),
        jsonb_build_object('activo', false, 'fecha_baja', p_fecha_baja));
END;
$$;

CREATE OR REPLACE FUNCTION sp_empleados_obtener(p_id_usuario_actor BIGINT, p_id_empleado BIGINT)
RETURNS TABLE (
    id_empleado    BIGINT,
    nombres        VARCHAR,
    apellidos      VARCHAR,
    dpi            VARCHAR,
    telefono       VARCHAR,
    puesto         VARCHAR,
    fecha_ingreso  DATE,
    fecha_baja     DATE,
    activo         BOOLEAN,
    id_usuario     BIGINT,
    correo         CITEXT,
    rol            VARCHAR,
    usuario_activo BOOLEAN,
    hoteles        JSONB,
    turnos         JSONB)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR', 'ASISTENCIA_REGISTRAR');
    PERFORM interno.sp_empleados_exigir_acceso(v_actor, p_id_empleado);

    RETURN QUERY
    SELECT e.id_empleado, e.nombres, e.apellidos, e.dpi, e.telefono, e.puesto, e.fecha_ingreso, e.fecha_baja,
           e.activo, u.id_usuario, u.correo, r.nombre, u.activo,
           (SELECT COALESCE(jsonb_agg(jsonb_build_object('id_hotel', h.id_hotel, 'nombre', h.nombre,
                                                         'activo', eh.activo) ORDER BY h.nombre), '[]')
              FROM empleado_hotel eh JOIN hotel h ON h.id_hotel = eh.id_hotel
             WHERE eh.id_empleado = e.id_empleado),
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                       'id_empleado_turno', et.id_empleado_turno, 'id_turno', t.id_turno, 'turno', t.nombre,
                       'id_hotel', et.id_hotel, 'hora_inicio', t.hora_inicio, 'hora_fin', t.hora_fin,
                       'desde', lower(et.vigencia), 'hasta', upper(et.vigencia) - 1)
                       ORDER BY lower(et.vigencia) DESC), '[]')
              FROM empleado_turno et JOIN turno t ON t.id_turno = et.id_turno
             WHERE et.id_empleado = e.id_empleado)
      FROM empleado e
      LEFT JOIN usuario u ON u.id_usuario = e.id_usuario
      LEFT JOIN rol r ON r.id_rol = u.id_rol
     WHERE e.id_empleado = p_id_empleado;
END;
$$;
CREATE OR REPLACE FUNCTION sp_empleados_listar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_busqueda          TEXT,
    p_activo            BOOLEAN,
    p_pagina            INTEGER,
    p_tamano            INTEGER,
    p_orden             TEXT,
    p_direccion         TEXT)
RETURNS TABLE (
    id_empleado      BIGINT,
    nombre           TEXT,
    dpi              VARCHAR,
    puesto           VARCHAR,
    fecha_ingreso    DATE,
    activo           BOOLEAN,
    correo           CITEXT,
    rol              VARCHAR,
    hoteles          TEXT,
    turnos_vigentes  TEXT,
    total_registros  BIGINT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_hoy       DATE;
    v_busqueda  TEXT := NULLIF(btrim(p_busqueda), '');
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR', 'ASISTENCIA_REGISTRAR');
    IF p_id_hotel IS NULL THEN
        IF v_actor.rol <> 'administrador' THEN
            PERFORM interno.sp_comun_error('HH422', 'hotel_requerido', 'Seleccione un hotel');
        END IF;
    ELSE
        PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    END IF;
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    PERFORM interno.sp_comun_validar_direccion(p_direccion);
    IF p_orden IS NULL OR p_orden NOT IN ('nombre', 'fecha_ingreso', 'puesto') THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_invalido', 'Orden no válido: use nombre, fecha_ingreso o puesto');
    END IF;
    v_hoy := interno.sp_comun_hoy();

    RETURN QUERY
    SELECT e.id_empleado, e.nombres || ' ' || e.apellidos, e.dpi, e.puesto, e.fecha_ingreso, e.activo,
           u.correo, r.nombre,
           (SELECT string_agg(h.nombre, ', ' ORDER BY h.nombre) FROM empleado_hotel eh
              JOIN hotel h ON h.id_hotel = eh.id_hotel WHERE eh.id_empleado = e.id_empleado AND eh.activo),
           (SELECT string_agg(t.nombre || ' ' || to_char(t.hora_inicio, 'HH24:MI') || '-' || to_char(t.hora_fin, 'HH24:MI'),
                              ', ' ORDER BY t.hora_inicio)
              FROM empleado_turno et JOIN turno t ON t.id_turno = et.id_turno
             WHERE et.id_empleado = e.id_empleado AND et.vigencia @> v_hoy
               AND (p_id_hotel IS NULL OR et.id_hotel = p_id_hotel)),
           count(*) OVER ()
      FROM empleado e
      LEFT JOIN usuario u ON u.id_usuario = e.id_usuario
      LEFT JOIN rol r ON r.id_rol = u.id_rol
     WHERE (p_id_hotel IS NULL OR EXISTS (
               SELECT 1 FROM empleado_hotel eh
                WHERE eh.id_empleado = e.id_empleado AND eh.id_hotel = p_id_hotel AND eh.activo))
       AND (p_activo IS NULL OR e.activo = p_activo)
       AND (v_busqueda IS NULL
            OR (e.nombres || ' ' || e.apellidos) ILIKE '%' || v_busqueda || '%'
            OR e.dpi = v_busqueda
            OR e.puesto ILIKE '%' || v_busqueda || '%')
     ORDER BY
        CASE WHEN p_orden = 'nombre'        AND p_direccion = 'asc'  THEN e.apellidos || ' ' || e.nombres END ASC,
        CASE WHEN p_orden = 'nombre'        AND p_direccion = 'desc' THEN e.apellidos || ' ' || e.nombres END DESC,
        CASE WHEN p_orden = 'fecha_ingreso' AND p_direccion = 'asc'  THEN e.fecha_ingreso END ASC,
        CASE WHEN p_orden = 'fecha_ingreso' AND p_direccion = 'desc' THEN e.fecha_ingreso END DESC,
        CASE WHEN p_orden = 'puesto'        AND p_direccion = 'asc'  THEN e.puesto END ASC,
        CASE WHEN p_orden = 'puesto'        AND p_direccion = 'desc' THEN e.puesto END DESC,
        e.id_empleado
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;


CREATE OR REPLACE FUNCTION sp_turnos_crear(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_nombre            TEXT,
    p_hora_inicio       TIME,
    p_hora_fin          TIME)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_id_turno     BIGINT;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');
    IF p_hora_inicio IS NULL OR p_hora_fin IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'campo_requerido', 'Las horas de inicio y fin son obligatorias');
    END IF;

    INSERT INTO turno (id_hotel, nombre, hora_inicio, hora_fin)
    VALUES (p_id_hotel, btrim(p_nombre), p_hora_inicio, p_hora_fin)
    RETURNING id_turno INTO v_id_turno;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'empleados', 'turno',
        v_id_turno::text, 'crear', NULL, (SELECT to_jsonb(t) FROM turno t WHERE t.id_turno = v_id_turno));
    RETURN v_id_turno;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'turno_duplicado', 'Ese hotel ya tiene un turno con ese nombre');
    WHEN foreign_key_violation THEN
        PERFORM interno.sp_comun_error('HH404', 'hotel_no_encontrado', 'Hotel no encontrado');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'La hora de inicio y la de fin no pueden ser iguales');
END;
$$;

CREATE OR REPLACE FUNCTION sp_turnos_actualizar(
    p_id_usuario_actor  BIGINT,
    p_id_turno          BIGINT,
    p_nombre            TEXT,
    p_hora_inicio       TIME,
    p_hora_fin          TIME,
    p_activo            BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_anterior     JSONB;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');

    SELECT to_jsonb(t) INTO v_anterior FROM turno t WHERE t.id_turno = p_id_turno FOR UPDATE;
    IF v_anterior IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'turno_no_encontrado', 'Turno no encontrado');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, (v_anterior ->> 'id_hotel')::bigint);

    IF p_activo IS FALSE AND EXISTS (
        SELECT 1 FROM empleado_turno et
         WHERE et.id_turno = p_id_turno
           AND (upper_inf(et.vigencia) OR upper(et.vigencia) > interno.sp_comun_hoy())) THEN
        PERFORM interno.sp_comun_error('HH409', 'turno_con_empleados',
            'Hay empleados con este turno vigente; finalice sus asignaciones primero');
    END IF;

    UPDATE turno t
       SET nombre = btrim(p_nombre), hora_inicio = COALESCE(p_hora_inicio, t.hora_inicio),
           hora_fin = COALESCE(p_hora_fin, t.hora_fin), activo = COALESCE(p_activo, t.activo)
     WHERE t.id_turno = p_id_turno;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, (v_anterior ->> 'id_hotel')::bigint,
        'empleados', 'turno', p_id_turno::text,
        CASE WHEN p_activo IS FALSE AND (v_anterior ->> 'activo')::boolean THEN 'desactivar' ELSE 'modificar' END,
        v_anterior, (SELECT to_jsonb(t) FROM turno t WHERE t.id_turno = p_id_turno));
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'turno_duplicado', 'Ese hotel ya tiene un turno con ese nombre');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'La hora de inicio y la de fin no pueden ser iguales');
END;
$$;

CREATE OR REPLACE FUNCTION sp_turnos_listar(p_id_usuario_actor BIGINT, p_id_hotel BIGINT, p_incluir_inactivos BOOLEAN)
RETURNS TABLE (
    id_turno            BIGINT,
    nombre              VARCHAR,
    hora_inicio         TIME,
    hora_fin            TIME,
    cruza_medianoche    BOOLEAN,
    activo              BOOLEAN,
    empleados_vigentes  INTEGER)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR', 'ASISTENCIA_REGISTRAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);

    RETURN QUERY
    SELECT t.id_turno, t.nombre, t.hora_inicio, t.hora_fin, (t.hora_fin < t.hora_inicio), t.activo,
           (SELECT count(*)::int FROM empleado_turno et
             WHERE et.id_turno = t.id_turno AND et.vigencia @> interno.sp_comun_hoy())
      FROM turno t
     WHERE t.id_hotel = p_id_hotel
       AND (t.activo OR COALESCE(p_incluir_inactivos, FALSE))
     ORDER BY t.hora_inicio;
END;
$$;

CREATE OR REPLACE FUNCTION sp_empleados_asignar_turno(
    p_id_usuario_actor  BIGINT,
    p_id_empleado       BIGINT,
    p_id_turno          BIGINT,
    p_fecha_desde       DATE)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_turno     turno%ROWTYPE;
    v_empleado  empleado%ROWTYPE;
    v_id        BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');

    SELECT t.* INTO v_turno FROM turno t WHERE t.id_turno = p_id_turno;
    IF NOT FOUND OR NOT v_turno.activo THEN
        PERFORM interno.sp_comun_error('HH404', 'turno_no_encontrado', 'Turno no encontrado o inactivo');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_turno.id_hotel);

    SELECT e.* INTO v_empleado FROM empleado e WHERE e.id_empleado = p_id_empleado;
    IF NOT FOUND OR NOT v_empleado.activo THEN
        PERFORM interno.sp_comun_error('HH404', 'empleado_no_encontrado', 'Empleado no encontrado o dado de baja');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM empleado_hotel eh
                    WHERE eh.id_empleado = p_id_empleado AND eh.id_hotel = v_turno.id_hotel AND eh.activo) THEN
        PERFORM interno.sp_comun_error('HH422', 'empleado_de_otro_hotel', 'El empleado no trabaja en el hotel de ese turno');
    END IF;
    IF p_fecha_desde IS NULL OR p_fecha_desde < v_empleado.fecha_ingreso THEN
        PERFORM interno.sp_comun_error('HH422', 'fecha_invalida', 'La fecha no puede ser anterior al ingreso del empleado');
    END IF;

    INSERT INTO empleado_turno (id_empleado, id_hotel, id_turno, vigencia, creado_por)
    VALUES (p_id_empleado, v_turno.id_hotel, p_id_turno, daterange(p_fecha_desde, NULL, '[)'), p_id_usuario_actor)
    RETURNING id_empleado_turno INTO v_id;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_turno.id_hotel, 'empleados', 'empleado_turno',
        v_id::text, 'crear', NULL,
        jsonb_build_object('id_empleado', p_id_empleado, 'turno', v_turno.nombre, 'desde', p_fecha_desde));
    RETURN v_id;
EXCEPTION
    WHEN exclusion_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'turno_ya_asignado', 'El empleado ya tiene ese turno en esas fechas');
END;
$$;
CREATE OR REPLACE FUNCTION sp_empleados_finalizar_turno(
    p_id_usuario_actor   BIGINT,
    p_id_empleado_turno  BIGINT,
    p_fecha_hasta        DATE)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  interno.tp_actor;
    v_et     empleado_turno%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');

    SELECT et.* INTO v_et FROM empleado_turno et WHERE et.id_empleado_turno = p_id_empleado_turno FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'asignacion_no_encontrada', 'Asignación de turno no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_et.id_hotel);
    IF p_fecha_hasta IS NULL OR p_fecha_hasta < lower(v_et.vigencia) THEN
        PERFORM interno.sp_comun_error('HH422', 'fecha_invalida',
            format('La fecha final no puede ser anterior al inicio (%s)', to_char(lower(v_et.vigencia), 'DD/MM/YYYY')));
    END IF;

    UPDATE empleado_turno et SET vigencia = daterange(lower(et.vigencia), p_fecha_hasta + 1, '[)')
     WHERE et.id_empleado_turno = p_id_empleado_turno;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_et.id_hotel, 'empleados', 'empleado_turno',
        p_id_empleado_turno::text, 'modificar',
        jsonb_build_object('hasta', upper(v_et.vigencia) - 1), jsonb_build_object('hasta', p_fecha_hasta));
END;
$$;

CREATE OR REPLACE FUNCTION sp_asistencia_registrar(
    p_id_usuario_actor  BIGINT,
    p_id_empleado       BIGINT,
    p_id_hotel          BIGINT,
    p_fecha             DATE,
    p_id_turno          BIGINT,
    p_estado            TEXT,
    p_observacion       TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor interno.tp_actor;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'ASISTENCIA_REGISTRAR');
    RETURN interno.sp_asistencia_guardar(v_actor, p_id_empleado, p_id_hotel, p_fecha, p_id_turno, p_estado, p_observacion);
END;
$$;

CREATE OR REPLACE FUNCTION sp_asistencia_registrar_rango(
    p_id_usuario_actor  BIGINT,
    p_id_empleado       BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_estado            TEXT,
    p_observacion       TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  interno.tp_actor;
    v_dia    DATE;
    v_total  INTEGER := 0;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'ASISTENCIA_REGISTRAR');
    IF p_estado IS NULL OR p_estado NOT IN ('permiso', 'descanso', 'vacaciones', 'suspension') THEN
        PERFORM interno.sp_comun_error('HH422', 'estado_invalido',
            'Por rango solo se registran permiso, descanso, vacaciones o suspensión');
    END IF;
    IF p_fecha_desde IS NULL OR p_fecha_hasta IS NULL OR p_fecha_hasta < p_fecha_desde THEN
        PERFORM interno.sp_comun_error('HH422', 'fechas_invalidas', 'La fecha final no puede ser anterior a la inicial');
    END IF;
    IF p_fecha_hasta - p_fecha_desde >= 60 THEN
        PERFORM interno.sp_comun_error('HH422', 'rango_muy_largo', 'Registre como máximo 60 días a la vez');
    END IF;

    FOR v_dia IN SELECT d::date FROM generate_series(p_fecha_desde::timestamp, p_fecha_hasta::timestamp, interval '1 day') d LOOP
        PERFORM interno.sp_asistencia_guardar(v_actor, p_id_empleado, p_id_hotel, v_dia, NULL, p_estado, p_observacion);
        v_total := v_total + 1;
    END LOOP;
    RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION sp_asistencia_hoja_del_dia(p_id_usuario_actor BIGINT, p_id_hotel BIGINT, p_fecha DATE)
RETURNS TABLE (
    id_empleado    BIGINT,
    empleado       TEXT,
    puesto         VARCHAR,
    id_turno       BIGINT,
    turno          VARCHAR,
    hora_inicio    TIME,
    hora_fin       TIME,
    estado         VARCHAR,
    observacion    VARCHAR,
    id_asistencia  BIGINT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'ASISTENCIA_REGISTRAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    IF p_fecha IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'fecha_requerida', 'La fecha es obligatoria');
    END IF;

    RETURN QUERY
    SELECT e.id_empleado, e.nombres || ' ' || e.apellidos, e.puesto, t.id_turno, t.nombre, t.hora_inicio,
           t.hora_fin, COALESCE(a.estado, dc.estado), COALESCE(a.observacion, dc.observacion),
           COALESCE(a.id_asistencia, dc.id_asistencia)
      FROM empleado_turno et
      JOIN empleado e ON e.id_empleado = et.id_empleado
      JOIN turno t ON t.id_turno = et.id_turno
      LEFT JOIN asistencia a ON a.id_empleado = e.id_empleado AND a.id_hotel = p_id_hotel
                            AND a.fecha = p_fecha AND a.id_turno = t.id_turno
      LEFT JOIN asistencia dc ON dc.id_empleado = e.id_empleado AND dc.id_hotel = p_id_hotel
                             AND dc.fecha = p_fecha AND dc.id_turno IS NULL
     WHERE et.id_hotel = p_id_hotel
       AND et.vigencia @> p_fecha
       AND p_fecha >= e.fecha_ingreso
       AND p_fecha <= COALESCE(e.fecha_baja, 'infinity'::date)
    UNION ALL

    SELECT e.id_empleado, e.nombres || ' ' || e.apellidos, e.puesto, t.id_turno, t.nombre, t.hora_inicio,
           t.hora_fin, a.estado, a.observacion, a.id_asistencia
      FROM asistencia a
      JOIN empleado e ON e.id_empleado = a.id_empleado
      JOIN turno t ON t.id_turno = a.id_turno
     WHERE a.id_hotel = p_id_hotel AND a.fecha = p_fecha
       AND NOT EXISTS (SELECT 1 FROM empleado_turno et
                        WHERE et.id_empleado = a.id_empleado AND et.id_turno = a.id_turno AND et.vigencia @> p_fecha)
    ORDER BY 6, 2;
END;
$$;

CREATE OR REPLACE FUNCTION sp_asistencia_listar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_id_empleado       BIGINT,
    p_estado            TEXT,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_asistencia    BIGINT,
    fecha            DATE,
    id_empleado      BIGINT,
    empleado         TEXT,
    turno            VARCHAR,
    estado           VARCHAR,
    observacion      VARCHAR,
    registrado_por   CITEXT,
    actualizado_en   TIMESTAMPTZ,
    total_registros  BIGINT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'ASISTENCIA_REGISTRAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);

    RETURN QUERY
    SELECT a.id_asistencia, a.fecha, e.id_empleado, e.nombres || ' ' || e.apellidos,
           COALESCE(t.nombre, 'Día completo'), a.estado, a.observacion, u.correo, a.actualizado_en,
           count(*) OVER ()
      FROM asistencia a
      JOIN empleado e ON e.id_empleado = a.id_empleado
      LEFT JOIN turno t ON t.id_turno = a.id_turno
      JOIN usuario u ON u.id_usuario = a.registrado_por
     WHERE a.id_hotel = p_id_hotel
       AND (p_fecha_desde IS NULL OR a.fecha >= p_fecha_desde)
       AND (p_fecha_hasta IS NULL OR a.fecha <= p_fecha_hasta)
       AND (p_id_empleado IS NULL OR a.id_empleado = p_id_empleado)
       AND (p_estado IS NULL OR a.estado = p_estado)
     ORDER BY a.fecha DESC, t.hora_inicio NULLS FIRST, e.apellidos
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_asistencia_resumen(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE)
RETURNS TABLE (
    id_empleado     BIGINT,
    empleado        TEXT,
    puesto          VARCHAR,
    asistio         INTEGER,
    llegada_tarde   INTEGER,
    falto           INTEGER,
    permiso         INTEGER,
    descanso        INTEGER,
    vacaciones      INTEGER,
    suspension      INTEGER)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'ASISTENCIA_REGISTRAR', 'REPORTES_VER');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    IF p_fecha_desde IS NULL OR p_fecha_hasta IS NULL OR p_fecha_hasta < p_fecha_desde THEN
        PERFORM interno.sp_comun_error('HH422', 'fechas_invalidas', 'Indique un periodo válido');
    END IF;

    RETURN QUERY
    SELECT e.id_empleado, e.nombres || ' ' || e.apellidos, e.puesto,
           count(*) FILTER (WHERE a.estado = 'asistio')::int,
           count(*) FILTER (WHERE a.estado = 'llegada_tarde')::int,
           count(*) FILTER (WHERE a.estado = 'falto')::int,
           count(*) FILTER (WHERE a.estado = 'permiso')::int,
           count(*) FILTER (WHERE a.estado = 'descanso')::int,
           count(*) FILTER (WHERE a.estado = 'vacaciones')::int,
           count(*) FILTER (WHERE a.estado = 'suspension')::int
      FROM empleado e
      JOIN empleado_hotel eh ON eh.id_empleado = e.id_empleado AND eh.id_hotel = p_id_hotel
      LEFT JOIN asistencia a ON a.id_empleado = e.id_empleado AND a.id_hotel = p_id_hotel
                            AND a.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
     WHERE eh.activo OR a.id_asistencia IS NOT NULL
     GROUP BY e.id_empleado, e.nombres, e.apellidos, e.puesto
     ORDER BY e.apellidos, e.nombres;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_empleados_crear(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, DATE, BIGINT[], TEXT, TEXT, TEXT),
    sp_empleados_actualizar(BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT),
    sp_empleados_asignar_hoteles(BIGINT, BIGINT, BIGINT[]),
    sp_empleados_crear_usuario(BIGINT, BIGINT, TEXT, TEXT, TEXT),
    sp_empleados_cambiar_rol(BIGINT, BIGINT, TEXT),
    sp_empleados_dar_baja(BIGINT, BIGINT, DATE),
    sp_empleados_obtener(BIGINT, BIGINT),
    sp_empleados_listar(BIGINT, BIGINT, TEXT, BOOLEAN, INTEGER, INTEGER, TEXT, TEXT),
    sp_turnos_crear(BIGINT, BIGINT, TEXT, TIME, TIME),
    sp_turnos_actualizar(BIGINT, BIGINT, TEXT, TIME, TIME, BOOLEAN),
    sp_turnos_listar(BIGINT, BIGINT, BOOLEAN),
    sp_empleados_asignar_turno(BIGINT, BIGINT, BIGINT, DATE),
    sp_empleados_finalizar_turno(BIGINT, BIGINT, DATE),
    sp_asistencia_registrar(BIGINT, BIGINT, BIGINT, DATE, BIGINT, TEXT, TEXT),
    sp_asistencia_registrar_rango(BIGINT, BIGINT, BIGINT, DATE, DATE, TEXT, TEXT),
    sp_asistencia_hoja_del_dia(BIGINT, BIGINT, DATE),
    sp_asistencia_listar(BIGINT, BIGINT, DATE, DATE, BIGINT, TEXT, INTEGER, INTEGER),
    sp_asistencia_resumen(BIGINT, BIGINT, DATE, DATE)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('027_sp_empleados.sql');