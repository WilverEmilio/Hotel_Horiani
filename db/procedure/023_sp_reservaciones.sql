-- =============================================================================
-- 023_sp_reservaciones.sql
-- Disponibilidad y reservaciones (RN-03), incluido el uso de cupones (RN-05).
--
-- Garantías de concurrencia:
--   * Antes de revisar si una habitación está libre se bloquea su fila
--     (SELECT ... FOR UPDATE). Dos reservaciones que compiten por la misma
--     habitación se atienden una después de la otra.
--   * La restricción EXCLUDE de reservacion_habitacion es la última barrera.
--   * El cupón se bloquea con FOR UPDATE y su límite lo protege un CHECK.
--   * La llave de idempotencia se serializa con un advisory lock: un doble
--     clic o un reintento devuelve la misma reservación sin crear otra.
-- =============================================================================

CREATE OR REPLACE FUNCTION interno.sp_reservaciones_validar_fechas(p_fecha_entrada DATE, p_fecha_salida DATE)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_fecha_entrada IS NULL OR p_fecha_salida IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'fechas_requeridas', 'Las fechas de entrada y salida son obligatorias');
    END IF;
    IF p_fecha_entrada < interno.sp_comun_hoy() THEN
        PERFORM interno.sp_comun_error('HH422', 'fecha_pasada', 'No se puede reservar en fechas pasadas');
    END IF;
    IF p_fecha_salida <= p_fecha_entrada THEN
        PERFORM interno.sp_comun_error('HH422', 'minimo_una_noche', 'La salida debe ser al menos un día después de la entrada');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_reservaciones_calcular_noches(
    p_id_tipo_habitacion  BIGINT,
    p_fecha_entrada       DATE,
    p_fecha_salida        DATE)
RETURNS TABLE (fecha DATE, precio_noche DECIMAL(10,2), id_tarifa_especial BIGINT)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT d.dia::date, COALESCE(te.precio_noche, th.precio_base), te.id_tarifa_especial
      FROM tipo_habitacion th
     CROSS JOIN generate_series(p_fecha_entrada::timestamp, (p_fecha_salida - 1)::timestamp,
                                interval '1 day') AS d(dia)
      LEFT JOIN tarifa_especial te
             ON te.id_tipo_habitacion = th.id_tipo_habitacion
            AND te.activo
            AND te.periodo @> d.dia::date
     WHERE th.id_tipo_habitacion = p_id_tipo_habitacion
     ORDER BY d.dia;
$$;
CREATE OR REPLACE FUNCTION interno.sp_reservaciones_habitacion_libre(p_id_habitacion BIGINT, p_periodo DATERANGE)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM habitacion h
         WHERE h.id_habitacion = p_id_habitacion
           AND h.activo
           AND h.estado <> 'fuera_de_servicio'
           AND NOT EXISTS (
               SELECT 1
                 FROM reservacion_habitacion rh
                 JOIN reservacion r ON r.id_reservacion = rh.id_reservacion
                WHERE rh.id_habitacion = h.id_habitacion
                  AND rh.activa
                  AND rh.periodo && p_periodo
                  AND NOT (r.estado = 'pendiente_pago' AND r.expira_en <= now()))
           AND NOT EXISTS (
               SELECT 1
                 FROM bloqueo_habitacion b
                WHERE b.id_habitacion = h.id_habitacion
                  AND b.activo
                  AND b.periodo && p_periodo));
$$;

CREATE OR REPLACE FUNCTION interno.sp_reservaciones_cambiar_estado(
    p_id_reservacion  BIGINT,
    p_estado_nuevo    TEXT,
    p_id_usuario      BIGINT,
    p_motivo          TEXT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_res        reservacion%ROWTYPE;
    v_id_cupon   BIGINT;
BEGIN
    SELECT * INTO v_res FROM reservacion r WHERE r.id_reservacion = p_id_reservacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'reservacion_no_encontrada', 'Reservación no encontrada');
    END IF;

    UPDATE reservacion r
       SET estado             = p_estado_nuevo,
           cancelada_en       = CASE WHEN p_estado_nuevo = 'cancelada' THEN now() ELSE r.cancelada_en END,
           motivo_cancelacion = CASE WHEN p_estado_nuevo = 'cancelada' THEN p_motivo ELSE r.motivo_cancelacion END,
           checkin_en         = CASE WHEN p_estado_nuevo = 'en_curso' THEN now() ELSE r.checkin_en END,
           checkout_en        = CASE WHEN p_estado_nuevo = 'finalizada' THEN now() ELSE r.checkout_en END
     WHERE r.id_reservacion = p_id_reservacion;

    IF p_estado_nuevo IN ('cancelada', 'expirada', 'no_presentado', 'finalizada') THEN
        UPDATE reservacion_habitacion rh SET activa = FALSE WHERE rh.id_reservacion = p_id_reservacion;
    END IF;

    IF p_estado_nuevo IN ('cancelada', 'expirada') THEN
        UPDATE cupon_uso cu SET estado = 'devuelto', devuelto_en = now()
         WHERE cu.id_reservacion = p_id_reservacion AND cu.estado = 'aplicado'
        RETURNING cu.id_cupon INTO v_id_cupon;
        IF v_id_cupon IS NOT NULL THEN
            UPDATE cupon c SET usos_actuales = c.usos_actuales - 1 WHERE c.id_cupon = v_id_cupon;
        END IF;
    END IF;

    INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo)
    VALUES (p_id_reservacion, v_res.estado, p_estado_nuevo, p_id_usuario, p_motivo);

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario, v_res.id_hotel, 'reservaciones', 'reservacion',
        p_id_reservacion::text, 'cambio_estado',
        jsonb_build_object('estado', v_res.estado),
        jsonb_build_object('estado', p_estado_nuevo, 'motivo', p_motivo));
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_reservaciones_exigir_acceso(p_actor interno.tp_actor, p_id_reservacion BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id_hotel    BIGINT;
    v_id_cliente  BIGINT;
BEGIN
    SELECT r.id_hotel, r.id_cliente INTO v_id_hotel, v_id_cliente
      FROM reservacion r WHERE r.id_reservacion = p_id_reservacion;

    IF NOT interno.sp_comun_tiene_permiso(p_actor, 'RESERVACIONES_GESTIONAR') THEN
        PERFORM interno.sp_comun_exigir_permiso(p_actor, 'RESERVAR');
        IF v_id_hotel IS NULL OR v_id_cliente IS DISTINCT FROM p_actor.id_cliente THEN
            PERFORM interno.sp_comun_error('HH404', 'reservacion_no_encontrada', 'Reservación no encontrada');
        END IF;
        RETURN v_id_hotel;
    END IF;

    IF v_id_hotel IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'reservacion_no_encontrada', 'Reservación no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(p_actor, v_id_hotel);
    RETURN v_id_hotel;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_expirar_pendientes()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id     BIGINT;
    v_total  INTEGER := 0;
BEGIN
    FOR v_id IN
        SELECT r.id_reservacion
          FROM reservacion r
         WHERE r.estado = 'pendiente_pago' AND r.expira_en <= now()
         ORDER BY r.id_reservacion
           FOR UPDATE SKIP LOCKED
    LOOP
        PERFORM interno.sp_reservaciones_cambiar_estado(v_id, 'expirada', NULL,
            'Venció el tiempo para pagar el anticipo');
        v_total := v_total + 1;
    END LOOP;
    RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_consultar_disponibilidad(
    p_id_hotel       BIGINT,
    p_fecha_entrada  DATE,
    p_fecha_salida   DATE,
    p_huespedes      INTEGER)
RETURNS TABLE (
    id_tipo_habitacion        BIGINT,
    nombre                    VARCHAR,
    descripcion               TEXT,
    capacidad_maxima          INTEGER,
    habitaciones_disponibles  INTEGER,
    noches                    INTEGER,
    precio_estancia           DECIMAL(10,2),
    precio_noche_minimo       DECIMAL(10,2),
    precio_noche_maximo       DECIMAL(10,2))
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_periodo DATERANGE;
BEGIN
    PERFORM interno.sp_reservaciones_validar_fechas(p_fecha_entrada, p_fecha_salida);
    IF p_huespedes IS NOT NULL AND p_huespedes < 1 THEN
        PERFORM interno.sp_comun_error('HH422', 'huespedes_invalido', 'El número de huéspedes debe ser 1 o más');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hotel h WHERE h.id_hotel = p_id_hotel AND h.activo) THEN
        PERFORM interno.sp_comun_error('HH404', 'hotel_no_encontrado', 'Hotel no encontrado');
    END IF;

    v_periodo := daterange(p_fecha_entrada, p_fecha_salida, '[)');

    RETURN QUERY
    SELECT th.id_tipo_habitacion, th.nombre, th.descripcion, th.capacidad_maxima,
           (SELECT count(*)::int FROM habitacion h
             WHERE h.id_tipo_habitacion = th.id_tipo_habitacion
               AND interno.sp_reservaciones_habitacion_libre(h.id_habitacion, v_periodo)),
           (p_fecha_salida - p_fecha_entrada),
           pn.total, pn.minimo, pn.maximo
      FROM tipo_habitacion th
     CROSS JOIN LATERAL (
           SELECT sum(n.precio_noche) AS total, min(n.precio_noche) AS minimo, max(n.precio_noche) AS maximo
             FROM interno.sp_reservaciones_calcular_noches(th.id_tipo_habitacion, p_fecha_entrada, p_fecha_salida) n
           ) pn
     WHERE th.id_hotel = p_id_hotel
       AND th.activo
       AND (p_huespedes IS NULL OR th.capacidad_maxima >= p_huespedes)
     ORDER BY th.precio_base, th.nombre;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_listar_habitaciones_libres(
    p_id_hotel            BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_fecha_entrada       DATE,
    p_fecha_salida        DATE)
RETURNS TABLE (id_habitacion BIGINT, numero VARCHAR, piso INTEGER)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_periodo DATERANGE;
BEGIN
    PERFORM interno.sp_reservaciones_validar_fechas(p_fecha_entrada, p_fecha_salida);
    v_periodo := daterange(p_fecha_entrada, p_fecha_salida, '[)');

    RETURN QUERY
    SELECT h.id_habitacion, h.numero, h.piso
      FROM habitacion h
      JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion AND th.activo
      JOIN hotel ho ON ho.id_hotel = h.id_hotel AND ho.activo
     WHERE h.id_hotel = p_id_hotel
       AND h.id_tipo_habitacion = p_id_tipo_habitacion
       AND interno.sp_reservaciones_habitacion_libre(h.id_habitacion, v_periodo)
     ORDER BY h.numero;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_crear(
    p_id_usuario_actor    BIGINT,
    p_id_hotel            BIGINT,
    p_fecha_entrada       DATE,
    p_fecha_salida        DATE,
    p_habitaciones        JSONB,
    p_codigo_cupon        TEXT,
    p_origen              TEXT,
    p_llave_idempotencia  UUID,
    p_id_cliente          BIGINT DEFAULT NULL)
RETURNS TABLE (
    id_reservacion  BIGINT,
    codigo          VARCHAR,
    estado          VARCHAR,
    subtotal        DECIMAL(10,2),
    descuento       DECIMAL(10,2),
    total           DECIMAL(10,2),
    base_imponible  DECIMAL(10,2),
    iva             DECIMAL(10,2),
    monto_anticipo  DECIMAL(10,2),
    expira_en       TIMESTAMPTZ,
    ya_existia      BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor        interno.tp_actor;
    v_id_cliente   BIGINT;
    v_origen       TEXT;
    v_config       hotel_configuracion%ROWTYPE;
    v_periodo      DATERANGE;
    v_item         JSONB;
    v_id_tipo      BIGINT;
    v_huespedes    INTEGER;
    v_id_hab       BIGINT;
    v_capacidad    INTEGER;
    v_candidata    BIGINT;
    v_tipos        BIGINT[]  := '{}';
    v_habs         BIGINT[]  := '{}';
    v_huesps       INTEGER[] := '{}';
    v_subtotales   NUMERIC[] := '{}';
    v_sub_hab      NUMERIC;
    v_subtotal     NUMERIC   := 0;
    v_descuento    NUMERIC   := 0;
    v_total        NUMERIC;
    v_base         NUMERIC;
    v_iva          NUMERIC;
    v_anticipo     NUMERIC;
    v_estado       TEXT;
    v_expira       TIMESTAMPTZ;
    v_cupon        cupon%ROWTYPE;
    v_base_cupon   NUMERIC   := 0;
    v_usos_cliente INTEGER;
    v_hoy          DATE;
    v_id_res       BIGINT;
    v_codigo       TEXT;
    v_id_rh        BIGINT;
    i              INTEGER;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    v_hoy := interno.sp_comun_hoy();

    IF NOT interno.sp_comun_tiene_permiso(v_actor, 'RESERVACIONES_GESTIONAR') THEN
        PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVAR');
        IF v_actor.id_cliente IS NULL THEN
            PERFORM interno.sp_comun_error('HH403', 'cliente_inactivo', 'Su cuenta de cliente no está activa');
        END IF;
        v_id_cliente := v_actor.id_cliente;
        IF p_origen IS NULL OR p_origen NOT IN ('web', 'movil') THEN
            PERFORM interno.sp_comun_error('HH422', 'origen_invalido', 'El origen debe ser web o movil');
        END IF;
        v_origen := p_origen;
    ELSE
        PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
        IF p_id_cliente IS NULL OR NOT EXISTS (
            SELECT 1 FROM cliente c WHERE c.id_cliente = p_id_cliente AND c.activo) THEN
            PERFORM interno.sp_comun_error('HH422', 'cliente_requerido', 'Seleccione un cliente activo para la reservación');
        END IF;
        v_id_cliente := p_id_cliente;
        v_origen := 'recepcion';
    END IF;

    IF p_llave_idempotencia IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'llave_requerida', 'Falta la llave de idempotencia');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(v_id_cliente::text || ':' || p_llave_idempotencia::text, 0));

    RETURN QUERY
    SELECT r.id_reservacion, r.codigo, r.estado, r.subtotal, r.descuento, r.total,
           r.base_imponible, r.iva, r.monto_anticipo, r.expira_en, TRUE
      FROM reservacion r
     WHERE r.id_cliente = v_id_cliente AND r.llave_idempotencia = p_llave_idempotencia;
    IF FOUND THEN
        RETURN;
    END IF;

    PERFORM interno.sp_reservaciones_validar_fechas(p_fecha_entrada, p_fecha_salida);
    v_periodo := daterange(p_fecha_entrada, p_fecha_salida, '[)');

    SELECT hc.* INTO v_config
      FROM hotel_configuracion hc
      JOIN hotel h ON h.id_hotel = hc.id_hotel AND h.activo
     WHERE hc.id_hotel = p_id_hotel;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'hotel_no_encontrado', 'Hotel no encontrado');
    END IF;

    IF p_habitaciones IS NULL OR jsonb_typeof(p_habitaciones) <> 'array'
       OR jsonb_array_length(p_habitaciones) = 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'habitaciones_requeridas', 'Seleccione al menos una habitación');
    END IF;

    PERFORM sp_reservaciones_expirar_pendientes();

    FOR v_item IN SELECT x FROM jsonb_array_elements(p_habitaciones) AS t(x) LOOP
        BEGIN
            v_id_tipo   := (v_item ->> 'id_tipo_habitacion')::bigint;
            v_huespedes := (v_item ->> 'huespedes')::integer;
            v_id_hab    := (v_item ->> 'id_habitacion')::bigint;
        EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
            PERFORM interno.sp_comun_error('HH422', 'habitacion_formato', 'Cada habitación debe indicar tipo y huéspedes como números');
        END;

        SELECT th.capacidad_maxima INTO v_capacidad
          FROM tipo_habitacion th
         WHERE th.id_tipo_habitacion = v_id_tipo AND th.id_hotel = p_id_hotel AND th.activo;
        IF NOT FOUND THEN
            PERFORM interno.sp_comun_error('HH422', 'tipo_invalido', 'El tipo de habitación no existe en este hotel');
        END IF;
        IF v_huespedes IS NULL OR v_huespedes < 1 OR v_huespedes > v_capacidad THEN
            PERFORM interno.sp_comun_error('HH422', 'capacidad_excedida',
                format('Cada habitación de este tipo admite de 1 a %s huéspedes', v_capacidad));
        END IF;

        IF v_id_hab IS NOT NULL THEN
            IF v_id_hab = ANY (v_habs) THEN
                PERFORM interno.sp_comun_error('HH422', 'habitacion_repetida', 'La misma habitación aparece dos veces');
            END IF;
            PERFORM 1 FROM habitacion h
             WHERE h.id_habitacion = v_id_hab AND h.id_hotel = p_id_hotel AND h.id_tipo_habitacion = v_id_tipo
               FOR UPDATE;
            IF NOT FOUND THEN
                PERFORM interno.sp_comun_error('HH422', 'habitacion_invalida', 'La habitación no pertenece a ese tipo y hotel');
            END IF;
            IF NOT interno.sp_reservaciones_habitacion_libre(v_id_hab, v_periodo) THEN
                PERFORM interno.sp_comun_error('HH409', 'habitacion_no_disponible',
                    'La habitación elegida ya no está disponible en esas fechas');
            END IF;
        ELSE
            v_id_hab := NULL;
            FOR v_candidata IN
                SELECT h.id_habitacion FROM habitacion h
                 WHERE h.id_hotel = p_id_hotel AND h.id_tipo_habitacion = v_id_tipo
                   AND h.activo AND h.estado <> 'fuera_de_servicio'
                   AND NOT (h.id_habitacion = ANY (v_habs))
                 ORDER BY h.numero
            LOOP
                PERFORM 1 FROM habitacion h WHERE h.id_habitacion = v_candidata FOR UPDATE;
                IF interno.sp_reservaciones_habitacion_libre(v_candidata, v_periodo) THEN
                    v_id_hab := v_candidata;
                    EXIT;
                END IF;
            END LOOP;
            IF v_id_hab IS NULL THEN
                PERFORM interno.sp_comun_error('HH409', 'sin_disponibilidad',
                    'No quedan habitaciones de ese tipo disponibles en esas fechas');
            END IF;
        END IF;

        SELECT sum(n.precio_noche) INTO v_sub_hab
          FROM interno.sp_reservaciones_calcular_noches(v_id_tipo, p_fecha_entrada, p_fecha_salida) n;

        v_tipos      := v_tipos || v_id_tipo;
        v_habs       := v_habs || v_id_hab;
        v_huesps     := v_huesps || v_huespedes;
        v_subtotales := v_subtotales || v_sub_hab;
        v_subtotal   := v_subtotal + v_sub_hab;
    END LOOP;

    IF NULLIF(btrim(p_codigo_cupon), '') IS NOT NULL THEN
        SELECT c.* INTO v_cupon FROM cupon c WHERE c.codigo = btrim(p_codigo_cupon)::citext FOR UPDATE;
        IF NOT FOUND OR NOT v_cupon.activo THEN
            PERFORM interno.sp_comun_error('HH422', 'cupon_invalido', 'El cupón no existe');
        END IF;
        IF v_hoy < lower(v_cupon.vigencia) THEN
            PERFORM interno.sp_comun_error('HH422', 'cupon_no_vigente',
                format('El cupón se puede usar a partir del %s', to_char(lower(v_cupon.vigencia), 'DD/MM/YYYY')));
        END IF;
        IF NOT (v_cupon.vigencia @> v_hoy) THEN
            PERFORM interno.sp_comun_error('HH422', 'cupon_vencido', 'El cupón está vencido');
        END IF;
        IF v_cupon.limite_usos_total IS NOT NULL AND v_cupon.usos_actuales >= v_cupon.limite_usos_total THEN
            PERFORM interno.sp_comun_error('HH422', 'cupon_agotado', 'El cupón ya alcanzó su límite de usos');
        END IF;
        IF v_cupon.id_hotel IS NOT NULL AND v_cupon.id_hotel <> p_id_hotel THEN
            PERFORM interno.sp_comun_error('HH422', 'cupon_no_aplica', 'El cupón no aplica para este hotel');
        END IF;
        IF v_cupon.limite_usos_cliente IS NOT NULL THEN
            SELECT count(*) INTO v_usos_cliente
              FROM cupon_uso cu
             WHERE cu.id_cupon = v_cupon.id_cupon AND cu.id_cliente = v_id_cliente AND cu.estado = 'aplicado';
            IF v_usos_cliente >= v_cupon.limite_usos_cliente THEN
                PERFORM interno.sp_comun_error('HH422', 'cupon_limite_cliente', 'Ya usó este cupón el máximo de veces permitido');
            END IF;
        END IF;

        FOR i IN 1 .. array_length(v_tipos, 1) LOOP
            IF v_cupon.id_tipo_habitacion IS NULL OR v_cupon.id_tipo_habitacion = v_tipos[i] THEN
                v_base_cupon := v_base_cupon + v_subtotales[i];
            END IF;
        END LOOP;
        IF v_base_cupon = 0 THEN
            PERFORM interno.sp_comun_error('HH422', 'cupon_no_aplica', 'El cupón no aplica a las habitaciones seleccionadas');
        END IF;
        IF v_base_cupon < v_cupon.monto_minimo THEN
            PERFORM interno.sp_comun_error('HH422', 'cupon_monto_minimo',
                format('El cupón requiere un monto mínimo de Q%s', to_char(v_cupon.monto_minimo, 'FM999999990.00')));
        END IF;

        v_descuento := CASE v_cupon.tipo
            WHEN 'porcentaje' THEN round(v_base_cupon * v_cupon.valor / 100, 2)
            ELSE least(v_cupon.valor, v_base_cupon)
        END;

        UPDATE cupon c SET usos_actuales = c.usos_actuales + 1 WHERE c.id_cupon = v_cupon.id_cupon;
    END IF;

    v_total    := v_subtotal - v_descuento;
    v_base     := round(v_total / 1.12, 2);
    v_iva      := v_total - v_base;
    v_anticipo := ceil(v_total * v_config.porcentaje_anticipo) / 100;

    IF v_anticipo = 0 THEN
        v_estado := 'confirmada';
        v_expira := NULL;
    ELSE
        v_estado := 'pendiente_pago';
        v_expira := now() + make_interval(mins => v_config.minutos_bloqueo_pago);
    END IF;

    v_id_res := nextval(pg_get_serial_sequence('reservacion', 'id_reservacion'));
    v_codigo := 'HOR-' || to_char(v_hoy, 'YYYY') || '-' || lpad(v_id_res::text, 6, '0');

    INSERT INTO reservacion (id_reservacion, codigo, id_hotel, id_cliente, fecha_entrada, fecha_salida,
                             estado, origen, creado_por, subtotal, descuento, total, base_imponible, iva,
                             monto_anticipo, id_cupon, codigo_cupon, expira_en, llave_idempotencia)
    OVERRIDING SYSTEM VALUE
    VALUES (v_id_res, v_codigo, p_id_hotel, v_id_cliente, p_fecha_entrada, p_fecha_salida,
            v_estado, v_origen, p_id_usuario_actor, v_subtotal, v_descuento, v_total, v_base, v_iva,
            v_anticipo, v_cupon.id_cupon, v_cupon.codigo, v_expira, p_llave_idempotencia);

    FOR i IN 1 .. array_length(v_habs, 1) LOOP
        INSERT INTO reservacion_habitacion (id_reservacion, id_hotel, id_habitacion, id_tipo_habitacion,
                                            periodo, huespedes, subtotal)
        VALUES (v_id_res, p_id_hotel, v_habs[i], v_tipos[i], v_periodo, v_huesps[i], v_subtotales[i])
        RETURNING id_reservacion_habitacion INTO v_id_rh;

        INSERT INTO reservacion_noche (id_reservacion_habitacion, fecha, precio_noche, id_tarifa_especial)
        SELECT v_id_rh, n.fecha, n.precio_noche, n.id_tarifa_especial
          FROM interno.sp_reservaciones_calcular_noches(v_tipos[i], p_fecha_entrada, p_fecha_salida) n;
    END LOOP;

    IF v_cupon.id_cupon IS NOT NULL THEN
        INSERT INTO cupon_uso (id_cupon, id_cliente, id_reservacion, monto_descuento)
        VALUES (v_cupon.id_cupon, v_id_cliente, v_id_res, v_descuento);
    END IF;

    INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo)
    VALUES (v_id_res, NULL, v_estado, p_id_usuario_actor, 'Reservación creada');

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'reservaciones', 'reservacion',
        v_id_res::text, 'crear', NULL,
        jsonb_build_object('codigo', v_codigo, 'estado', v_estado, 'total', v_total,
                           'habitaciones', to_jsonb(v_habs), 'cupon', v_cupon.codigo));

    RETURN QUERY
    SELECT v_id_res, v_codigo::varchar, v_estado::varchar, v_subtotal::numeric(10,2), v_descuento::numeric(10,2),
           v_total::numeric(10,2), v_base::numeric(10,2), v_iva::numeric(10,2), v_anticipo::numeric(10,2),
           v_expira, FALSE;
EXCEPTION

    WHEN exclusion_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'habitacion_no_disponible',
            'Otra persona acaba de reservar esa habitación. Intente de nuevo');
    WHEN deadlock_detected THEN
        PERFORM interno.sp_comun_error('HH409', 'reintentar', 'Hubo mucha demanda en este momento. Intente de nuevo');
END;
$$;


CREATE OR REPLACE FUNCTION sp_reservaciones_obtener(p_id_usuario_actor BIGINT, p_id_reservacion BIGINT)
RETURNS TABLE (
    id_reservacion  BIGINT,
    codigo          VARCHAR,
    id_hotel        BIGINT,
    hotel           VARCHAR,
    id_cliente      BIGINT,
    cliente         TEXT,
    fecha_entrada   DATE,
    fecha_salida    DATE,
    noches          INTEGER,
    estado          VARCHAR,
    origen          VARCHAR,
    subtotal        DECIMAL(10,2),
    descuento       DECIMAL(10,2),
    total           DECIMAL(10,2),
    base_imponible  DECIMAL(10,2),
    iva             DECIMAL(10,2),
    monto_anticipo  DECIMAL(10,2),
    codigo_cupon    VARCHAR,
    expira_en       TIMESTAMPTZ,
    creado_en       TIMESTAMPTZ,
    habitaciones    JSONB,
    historial       JSONB)
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
    SELECT r.id_reservacion, r.codigo, r.id_hotel, ho.nombre, r.id_cliente,
           c.nombres || ' ' || c.apellidos,
           r.fecha_entrada, r.fecha_salida, (r.fecha_salida - r.fecha_entrada),
           r.estado, r.origen, r.subtotal, r.descuento, r.total, r.base_imponible, r.iva, r.monto_anticipo,
           r.codigo_cupon, r.expira_en, r.creado_en,
           (SELECT jsonb_agg(jsonb_build_object(
                       'id_reservacion_habitacion', rh.id_reservacion_habitacion,
                       'id_habitacion', h.id_habitacion,
                       'numero', h.numero,
                       'tipo', th.nombre,
                       'huespedes', rh.huespedes,
                       'subtotal', rh.subtotal,
                       'noches', (SELECT jsonb_agg(jsonb_build_object('fecha', rn.fecha, 'precio', rn.precio_noche)
                                                   ORDER BY rn.fecha)
                                    FROM reservacion_noche rn
                                   WHERE rn.id_reservacion_habitacion = rh.id_reservacion_habitacion))
                   ORDER BY h.numero)
              FROM reservacion_habitacion rh
              JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
              JOIN tipo_habitacion th ON th.id_tipo_habitacion = rh.id_tipo_habitacion
             WHERE rh.id_reservacion = r.id_reservacion),
           CASE WHEN interno.sp_comun_tiene_permiso(v_actor, 'RESERVACIONES_GESTIONAR') THEN
               (SELECT jsonb_agg(jsonb_build_object(
                           'estado_anterior', eh.estado_anterior, 'estado_nuevo', eh.estado_nuevo,
                           'motivo', eh.motivo, 'id_usuario', eh.id_usuario, 'fecha', eh.creado_en)
                       ORDER BY eh.creado_en, eh.id_reservacion_estado_historial)
                  FROM reservacion_estado_historial eh WHERE eh.id_reservacion = r.id_reservacion)
           END
      FROM reservacion r
      JOIN hotel ho ON ho.id_hotel = r.id_hotel
      JOIN cliente c ON c.id_cliente = r.id_cliente
     WHERE r.id_reservacion = p_id_reservacion;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_listar_mias(
    p_id_usuario_actor  BIGINT,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_reservacion   BIGINT,
    codigo           VARCHAR,
    hotel            VARCHAR,
    fecha_entrada    DATE,
    fecha_salida     DATE,
    estado           VARCHAR,
    total            DECIMAL(10,2),
    monto_anticipo   DECIMAL(10,2),
    habitaciones     INTEGER,
    expira_en        TIMESTAMPTZ,
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVAR');
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);

    RETURN QUERY
    SELECT r.id_reservacion, r.codigo, ho.nombre, r.fecha_entrada, r.fecha_salida, r.estado,
           r.total, r.monto_anticipo,
           (SELECT count(*)::int FROM reservacion_habitacion rh WHERE rh.id_reservacion = r.id_reservacion),
           r.expira_en, count(*) OVER ()
      FROM reservacion r
      JOIN hotel ho ON ho.id_hotel = r.id_hotel
     WHERE r.id_cliente = v_actor.id_cliente
     ORDER BY r.fecha_entrada DESC, r.id_reservacion DESC
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;
CREATE OR REPLACE FUNCTION sp_reservaciones_listar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_estado            TEXT,
    p_id_cliente        BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_busqueda          TEXT,
    p_pagina            INTEGER,
    p_tamano            INTEGER,
    p_orden             TEXT,
    p_direccion         TEXT)
RETURNS TABLE (
    id_reservacion   BIGINT,
    codigo           VARCHAR,
    id_cliente       BIGINT,
    cliente          TEXT,
    fecha_entrada    DATE,
    fecha_salida     DATE,
    estado           VARCHAR,
    origen           VARCHAR,
    total            DECIMAL(10,2),
    monto_anticipo   DECIMAL(10,2),
    habitaciones     TEXT,
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    PERFORM interno.sp_comun_validar_direccion(p_direccion);
    IF p_orden IS NULL OR p_orden NOT IN ('fecha_entrada', 'creado_en', 'total', 'codigo') THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_invalido',
            'Orden no válido: use fecha_entrada, creado_en, total o codigo');
    END IF;

    RETURN QUERY
    SELECT r.id_reservacion, r.codigo, r.id_cliente, c.nombres || ' ' || c.apellidos,
           r.fecha_entrada, r.fecha_salida, r.estado, r.origen, r.total, r.monto_anticipo,
           (SELECT string_agg(h.numero, ', ' ORDER BY h.numero)
              FROM reservacion_habitacion rh JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
             WHERE rh.id_reservacion = r.id_reservacion),
           r.creado_en, count(*) OVER ()
      FROM reservacion r
      JOIN cliente c ON c.id_cliente = r.id_cliente
     WHERE r.id_hotel = p_id_hotel
       AND (p_estado IS NULL OR r.estado = p_estado)
       AND (p_id_cliente IS NULL OR r.id_cliente = p_id_cliente)
       AND (p_fecha_desde IS NULL OR r.fecha_entrada >= p_fecha_desde)
       AND (p_fecha_hasta IS NULL OR r.fecha_entrada <= p_fecha_hasta)
       AND (p_busqueda IS NULL
            OR r.codigo ILIKE '%' || p_busqueda || '%'
            OR (c.nombres || ' ' || c.apellidos) ILIKE '%' || p_busqueda || '%'
            OR c.numero_documento = btrim(p_busqueda))
     ORDER BY
        CASE WHEN p_orden = 'fecha_entrada' AND p_direccion = 'asc'  THEN r.fecha_entrada END ASC,
        CASE WHEN p_orden = 'fecha_entrada' AND p_direccion = 'desc' THEN r.fecha_entrada END DESC,
        CASE WHEN p_orden = 'creado_en'     AND p_direccion = 'asc'  THEN r.creado_en END ASC,
        CASE WHEN p_orden = 'creado_en'     AND p_direccion = 'desc' THEN r.creado_en END DESC,
        CASE WHEN p_orden = 'total'         AND p_direccion = 'asc'  THEN r.total END ASC,
        CASE WHEN p_orden = 'total'         AND p_direccion = 'desc' THEN r.total END DESC,
        CASE WHEN p_orden = 'codigo'        AND p_direccion = 'asc'  THEN r.codigo END ASC,
        CASE WHEN p_orden = 'codigo'        AND p_direccion = 'desc' THEN r.codigo END DESC,
        r.id_reservacion
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_cancelar(
    p_id_usuario_actor  BIGINT,
    p_id_reservacion    BIGINT,
    p_motivo            TEXT)
RETURNS TABLE (
    id_reservacion       BIGINT,
    estado               VARCHAR,
    anticipo_pagado      DECIMAL(10,2),
    reembolso_sugerido   DECIMAL(10,2))
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_id_hotel  BIGINT;
    v_res       reservacion%ROWTYPE;
    v_config    hotel_configuracion%ROWTYPE;
    v_pagado    NUMERIC;
    v_reembolso NUMERIC;
    v_horas     NUMERIC;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    v_id_hotel := interno.sp_reservaciones_exigir_acceso(v_actor, p_id_reservacion);

    IF interno.sp_comun_tiene_permiso(v_actor, 'RESERVACIONES_GESTIONAR') THEN
        PERFORM interno.sp_comun_exigir_texto(p_motivo, 'motivo');
    END IF;

    SELECT r.* INTO v_res FROM reservacion r WHERE r.id_reservacion = p_id_reservacion FOR UPDATE;
    IF v_res.estado NOT IN ('pendiente_pago', 'confirmada') THEN
        PERFORM interno.sp_comun_error('HH409', 'no_cancelable',
            'Solo se pueden cancelar reservaciones pendientes de pago o confirmadas');
    END IF;

    PERFORM interno.sp_reservaciones_cambiar_estado(p_id_reservacion, 'cancelada', p_id_usuario_actor,
        COALESCE(NULLIF(btrim(p_motivo), ''), 'Cancelada por el cliente'));

    SELECT COALESCE(sum(CASE WHEN p.tipo = 'reembolso' THEN -p.monto ELSE p.monto END), 0) INTO v_pagado
      FROM pago p
     WHERE p.id_reservacion = p_id_reservacion AND p.estado = 'aprobado';

    SELECT hc.* INTO v_config FROM hotel_configuracion hc WHERE hc.id_hotel = v_id_hotel;
    IF v_config.horas_limite_cancelacion IS NOT NULL AND v_config.porcentaje_reembolso IS NOT NULL THEN
        v_horas := extract(epoch FROM (v_res.fecha_entrada::timestamp AT TIME ZONE 'America/Guatemala') - now()) / 3600;
        v_reembolso := CASE
            WHEN v_horas >= v_config.horas_limite_cancelacion THEN round(v_pagado * v_config.porcentaje_reembolso / 100, 2)
            ELSE 0
        END;
    END IF;

    RETURN QUERY SELECT p_id_reservacion, 'cancelada'::varchar, v_pagado::numeric(10,2), v_reembolso::numeric(10,2);
END;
$$;

CREATE OR REPLACE FUNCTION sp_reservaciones_reasignar_habitacion(
    p_id_usuario_actor           BIGINT,
    p_id_reservacion_habitacion  BIGINT,
    p_id_habitacion_nueva        BIGINT,
    p_motivo                     TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_rh        reservacion_habitacion%ROWTYPE;
    v_estado    VARCHAR;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_motivo, 'motivo');

    SELECT rh.* INTO v_rh FROM reservacion_habitacion rh
     WHERE rh.id_reservacion_habitacion = p_id_reservacion_habitacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'reservacion_no_encontrada', 'Habitación de la reservación no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_rh.id_hotel);

    SELECT r.estado INTO v_estado FROM reservacion r WHERE r.id_reservacion = v_rh.id_reservacion FOR UPDATE;
    IF v_estado NOT IN ('pendiente_pago', 'confirmada', 'en_curso') OR NOT v_rh.activa THEN
        PERFORM interno.sp_comun_error('HH409', 'no_reasignable', 'Esta reservación ya no se puede modificar');
    END IF;
    IF v_rh.id_habitacion = p_id_habitacion_nueva THEN
        RETURN;
    END IF;

    PERFORM 1 FROM habitacion h
     WHERE h.id_habitacion = p_id_habitacion_nueva AND h.id_hotel = v_rh.id_hotel
       AND h.id_tipo_habitacion = v_rh.id_tipo_habitacion
       FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH422', 'habitacion_invalida',
            'La nueva habitación debe ser del mismo tipo y del mismo hotel');
    END IF;
    IF NOT interno.sp_reservaciones_habitacion_libre(p_id_habitacion_nueva, v_rh.periodo) THEN
        PERFORM interno.sp_comun_error('HH409', 'habitacion_no_disponible', 'La nueva habitación no está libre en esas fechas');
    END IF;

    UPDATE reservacion_habitacion rh SET id_habitacion = p_id_habitacion_nueva
     WHERE rh.id_reservacion_habitacion = p_id_reservacion_habitacion;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_rh.id_hotel, 'reservaciones', 'reservacion_habitacion',
        p_id_reservacion_habitacion::text, 'modificar',
        jsonb_build_object('id_habitacion', v_rh.id_habitacion),
        jsonb_build_object('id_habitacion', p_id_habitacion_nueva, 'motivo', p_motivo));
EXCEPTION
    WHEN exclusion_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'habitacion_no_disponible', 'La nueva habitación no está libre en esas fechas');
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_reservaciones_expirar_pendientes(),
    sp_reservaciones_consultar_disponibilidad(BIGINT, DATE, DATE, INTEGER),
    sp_reservaciones_listar_habitaciones_libres(BIGINT, BIGINT, DATE, DATE),
    sp_reservaciones_crear(BIGINT, BIGINT, DATE, DATE, JSONB, TEXT, TEXT, UUID, BIGINT),
    sp_reservaciones_obtener(BIGINT, BIGINT),
    sp_reservaciones_listar_mias(BIGINT, INTEGER, INTEGER),
    sp_reservaciones_listar(BIGINT, BIGINT, TEXT, BIGINT, DATE, DATE, TEXT, INTEGER, INTEGER, TEXT, TEXT),
    sp_reservaciones_cancelar(BIGINT, BIGINT, TEXT),
    sp_reservaciones_reasignar_habitacion(BIGINT, BIGINT, BIGINT, TEXT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('023_sp_reservaciones.sql');