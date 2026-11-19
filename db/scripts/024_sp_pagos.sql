-- =============================================================================
-- 024_sp_pagos.sql
-- Pagos: anticipo en línea, cobros en el hotel y reembolsos (RN-04).
--
-- Anticipo en línea, en dos pasos (no se deja una transacción abierta
-- mientras se espera a la pasarela):
--   1. sp_pagos_iniciar_anticipo   -> crea el pago 'pendiente'. La API usa
--      el id_pago como referencia al enviar el cobro a BAC / VisaNet.
--   2. sp_pagos_confirmar_pasarela -> lo llama la API al recibir el aviso de
--      la pasarela (después de verificar su firma). Aprueba el pago y
--      confirma la reservación. Avisos repetidos no hacen nada.
-- La reservación solo se confirma en el paso 2, nunca porque el navegador
-- diga que el pago salió bien.
--
-- Mientras no se elija la pasarela, la API usa pasarela = 'simulada'.
-- =============================================================================

CREATE OR REPLACE FUNCTION interno.sp_pagos_resumen(p_id_reservacion BIGINT)
RETURNS TABLE (pagado DECIMAL(10,2), saldo DECIMAL(10,2))
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT (x.cobrado - x.reembolsado)::numeric(10,2),
           (r.total - (x.cobrado - x.reembolsado))::numeric(10,2)
      FROM reservacion r
     CROSS JOIN LATERAL (
           SELECT COALESCE(sum(p.monto) FILTER (WHERE p.tipo <> 'reembolso'), 0) AS cobrado,
                  COALESCE(sum(p.monto) FILTER (WHERE p.tipo = 'reembolso' AND o.estado = 'aprobado'), 0) AS reembolsado
             FROM pago p
             LEFT JOIN pago o ON o.id_pago = p.id_pago_origen
            WHERE p.id_reservacion = r.id_reservacion
              AND p.estado = 'aprobado'
           ) x
     WHERE r.id_reservacion = p_id_reservacion;
$$;

CREATE OR REPLACE FUNCTION sp_pagos_iniciar_anticipo(
    p_id_usuario_actor    BIGINT,
    p_id_reservacion      BIGINT,
    p_pasarela            TEXT,
    p_llave_idempotencia  UUID)
RETURNS TABLE (id_pago BIGINT, monto DECIMAL(10,2), estado VARCHAR, expira_en TIMESTAMPTZ, ya_existia BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor  interno.tp_actor;
    v_res    reservacion%ROWTYPE;
    v_pago   pago%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_reservaciones_exigir_acceso(v_actor, p_id_reservacion);
    PERFORM interno.sp_comun_exigir_texto(p_pasarela, 'pasarela');
    IF p_llave_idempotencia IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'llave_requerida', 'Falta la llave de idempotencia');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('pago:' || p_llave_idempotencia::text, 0));

    SELECT p.* INTO v_pago FROM pago p WHERE p.llave_idempotencia = p_llave_idempotencia;
    IF FOUND THEN
        IF v_pago.id_reservacion <> p_id_reservacion THEN
            PERFORM interno.sp_comun_error('HH409', 'llave_reutilizada', 'La llave de idempotencia ya se usó en otro pago');
        END IF;
        RETURN QUERY SELECT v_pago.id_pago, v_pago.monto, v_pago.estado,
                            (SELECT r.expira_en FROM reservacion r WHERE r.id_reservacion = p_id_reservacion), TRUE;
        RETURN;
    END IF;

    SELECT r.* INTO v_res FROM reservacion r WHERE r.id_reservacion = p_id_reservacion FOR UPDATE;
    IF v_res.estado <> 'pendiente_pago' THEN
        PERFORM interno.sp_comun_error('HH409', 'no_requiere_pago',
            'Esta reservación no está pendiente de pago');
    END IF;
    IF v_res.expira_en <= now() THEN
        PERFORM interno.sp_comun_error('HH409', 'tiempo_vencido',
            'Venció el tiempo para pagar; vuelva a hacer la reservación');
    END IF;

    INSERT INTO pago (id_reservacion, tipo, metodo, monto, estado, llave_idempotencia, pasarela)
    VALUES (p_id_reservacion, 'anticipo', 'pasarela', v_res.monto_anticipo, 'pendiente',
            p_llave_idempotencia, lower(btrim(p_pasarela)))
    RETURNING * INTO v_pago;

    RETURN QUERY SELECT v_pago.id_pago, v_pago.monto, v_pago.estado, v_res.expira_en, FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION sp_pagos_confirmar_pasarela(
    p_pasarela             TEXT,
    p_id_evento_externo    TEXT,
    p_tipo_evento          TEXT,
    p_contenido            JSONB,
    p_id_pago              BIGINT,
    p_referencia_pasarela  TEXT,
    p_monto                DECIMAL(10,2),
    p_aprobado             BOOLEAN)
RETURNS TABLE (resultado TEXT, id_reservacion BIGINT, estado_reservacion VARCHAR, estado_pago VARCHAR)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_id_evento   BIGINT;
    v_pago        pago%ROWTYPE;
    v_estado_res  VARCHAR;
    v_resultado   TEXT;
BEGIN
    PERFORM interno.sp_comun_exigir_texto(p_pasarela, 'pasarela');
    PERFORM interno.sp_comun_exigir_texto(p_id_evento_externo, 'id del evento');
    IF p_aprobado IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'resultado_requerido', 'Falta indicar si el cobro fue aprobado');
    END IF;

    SELECT p.* INTO v_pago FROM pago p WHERE p.id_pago = p_id_pago FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'pago_no_encontrado', 'Pago no encontrado');
    END IF;

    INSERT INTO evento_pasarela (pasarela, id_evento_externo, tipo, contenido, id_pago)
    VALUES (lower(btrim(p_pasarela)), btrim(p_id_evento_externo), COALESCE(p_tipo_evento, 'desconocido'),
            COALESCE(p_contenido, '{}'::jsonb), p_id_pago)
    ON CONFLICT (pasarela, id_evento_externo) DO NOTHING
    RETURNING id_evento_pasarela INTO v_id_evento;

    IF v_id_evento IS NULL THEN
        RETURN QUERY SELECT 'duplicado'::text, v_pago.id_reservacion,
                            (SELECT r.estado FROM reservacion r WHERE r.id_reservacion = v_pago.id_reservacion),
                            v_pago.estado;
        RETURN;
    END IF;

    IF v_pago.metodo <> 'pasarela' OR v_pago.pasarela IS DISTINCT FROM lower(btrim(p_pasarela)) THEN
        PERFORM interno.sp_comun_error('HH422', 'pasarela_no_coincide', 'El aviso no corresponde a la pasarela del pago');
    END IF;
    IF p_aprobado AND p_monto IS DISTINCT FROM v_pago.monto THEN
        PERFORM interno.sp_comun_error('HH422', 'monto_no_coincide',
            format('La pasarela reporta Q%s pero el pago es de Q%s', p_monto, v_pago.monto));
    END IF;

    IF v_pago.estado NOT IN ('pendiente', 'expirado') THEN
        UPDATE evento_pasarela e SET procesado_en = now() WHERE e.id_evento_pasarela = v_id_evento;
        RETURN QUERY SELECT 'duplicado'::text, v_pago.id_reservacion,
                            (SELECT r.estado FROM reservacion r WHERE r.id_reservacion = v_pago.id_reservacion),
                            v_pago.estado;
        RETURN;
    END IF;

    SELECT r.estado INTO v_estado_res FROM reservacion r WHERE r.id_reservacion = v_pago.id_reservacion FOR UPDATE;

    IF NOT p_aprobado THEN
        UPDATE pago p SET estado = 'rechazado', referencia_pasarela = NULLIF(btrim(p_referencia_pasarela), '')
         WHERE p.id_pago = p_id_pago;
        v_resultado := 'rechazado';
    ELSIF v_pago.estado = 'pendiente' AND v_estado_res = 'pendiente_pago' THEN
        UPDATE pago p
           SET estado = 'aprobado', referencia_pasarela = NULLIF(btrim(p_referencia_pasarela), ''),
               confirmado_en = now()
         WHERE p.id_pago = p_id_pago;
        PERFORM interno.sp_reservaciones_cambiar_estado(v_pago.id_reservacion, 'confirmada', NULL,
            'Anticipo aprobado por la pasarela');
        v_resultado := 'aprobado';
    ELSE
        UPDATE pago p
           SET estado = 'anulado', referencia_pasarela = NULLIF(btrim(p_referencia_pasarela), ''),
               confirmado_en = now()
         WHERE p.id_pago = p_id_pago;
        v_resultado := 'anulado';
    END IF;

    UPDATE evento_pasarela e SET procesado_en = now() WHERE e.id_evento_pasarela = v_id_evento;

    PERFORM interno.sp_comun_registrar_bitacora(NULL,
        (SELECT r.id_hotel FROM reservacion r WHERE r.id_reservacion = v_pago.id_reservacion),
        'pagos', 'pago', p_id_pago::text, 'cambio_estado',
        jsonb_build_object('estado', v_pago.estado),
        jsonb_build_object('estado', CASE v_resultado WHEN 'aprobado' THEN 'aprobado'
                                                      WHEN 'rechazado' THEN 'rechazado' ELSE 'anulado' END,
                           'pasarela', lower(btrim(p_pasarela)), 'referencia', p_referencia_pasarela));

    RETURN QUERY SELECT v_resultado, v_pago.id_reservacion,
                        (SELECT r.estado FROM reservacion r WHERE r.id_reservacion = v_pago.id_reservacion),
                        (SELECT p.estado FROM pago p WHERE p.id_pago = p_id_pago);
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'anticipo_ya_aprobado',
            'Esta reservación ya tiene un anticipo aprobado');
END;
$$;

CREATE OR REPLACE FUNCTION sp_pagos_registrar_en_hotel(
    p_id_usuario_actor    BIGINT,
    p_id_reservacion      BIGINT,
    p_tipo                TEXT,
    p_metodo              TEXT,
    p_monto               DECIMAL(10,2),
    p_llave_idempotencia  UUID)
RETURNS TABLE (id_pago BIGINT, monto DECIMAL(10,2), pagado DECIMAL(10,2), saldo DECIMAL(10,2), ya_existia BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_id_hotel  BIGINT;
    v_res       reservacion%ROWTYPE;
    v_pago      pago%ROWTYPE;
    v_saldo     NUMERIC;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'PAGOS_REGISTRAR');
    SELECT r.id_hotel INTO v_id_hotel FROM reservacion r WHERE r.id_reservacion = p_id_reservacion;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'reservacion_no_encontrada', 'Reservación no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);

    IF p_tipo IS NULL OR p_tipo NOT IN ('anticipo', 'saldo') THEN
        PERFORM interno.sp_comun_error('HH422', 'tipo_invalido', 'El tipo de cobro debe ser anticipo o saldo');
    END IF;
    IF p_metodo IS NULL OR p_metodo NOT IN ('efectivo', 'tarjeta_en_hotel') THEN
        PERFORM interno.sp_comun_error('HH422', 'metodo_invalido', 'El método debe ser efectivo o tarjeta_en_hotel');
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'monto_invalido', 'El monto debe ser mayor que cero');
    END IF;
    IF p_llave_idempotencia IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'llave_requerida', 'Falta la llave de idempotencia');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('pago:' || p_llave_idempotencia::text, 0));

    SELECT p.* INTO v_pago FROM pago p WHERE p.llave_idempotencia = p_llave_idempotencia;
    IF FOUND THEN
        RETURN QUERY SELECT v_pago.id_pago, v_pago.monto, s.pagado, s.saldo, TRUE
                       FROM interno.sp_pagos_resumen(v_pago.id_reservacion) s;
        RETURN;
    END IF;

    SELECT r.* INTO v_res FROM reservacion r WHERE r.id_reservacion = p_id_reservacion FOR UPDATE;

    IF p_tipo = 'anticipo' THEN
        IF v_res.estado <> 'pendiente_pago' THEN
            PERFORM interno.sp_comun_error('HH409', 'no_requiere_anticipo', 'Esta reservación no está pendiente de pago');
        END IF;
        IF p_monto <> v_res.monto_anticipo THEN
            PERFORM interno.sp_comun_error('HH422', 'monto_anticipo',
                format('El anticipo de esta reservación es de Q%s', v_res.monto_anticipo));
        END IF;
    ELSE
        IF v_res.estado NOT IN ('confirmada', 'en_curso') THEN
            PERFORM interno.sp_comun_error('HH409', 'no_admite_saldo',
                'Solo se cobra saldo en reservaciones confirmadas o en curso');
        END IF;
        SELECT s.saldo INTO v_saldo FROM interno.sp_pagos_resumen(p_id_reservacion) s;
        IF p_monto > v_saldo THEN
            PERFORM interno.sp_comun_error('HH422', 'monto_excede_saldo',
                format('El saldo pendiente es de Q%s', to_char(v_saldo, 'FM999999990.00')));
        END IF;
    END IF;

    INSERT INTO pago (id_reservacion, tipo, metodo, monto, estado, llave_idempotencia, registrado_por, confirmado_en)
    VALUES (p_id_reservacion, p_tipo, p_metodo, p_monto, 'aprobado', p_llave_idempotencia, p_id_usuario_actor, now())
    RETURNING * INTO v_pago;

    IF p_tipo = 'anticipo' THEN
        PERFORM interno.sp_reservaciones_cambiar_estado(p_id_reservacion, 'confirmada', p_id_usuario_actor,
            'Anticipo cobrado en el hotel');
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'pagos', 'pago',
        v_pago.id_pago::text, 'crear', NULL,
        jsonb_build_object('reservacion', v_res.codigo, 'tipo', p_tipo, 'metodo', p_metodo, 'monto', p_monto));

    RETURN QUERY SELECT v_pago.id_pago, v_pago.monto, s.pagado, s.saldo, FALSE
                   FROM interno.sp_pagos_resumen(p_id_reservacion) s;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'anticipo_ya_aprobado', 'Esta reservación ya tiene un anticipo aprobado');
END;
$$;

CREATE OR REPLACE FUNCTION sp_pagos_reembolsar(
    p_id_usuario_actor     BIGINT,
    p_id_pago_origen       BIGINT,
    p_monto                DECIMAL(10,2),
    p_motivo               TEXT,
    p_referencia_pasarela  TEXT,
    p_llave_idempotencia   UUID)
RETURNS TABLE (id_pago BIGINT, monto DECIMAL(10,2), reembolsado_total DECIMAL(10,2), ya_existia BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor        interno.tp_actor;
    v_origen       pago%ROWTYPE;
    v_id_hotel     BIGINT;
    v_reembolsado  NUMERIC;
    v_pago         pago%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'PAGOS_REEMBOLSAR');
    PERFORM interno.sp_comun_exigir_texto(p_motivo, 'motivo');
    IF p_llave_idempotencia IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'llave_requerida', 'Falta la llave de idempotencia');
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'monto_invalido', 'El monto debe ser mayor que cero');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('pago:' || p_llave_idempotencia::text, 0));
    SELECT p.* INTO v_pago FROM pago p WHERE p.llave_idempotencia = p_llave_idempotencia;
    IF FOUND THEN
        RETURN QUERY SELECT v_pago.id_pago, v_pago.monto,
            (SELECT COALESCE(sum(p.monto), 0)::numeric(10,2) FROM pago p
              WHERE p.id_pago_origen = v_pago.id_pago_origen AND p.estado = 'aprobado'), TRUE;
        RETURN;
    END IF;

    SELECT p.* INTO v_origen FROM pago p WHERE p.id_pago = p_id_pago_origen FOR UPDATE;
    IF NOT FOUND OR v_origen.tipo = 'reembolso' THEN
        PERFORM interno.sp_comun_error('HH404', 'pago_no_encontrado', 'Pago original no encontrado');
    END IF;
    SELECT r.id_hotel INTO v_id_hotel FROM reservacion r WHERE r.id_reservacion = v_origen.id_reservacion;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);

    IF v_origen.estado NOT IN ('aprobado', 'anulado') THEN
        PERFORM interno.sp_comun_error('HH409', 'pago_no_reembolsable', 'Solo se reembolsan pagos cobrados');
    END IF;

    SELECT COALESCE(sum(p.monto), 0) INTO v_reembolsado
      FROM pago p WHERE p.id_pago_origen = p_id_pago_origen AND p.estado = 'aprobado';
    IF v_reembolsado + p_monto > v_origen.monto THEN
        PERFORM interno.sp_comun_error('HH422', 'reembolso_excede',
            format('Del pago de Q%s ya se reembolsaron Q%s', v_origen.monto, to_char(v_reembolsado, 'FM999999990.00')));
    END IF;

    INSERT INTO pago (id_reservacion, tipo, metodo, monto, estado, llave_idempotencia, pasarela,
                      referencia_pasarela, id_pago_origen, registrado_por, confirmado_en)
    VALUES (v_origen.id_reservacion, 'reembolso', v_origen.metodo, p_monto, 'aprobado', p_llave_idempotencia,
            v_origen.pasarela, NULLIF(btrim(p_referencia_pasarela), ''), p_id_pago_origen,
            p_id_usuario_actor, now())
    RETURNING * INTO v_pago;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'pagos', 'pago',
        v_pago.id_pago::text, 'crear', NULL,
        jsonb_build_object('tipo', 'reembolso', 'pago_origen', p_id_pago_origen, 'monto', p_monto,
                           'motivo', btrim(p_motivo)));

    RETURN QUERY SELECT v_pago.id_pago, v_pago.monto, (v_reembolsado + p_monto)::numeric(10,2), FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION sp_pagos_listar_por_reservacion(p_id_usuario_actor BIGINT, p_id_reservacion BIGINT)
RETURNS TABLE (
    id_pago         BIGINT,
    tipo            VARCHAR,
    metodo          VARCHAR,
    monto           DECIMAL(10,2),
    estado          VARCHAR,
    pasarela        VARCHAR,
    id_pago_origen  BIGINT,
    confirmado_en   TIMESTAMPTZ,
    creado_en       TIMESTAMPTZ,
    total_reservacion  DECIMAL(10,2),
    pagado          DECIMAL(10,2),
    saldo           DECIMAL(10,2))
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
    PERFORM interno.sp_reservaciones_exigir_acceso(v_actor, p_id_reservacion);

    RETURN QUERY
    SELECT p.id_pago, p.tipo, p.metodo, p.monto, p.estado, p.pasarela, p.id_pago_origen,
           p.confirmado_en, p.creado_en, r.total, s.pagado, s.saldo
      FROM reservacion r
     CROSS JOIN interno.sp_pagos_resumen(r.id_reservacion) s
      LEFT JOIN pago p ON p.id_reservacion = r.id_reservacion
     WHERE r.id_reservacion = p_id_reservacion
     ORDER BY p.creado_en, p.id_pago;
END;
$$;

CREATE OR REPLACE FUNCTION sp_pagos_listar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_tipo              TEXT,
    p_metodo            TEXT,
    p_estado            TEXT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_pagina            INTEGER,
    p_tamano            INTEGER,
    p_orden             TEXT,
    p_direccion         TEXT)
RETURNS TABLE (
    id_pago          BIGINT,
    id_reservacion   BIGINT,
    codigo           VARCHAR,
    cliente          TEXT,
    tipo             VARCHAR,
    metodo           VARCHAR,
    monto            DECIMAL(10,2),
    estado           VARCHAR,
    registrado_por   CITEXT,
    confirmado_en    TIMESTAMPTZ,
    creado_en        TIMESTAMPTZ,
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'PAGOS_VER');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    PERFORM interno.sp_comun_validar_direccion(p_direccion);
    IF p_orden IS NULL OR p_orden NOT IN ('confirmado_en', 'monto', 'creado_en') THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_invalido', 'Orden no válido: use confirmado_en, monto o creado_en');
    END IF;

    RETURN QUERY
    SELECT p.id_pago, r.id_reservacion, r.codigo, c.nombres || ' ' || c.apellidos, p.tipo, p.metodo,
           p.monto, p.estado, u.correo, p.confirmado_en, p.creado_en, count(*) OVER ()
      FROM pago p
      JOIN reservacion r ON r.id_reservacion = p.id_reservacion
      JOIN cliente c ON c.id_cliente = r.id_cliente
      LEFT JOIN usuario u ON u.id_usuario = p.registrado_por
     WHERE r.id_hotel = p_id_hotel
       AND (p_tipo IS NULL OR p.tipo = p_tipo)
       AND (p_metodo IS NULL OR p.metodo = p_metodo)
       AND (p_estado IS NULL OR p.estado = p_estado)
       AND (p_fecha_desde IS NULL OR (p.confirmado_en AT TIME ZONE 'America/Guatemala')::date >= p_fecha_desde)
       AND (p_fecha_hasta IS NULL OR (p.confirmado_en AT TIME ZONE 'America/Guatemala')::date <= p_fecha_hasta)
     ORDER BY
        CASE WHEN p_orden = 'confirmado_en' AND p_direccion = 'asc'  THEN p.confirmado_en END ASC NULLS LAST,
        CASE WHEN p_orden = 'confirmado_en' AND p_direccion = 'desc' THEN p.confirmado_en END DESC NULLS LAST,
        CASE WHEN p_orden = 'monto'         AND p_direccion = 'asc'  THEN p.monto END ASC,
        CASE WHEN p_orden = 'monto'         AND p_direccion = 'desc' THEN p.monto END DESC,
        CASE WHEN p_orden = 'creado_en'     AND p_direccion = 'asc'  THEN p.creado_en END ASC,
        CASE WHEN p_orden = 'creado_en'     AND p_direccion = 'desc' THEN p.creado_en END DESC,
        p.id_pago
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_pagos_iniciar_anticipo(BIGINT, BIGINT, TEXT, UUID),
    sp_pagos_confirmar_pasarela(TEXT, TEXT, TEXT, JSONB, BIGINT, TEXT, DECIMAL, BOOLEAN),
    sp_pagos_registrar_en_hotel(BIGINT, BIGINT, TEXT, TEXT, DECIMAL, UUID),
    sp_pagos_reembolsar(BIGINT, BIGINT, DECIMAL, TEXT, TEXT, UUID),
    sp_pagos_listar_por_reservacion(BIGINT, BIGINT),
    sp_pagos_listar(BIGINT, BIGINT, TEXT, TEXT, TEXT, DATE, DATE, INTEGER, INTEGER, TEXT, TEXT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('024_sp_pagos.sql');