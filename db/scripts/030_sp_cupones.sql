-- =============================================================================
-- 030_sp_cupones.sql
-- Administración de cupones y vista previa del descuento (RN-05).
-- Las reglas para aplicar un cupón viven en interno.sp_cupones_calcular_descuento
-- (023), la misma que usa la reservación.
-- Alcance: un cupón sin hotel aplica en los 4 hoteles; solo el administrador
-- lo puede crear así. Quien no es administrador crea cupones de sus hoteles.
-- =============================================================================

CREATE OR REPLACE FUNCTION interno.sp_cupones_validar_alcance(
    p_actor               interno.tp_actor,
    p_id_hotel            BIGINT,
    p_id_tipo_habitacion  BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id_hotel       BIGINT := p_id_hotel;
    v_hotel_del_tipo BIGINT;
BEGIN
    IF p_id_tipo_habitacion IS NOT NULL THEN
        SELECT th.id_hotel INTO v_hotel_del_tipo FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion;
        IF NOT FOUND THEN
            PERFORM interno.sp_comun_error('HH422', 'tipo_invalido', 'El tipo de habitación no existe');
        END IF;
        IF v_id_hotel IS NOT NULL AND v_id_hotel <> v_hotel_del_tipo THEN
            PERFORM interno.sp_comun_error('HH422', 'tipo_de_otro_hotel', 'El tipo de habitación no es de ese hotel');
        END IF;
        v_id_hotel := v_hotel_del_tipo;
    END IF;

    IF v_id_hotel IS NULL THEN
        IF p_actor.rol <> 'administrador' THEN
            PERFORM interno.sp_comun_error('HH403', 'cupon_de_cadena',
                'Solo el administrador crea cupones para todos los hoteles; seleccione un hotel');
        END IF;
    ELSE
        PERFORM interno.sp_comun_exigir_hotel(p_actor, v_id_hotel);
    END IF;
    RETURN v_id_hotel;
END;
$$;

CREATE OR REPLACE FUNCTION sp_cupones_crear(
    p_id_usuario_actor     BIGINT,
    p_codigo               TEXT,
    p_descripcion          TEXT,
    p_tipo                 TEXT,
    p_valor                DECIMAL(10,2),
    p_fecha_inicio         DATE,
    p_fecha_fin            DATE,
    p_monto_minimo         DECIMAL(10,2),
    p_limite_usos_total    INTEGER,
    p_limite_usos_cliente  INTEGER,
    p_id_hotel             BIGINT,
    p_id_tipo_habitacion   BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_id_hotel     BIGINT;
    v_id           BIGINT;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CUPONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_codigo, 'código');
    IF p_fecha_inicio IS NULL OR p_fecha_fin IS NULL OR p_fecha_fin < p_fecha_inicio THEN
        PERFORM interno.sp_comun_error('HH422', 'fechas_invalidas', 'La fecha final no puede ser anterior a la inicial');
    END IF;
    v_id_hotel := interno.sp_cupones_validar_alcance(v_actor, p_id_hotel, p_id_tipo_habitacion);

    INSERT INTO cupon (codigo, descripcion, tipo, valor, vigencia, monto_minimo, limite_usos_total,
                       limite_usos_cliente, id_hotel, id_tipo_habitacion, creado_por)
    VALUES (upper(btrim(p_codigo)), NULLIF(btrim(p_descripcion), ''), p_tipo, p_valor,
            daterange(p_fecha_inicio, p_fecha_fin + 1, '[)'), COALESCE(p_monto_minimo, 0),
            p_limite_usos_total, p_limite_usos_cliente, v_id_hotel, p_id_tipo_habitacion, p_id_usuario_actor)
    RETURNING id_cupon INTO v_id;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'cupones', 'cupon', v_id::text,
        'crear', NULL, (SELECT to_jsonb(c) FROM cupon c WHERE c.id_cupon = v_id));
    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'cupon_duplicado', 'Ya existe un cupón con ese código');
    WHEN not_null_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'campo_requerido', 'Tipo y valor son obligatorios');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, CASE v_restriccion
            WHEN 'ck_cupon_codigo' THEN 'El código debe tener de 3 a 30 letras, números, guion o guion bajo'
            WHEN 'ck_cupon_tipo' THEN 'El tipo debe ser porcentaje o monto_fijo'
            WHEN 'ck_cupon_porcentaje' THEN 'Un porcentaje no puede ser mayor que 100'
            ELSE 'Los valores del cupón deben ser mayores que cero' END);
END;
$$;
CREATE OR REPLACE FUNCTION sp_cupones_actualizar(
    p_id_usuario_actor     BIGINT,
    p_id_cupon             BIGINT,
    p_codigo               TEXT,
    p_descripcion          TEXT,
    p_tipo                 TEXT,
    p_valor                DECIMAL(10,2),
    p_fecha_inicio         DATE,
    p_fecha_fin            DATE,
    p_monto_minimo         DECIMAL(10,2),
    p_limite_usos_total    INTEGER,
    p_limite_usos_cliente  INTEGER,
    p_id_hotel             BIGINT,
    p_id_tipo_habitacion   BIGINT,
    p_activo               BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_cupon        cupon%ROWTYPE;
    v_usado        BOOLEAN;
    v_id_hotel     BIGINT;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CUPONES_GESTIONAR');

    SELECT c.* INTO v_cupon FROM cupon c WHERE c.id_cupon = p_id_cupon FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'cupon_no_encontrado', 'Cupón no encontrado');
    END IF;
    IF v_cupon.id_hotel IS NULL THEN
        IF v_actor.rol <> 'administrador' THEN
            PERFORM interno.sp_comun_error('HH403', 'cupon_de_cadena', 'Solo el administrador modifica cupones de la cadena');
        END IF;
    ELSE
        PERFORM interno.sp_comun_exigir_hotel(v_actor, v_cupon.id_hotel);
    END IF;
    IF p_fecha_inicio IS NULL OR p_fecha_fin IS NULL OR p_fecha_fin < p_fecha_inicio THEN
        PERFORM interno.sp_comun_error('HH422', 'fechas_invalidas', 'La fecha final no puede ser anterior a la inicial');
    END IF;

    v_usado := EXISTS (SELECT 1 FROM cupon_uso cu WHERE cu.id_cupon = p_id_cupon);
    IF v_usado AND (upper(btrim(p_codigo)) IS DISTINCT FROM upper(v_cupon.codigo::text)
                    OR p_tipo IS DISTINCT FROM v_cupon.tipo
                    OR p_valor IS DISTINCT FROM v_cupon.valor
                    OR COALESCE(p_monto_minimo, 0) IS DISTINCT FROM v_cupon.monto_minimo
                    OR p_fecha_inicio IS DISTINCT FROM lower(v_cupon.vigencia)
                    OR p_id_hotel IS DISTINCT FROM v_cupon.id_hotel
                    OR p_id_tipo_habitacion IS DISTINCT FROM v_cupon.id_tipo_habitacion) THEN
        PERFORM interno.sp_comun_error('HH409', 'cupon_usado',
            'El cupón ya se usó: solo puede cambiar descripción, fecha final, límites y si está activo');
    END IF;
    v_id_hotel := CASE WHEN v_usado THEN v_cupon.id_hotel
                       ELSE interno.sp_cupones_validar_alcance(v_actor, p_id_hotel, p_id_tipo_habitacion) END;

    UPDATE cupon c
       SET codigo = upper(btrim(p_codigo)), descripcion = NULLIF(btrim(p_descripcion), ''), tipo = p_tipo,
           valor = p_valor, vigencia = daterange(p_fecha_inicio, p_fecha_fin + 1, '[)'),
           monto_minimo = COALESCE(p_monto_minimo, 0), limite_usos_total = p_limite_usos_total,
           limite_usos_cliente = p_limite_usos_cliente, id_hotel = v_id_hotel,
           id_tipo_habitacion = p_id_tipo_habitacion, activo = COALESCE(p_activo, c.activo)
     WHERE c.id_cupon = p_id_cupon;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_cupon.id_hotel, 'cupones', 'cupon',
        p_id_cupon::text, CASE WHEN p_activo IS FALSE AND v_cupon.activo THEN 'desactivar' ELSE 'modificar' END,
        to_jsonb(v_cupon), (SELECT to_jsonb(c) FROM cupon c WHERE c.id_cupon = p_id_cupon));
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'cupon_duplicado', 'Ya existe un cupón con ese código');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, CASE v_restriccion
            WHEN 'ck_cupon_usos' THEN 'El límite total no puede ser menor que los usos que ya tiene'
            WHEN 'ck_cupon_codigo' THEN 'El código debe tener de 3 a 30 letras, números, guion o guion bajo'
            WHEN 'ck_cupon_porcentaje' THEN 'Un porcentaje no puede ser mayor que 100'
            ELSE 'Los valores del cupón no son válidos' END);
END;
$$;

CREATE OR REPLACE FUNCTION sp_cupones_listar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_busqueda          TEXT,
    p_estado            TEXT,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_cupon             BIGINT,
    codigo               CITEXT,
    descripcion          VARCHAR,
    tipo                 VARCHAR,
    valor                DECIMAL(10,2),
    fecha_inicio         DATE,
    fecha_fin            DATE,
    monto_minimo         DECIMAL(10,2),
    usos_actuales        INTEGER,
    limite_usos_total    INTEGER,
    limite_usos_cliente  INTEGER,
    hotel                VARCHAR,
    tipo_habitacion      VARCHAR,
    descuento_otorgado   DECIMAL(12,2),
    estado               TEXT,
    total_registros      BIGINT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CUPONES_GESTIONAR', 'REPORTES_VER');
    IF p_id_hotel IS NOT NULL THEN
        PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    END IF;
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    IF p_estado IS NOT NULL AND p_estado NOT IN ('vigente', 'programado', 'vencido', 'agotado', 'inactivo') THEN
        PERFORM interno.sp_comun_error('HH422', 'estado_invalido',
            'Estado no válido: vigente, programado, vencido, agotado o inactivo');
    END IF;
    v_hoy := interno.sp_comun_hoy();

    RETURN QUERY
    WITH x AS (
        SELECT c.*,
               CASE WHEN NOT c.activo THEN 'inactivo'
                    WHEN v_hoy < lower(c.vigencia) THEN 'programado'
                    WHEN NOT (c.vigencia @> v_hoy) THEN 'vencido'
                    WHEN c.limite_usos_total IS NOT NULL AND c.usos_actuales >= c.limite_usos_total THEN 'agotado'
                    ELSE 'vigente' END AS estado_calc
          FROM cupon c
         WHERE (p_id_hotel IS NULL OR c.id_hotel IS NULL OR c.id_hotel = p_id_hotel)
           AND (v_actor.rol = 'administrador' OR c.id_hotel IS NULL OR EXISTS (
                    SELECT 1 FROM empleado_hotel eh
                     WHERE eh.id_empleado = v_actor.id_empleado AND eh.id_hotel = c.id_hotel AND eh.activo))
           AND (v_busqueda IS NULL OR c.codigo ILIKE '%' || v_busqueda || '%'
                OR c.descripcion ILIKE '%' || v_busqueda || '%')
    )
    SELECT x.id_cupon, x.codigo, x.descripcion, x.tipo, x.valor, lower(x.vigencia), upper(x.vigencia) - 1,
           x.monto_minimo, x.usos_actuales, x.limite_usos_total, x.limite_usos_cliente,
           COALESCE(h.nombre, 'Todos los hoteles'), th.nombre,
           (SELECT COALESCE(sum(cu.monto_descuento), 0)::numeric(12,2) FROM cupon_uso cu
             WHERE cu.id_cupon = x.id_cupon AND cu.estado = 'aplicado'),
           x.estado_calc, count(*) OVER ()
      FROM x
      LEFT JOIN hotel h ON h.id_hotel = x.id_hotel
      LEFT JOIN tipo_habitacion th ON th.id_tipo_habitacion = x.id_tipo_habitacion
     WHERE p_estado IS NULL OR x.estado_calc = p_estado
     ORDER BY lower(x.vigencia) DESC, x.id_cupon DESC
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_cupones_obtener(p_id_usuario_actor BIGINT, p_id_cupon BIGINT)
RETURNS TABLE (
    id_cupon             BIGINT,
    codigo               CITEXT,
    descripcion          VARCHAR,
    tipo                 VARCHAR,
    valor                DECIMAL(10,2),
    fecha_inicio         DATE,
    fecha_fin            DATE,
    monto_minimo         DECIMAL(10,2),
    usos_actuales        INTEGER,
    limite_usos_total    INTEGER,
    limite_usos_cliente  INTEGER,
    id_hotel             BIGINT,
    id_tipo_habitacion   BIGINT,
    activo               BOOLEAN,
    usos                 JSONB)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_id_hotel  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CUPONES_GESTIONAR', 'REPORTES_VER');
    SELECT c.id_hotel INTO v_id_hotel FROM cupon c WHERE c.id_cupon = p_id_cupon;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'cupon_no_encontrado', 'Cupón no encontrado');
    END IF;
    IF v_id_hotel IS NOT NULL THEN
        PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);
    END IF;

    RETURN QUERY
    SELECT c.id_cupon, c.codigo, c.descripcion, c.tipo, c.valor, lower(c.vigencia), upper(c.vigencia) - 1,
           c.monto_minimo, c.usos_actuales, c.limite_usos_total, c.limite_usos_cliente, c.id_hotel,
           c.id_tipo_habitacion, c.activo,
           (SELECT COALESCE(jsonb_agg(u ORDER BY u.fecha DESC), '[]'::jsonb)
              FROM (SELECT cu.creado_en AS fecha, r.codigo AS reservacion, cl.nombres || ' ' || cl.apellidos AS cliente,
                           cu.monto_descuento AS descuento, cu.estado
                      FROM cupon_uso cu
                      JOIN reservacion r ON r.id_reservacion = cu.id_reservacion
                      JOIN cliente cl ON cl.id_cliente = cu.id_cliente
                     WHERE cu.id_cupon = c.id_cupon
                     ORDER BY cu.creado_en DESC
                     LIMIT 50) u)
      FROM cupon c
     WHERE c.id_cupon = p_id_cupon;
END;
$$;

CREATE OR REPLACE FUNCTION sp_cupones_vista_previa(
    p_id_usuario_actor  BIGINT,
    p_codigo            TEXT,
    p_id_hotel          BIGINT,
    p_fecha_entrada     DATE,
    p_fecha_salida      DATE,
    p_habitaciones      JSONB,
    p_id_cliente        BIGINT DEFAULT NULL)
RETURNS TABLE (codigo TEXT, descripcion VARCHAR, subtotal DECIMAL(10,2), descuento DECIMAL(10,2), total DECIMAL(10,2))
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor       interno.tp_actor;
    v_id_cliente  BIGINT;
    v_cupon       cupon%ROWTYPE;
    v_tipos       BIGINT[] := '{}';
    v_subtotales  NUMERIC[] := '{}';
    v_item        JSONB;
    v_id_tipo     BIGINT;
    v_sub         NUMERIC;
    v_descuento   NUMERIC;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    IF interno.sp_comun_tiene_permiso(v_actor, 'RESERVACIONES_GESTIONAR') THEN
        PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
        v_id_cliente := p_id_cliente;
    ELSE
        PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVAR');
        v_id_cliente := v_actor.id_cliente;
    END IF;
    PERFORM interno.sp_comun_exigir_texto(p_codigo, 'código del cupón');
    PERFORM interno.sp_reservaciones_validar_fechas(p_fecha_entrada, p_fecha_salida);
    IF p_habitaciones IS NULL OR jsonb_typeof(p_habitaciones) <> 'array' OR jsonb_array_length(p_habitaciones) = 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'habitaciones_requeridas', 'Seleccione al menos una habitación');
    END IF;

    FOR v_item IN SELECT x FROM jsonb_array_elements(p_habitaciones) AS t(x) LOOP
        BEGIN
            v_id_tipo := (v_item ->> 'id_tipo_habitacion')::bigint;
        EXCEPTION WHEN invalid_text_representation THEN
            PERFORM interno.sp_comun_error('HH422', 'habitacion_formato', 'Cada habitación debe indicar su tipo');
        END;
        IF NOT EXISTS (SELECT 1 FROM tipo_habitacion th
                        WHERE th.id_tipo_habitacion = v_id_tipo AND th.id_hotel = p_id_hotel AND th.activo) THEN
            PERFORM interno.sp_comun_error('HH422', 'tipo_invalido', 'El tipo de habitación no existe en este hotel');
        END IF;
        SELECT sum(n.precio_noche) INTO v_sub
          FROM interno.sp_reservaciones_calcular_noches(v_id_tipo, p_fecha_entrada, p_fecha_salida) n;
        v_tipos := v_tipos || v_id_tipo;
        v_subtotales := v_subtotales || v_sub;
    END LOOP;

    SELECT c.* INTO v_cupon FROM cupon c WHERE c.codigo = btrim(p_codigo)::citext;
    v_descuento := interno.sp_cupones_calcular_descuento(v_cupon, v_id_cliente, p_id_hotel, v_tipos, v_subtotales);

    RETURN QUERY
    SELECT v_cupon.codigo::text, v_cupon.descripcion,
           (SELECT sum(s) FROM unnest(v_subtotales) s)::numeric(10,2), v_descuento::numeric(10,2),
           ((SELECT sum(s) FROM unnest(v_subtotales) s) - v_descuento)::numeric(10,2);
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_cupones_crear(BIGINT, TEXT, TEXT, TEXT, DECIMAL, DATE, DATE, DECIMAL, INTEGER, INTEGER, BIGINT, BIGINT),
    sp_cupones_actualizar(BIGINT, BIGINT, TEXT, TEXT, TEXT, DECIMAL, DATE, DATE, DECIMAL, INTEGER, INTEGER, BIGINT, BIGINT, BOOLEAN),
    sp_cupones_listar(BIGINT, BIGINT, TEXT, TEXT, INTEGER, INTEGER),
    sp_cupones_obtener(BIGINT, BIGINT),
    sp_cupones_vista_previa(BIGINT, TEXT, BIGINT, DATE, DATE, JSONB, BIGINT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('030_sp_cupones.sql');