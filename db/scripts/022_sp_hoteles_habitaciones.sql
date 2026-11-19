-- =============================================================================
-- 022_sp_hoteles_habitaciones.sql
-- Hoteles, configuración, tipos de habitación, precio base, tarifas
-- especiales, servicios y habitaciones (RN-02).
-- Los sp_*_publico no piden usuario: los usa la página web sin sesión.
-- =============================================================================

CREATE OR REPLACE FUNCTION sp_hoteles_listar_publico()
RETURNS TABLE (
    id_hotel   BIGINT,
    nombre     VARCHAR,
    slug       VARCHAR,
    direccion  VARCHAR,
    ciudad     VARCHAR,
    telefono   VARCHAR,
    correo     CITEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT h.id_hotel, h.nombre, h.slug, h.direccion, h.ciudad, h.telefono, h.correo
      FROM hotel h
     WHERE h.activo
     ORDER BY h.nombre;
$$;

CREATE OR REPLACE FUNCTION sp_hoteles_crear(
    p_id_usuario_actor  BIGINT,
    p_nombre            TEXT,
    p_slug              TEXT,
    p_direccion         TEXT,
    p_ciudad            TEXT,
    p_telefono          TEXT,
    p_correo            TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       interno.tp_actor;
    v_id_hotel    BIGINT;
    v_restriccion TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HOTELES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');
    PERFORM interno.sp_comun_exigir_texto(p_slug, 'slug');
    PERFORM interno.sp_comun_exigir_texto(p_direccion, 'dirección');
    PERFORM interno.sp_comun_exigir_texto(p_ciudad, 'ciudad');

    INSERT INTO hotel (nombre, slug, direccion, ciudad, telefono, correo)
    VALUES (btrim(p_nombre), lower(btrim(p_slug)), btrim(p_direccion), btrim(p_ciudad),
            NULLIF(btrim(p_telefono), ''), NULLIF(btrim(p_correo), ''))
    RETURNING id_hotel INTO v_id_hotel;

    INSERT INTO hotel_configuracion (id_hotel) VALUES (v_id_hotel);

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'hoteles', 'hotel', v_id_hotel::text,
        'crear', NULL, (SELECT to_jsonb(h) FROM hotel h WHERE h.id_hotel = v_id_hotel));
    RETURN v_id_hotel;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'hotel_duplicado', 'Ya existe un hotel con ese nombre o slug');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'Los datos del hotel no tienen un formato válido');
END;
$$;

CREATE OR REPLACE FUNCTION sp_hoteles_actualizar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_nombre            TEXT,
    p_direccion         TEXT,
    p_ciudad            TEXT,
    p_telefono          TEXT,
    p_correo            TEXT,
    p_activo            BOOLEAN)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HOTELES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');
    PERFORM interno.sp_comun_exigir_texto(p_direccion, 'dirección');
    PERFORM interno.sp_comun_exigir_texto(p_ciudad, 'ciudad');

    SELECT to_jsonb(h) INTO v_anterior FROM hotel h WHERE h.id_hotel = p_id_hotel FOR UPDATE;
    IF v_anterior IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'hotel_no_encontrado', 'Hotel no encontrado');
    END IF;

    UPDATE hotel h
       SET nombre = btrim(p_nombre), direccion = btrim(p_direccion), ciudad = btrim(p_ciudad),
           telefono = NULLIF(btrim(p_telefono), ''), correo = NULLIF(btrim(p_correo), ''),
           activo = COALESCE(p_activo, h.activo)
     WHERE h.id_hotel = p_id_hotel;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'hoteles', 'hotel', p_id_hotel::text,
        CASE WHEN p_activo IS FALSE AND (v_anterior ->> 'activo')::boolean THEN 'desactivar' ELSE 'modificar' END,
        v_anterior, (SELECT to_jsonb(h) FROM hotel h WHERE h.id_hotel = p_id_hotel));
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'hotel_duplicado', 'Ya existe un hotel con ese nombre');
END;
$$;

CREATE OR REPLACE FUNCTION sp_hoteles_obtener_configuracion(p_id_usuario_actor BIGINT, p_id_hotel BIGINT)
RETURNS TABLE (
    id_hotel                         BIGINT,
    hora_checkout                    TIME,
    porcentaje_anticipo              DECIMAL(5,2),
    minutos_bloqueo_pago             INTEGER,
    horas_limite_cancelacion         INTEGER,
    porcentaje_reembolso             DECIMAL(5,2),
    no_presentacion_pierde_anticipo  BOOLEAN)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HOTELES_GESTIONAR', 'RESERVACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);

    RETURN QUERY
    SELECT hc.id_hotel, hc.hora_checkout, hc.porcentaje_anticipo, hc.minutos_bloqueo_pago,
           hc.horas_limite_cancelacion, hc.porcentaje_reembolso, hc.no_presentacion_pierde_anticipo
      FROM hotel_configuracion hc
     WHERE hc.id_hotel = p_id_hotel;
END;
$$;

CREATE OR REPLACE FUNCTION sp_hoteles_actualizar_configuracion(
    p_id_usuario_actor                 BIGINT,
    p_id_hotel                         BIGINT,
    p_hora_checkout                    TIME,
    p_porcentaje_anticipo              DECIMAL(5,2),
    p_minutos_bloqueo_pago             INTEGER,
    p_horas_limite_cancelacion         INTEGER,
    p_porcentaje_reembolso             DECIMAL(5,2),
    p_no_presentacion_pierde_anticipo  BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       interno.tp_actor;
    v_anterior    JSONB;
    v_restriccion TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HOTELES_GESTIONAR');

    SELECT to_jsonb(hc) INTO v_anterior FROM hotel_configuracion hc WHERE hc.id_hotel = p_id_hotel FOR UPDATE;
    IF v_anterior IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'hotel_no_encontrado', 'Hotel no encontrado');
    END IF;

    UPDATE hotel_configuracion hc
       SET hora_checkout = p_hora_checkout,
           porcentaje_anticipo = p_porcentaje_anticipo,
           minutos_bloqueo_pago = p_minutos_bloqueo_pago,
           horas_limite_cancelacion = p_horas_limite_cancelacion,
           porcentaje_reembolso = p_porcentaje_reembolso,
           no_presentacion_pierde_anticipo = p_no_presentacion_pierde_anticipo
     WHERE hc.id_hotel = p_id_hotel;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'hoteles', 'hotel_configuracion',
        p_id_hotel::text, 'modificar', v_anterior,
        (SELECT to_jsonb(hc) FROM hotel_configuracion hc WHERE hc.id_hotel = p_id_hotel));
EXCEPTION
    WHEN not_null_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'campo_requerido',
            'Hora de check-out, porcentaje de anticipo y minutos para pagar son obligatorios');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'Valores de configuración fuera de rango');
END;
$$;

CREATE OR REPLACE FUNCTION sp_servicios_listar_publico()
RETURNS TABLE (id_servicio BIGINT, nombre VARCHAR, icono VARCHAR)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT s.id_servicio, s.nombre, s.icono FROM servicio s WHERE s.activo ORDER BY s.nombre;
$$;

CREATE OR REPLACE FUNCTION sp_servicios_crear(p_id_usuario_actor BIGINT, p_nombre TEXT, p_icono TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_id_servicio  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');

    INSERT INTO servicio (nombre, icono) VALUES (btrim(p_nombre), NULLIF(btrim(p_icono), ''))
    RETURNING id_servicio INTO v_id_servicio;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'habitaciones', 'servicio',
        v_id_servicio::text, 'crear', NULL, jsonb_build_object('nombre', btrim(p_nombre)));
    RETURN v_id_servicio;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'servicio_duplicado', 'Ya existe un servicio con ese nombre');
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_listar_tipos_publico(p_id_hotel BIGINT)
RETURNS TABLE (
    id_tipo_habitacion  BIGINT,
    nombre              VARCHAR,
    descripcion         TEXT,
    capacidad_maxima    INTEGER,
    precio_base         DECIMAL(10,2),
    servicios           JSONB,
    imagenes            JSONB)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT th.id_tipo_habitacion, th.nombre, th.descripcion, th.capacidad_maxima, th.precio_base,
           COALESCE((SELECT jsonb_agg(jsonb_build_object('id_servicio', s.id_servicio, 'nombre', s.nombre,
                                                         'icono', s.icono) ORDER BY s.nombre)
                       FROM tipo_habitacion_servicio ths
                       JOIN servicio s ON s.id_servicio = ths.id_servicio AND s.activo
                      WHERE ths.id_tipo_habitacion = th.id_tipo_habitacion), '[]'::jsonb),
           COALESCE((SELECT jsonb_agg(jsonb_build_object('url', i.url, 'texto_alternativo', i.texto_alternativo)
                                      ORDER BY i.orden)
                       FROM tipo_habitacion_imagen i
                      WHERE i.id_tipo_habitacion = th.id_tipo_habitacion), '[]'::jsonb)
      FROM tipo_habitacion th
      JOIN hotel h ON h.id_hotel = th.id_hotel AND h.activo
     WHERE th.id_hotel = p_id_hotel
       AND th.activo
     ORDER BY th.precio_base, th.nombre;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_crear_tipo(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_nombre            TEXT,
    p_descripcion       TEXT,
    p_capacidad_maxima  INTEGER,
    p_precio_base       DECIMAL(10,2))
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       interno.tp_actor;
    v_id_tipo     BIGINT;
    v_restriccion TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');

    IF NOT EXISTS (SELECT 1 FROM hotel h WHERE h.id_hotel = p_id_hotel) THEN
        PERFORM interno.sp_comun_error('HH404', 'hotel_no_encontrado', 'Hotel no encontrado');
    END IF;

    INSERT INTO tipo_habitacion (id_hotel, nombre, descripcion, capacidad_maxima, precio_base)
    VALUES (p_id_hotel, btrim(p_nombre), NULLIF(btrim(p_descripcion), ''), p_capacidad_maxima, p_precio_base)
    RETURNING id_tipo_habitacion INTO v_id_tipo;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'habitaciones', 'tipo_habitacion',
        v_id_tipo::text, 'crear', NULL,
        (SELECT to_jsonb(th) FROM tipo_habitacion th WHERE th.id_tipo_habitacion = v_id_tipo));
    RETURN v_id_tipo;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'tipo_duplicado', 'Ese hotel ya tiene un tipo de habitación con ese nombre');
    WHEN not_null_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'campo_requerido', 'Capacidad y precio base son obligatorios');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'La capacidad y el precio deben ser mayores que cero');
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_actualizar_tipo(
    p_id_usuario_actor    BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_nombre              TEXT,
    p_descripcion         TEXT,
    p_capacidad_maxima    INTEGER,
    p_activo              BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       interno.tp_actor;
    v_anterior    JSONB;
    v_restriccion TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');

    SELECT to_jsonb(th) INTO v_anterior
      FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion FOR UPDATE;
    IF v_anterior IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'tipo_no_encontrado', 'Tipo de habitación no encontrado');
    END IF;

    IF p_activo IS FALSE AND EXISTS (
        SELECT 1 FROM habitacion h WHERE h.id_tipo_habitacion = p_id_tipo_habitacion AND h.activo) THEN
        PERFORM interno.sp_comun_error('HH409', 'tipo_con_habitaciones',
            'No se puede desactivar: hay habitaciones activas de este tipo');
    END IF;

    UPDATE tipo_habitacion th
       SET nombre = btrim(p_nombre), descripcion = NULLIF(btrim(p_descripcion), ''),
           capacidad_maxima = p_capacidad_maxima, activo = COALESCE(p_activo, th.activo)
     WHERE th.id_tipo_habitacion = p_id_tipo_habitacion;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, (v_anterior ->> 'id_hotel')::bigint,
        'habitaciones', 'tipo_habitacion', p_id_tipo_habitacion::text,
        CASE WHEN p_activo IS FALSE AND (v_anterior ->> 'activo')::boolean THEN 'desactivar' ELSE 'modificar' END,
        v_anterior, (SELECT to_jsonb(th) FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion));
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'tipo_duplicado', 'Ese hotel ya tiene un tipo de habitación con ese nombre');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'La capacidad debe ser mayor que cero');
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_cambiar_precio_base(
    p_id_usuario_actor    BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_precio_base         DECIMAL(10,2))
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_anterior  DECIMAL(10,2);
    v_id_hotel  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'PRECIOS_GESTIONAR');

    IF p_precio_base IS NULL OR p_precio_base <= 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'precio_invalido', 'El precio debe ser mayor que cero');
    END IF;

    SELECT th.precio_base, th.id_hotel INTO v_anterior, v_id_hotel
      FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'tipo_no_encontrado', 'Tipo de habitación no encontrado');
    END IF;
    IF v_anterior = p_precio_base THEN
        RETURN;
    END IF;

    UPDATE tipo_habitacion th SET precio_base = p_precio_base
     WHERE th.id_tipo_habitacion = p_id_tipo_habitacion;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'precios', 'tipo_habitacion',
        p_id_tipo_habitacion::text, 'modificar',
        jsonb_build_object('precio_base', v_anterior), jsonb_build_object('precio_base', p_precio_base));
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_asignar_servicios(
    p_id_usuario_actor    BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_ids_servicio        BIGINT[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_id_hotel  BIGINT;
    v_anterior  BIGINT[];
    v_nuevos    BIGINT[];
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_GESTIONAR');

    SELECT th.id_hotel INTO v_id_hotel
      FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'tipo_no_encontrado', 'Tipo de habitación no encontrado');
    END IF;

    v_nuevos := ARRAY(SELECT DISTINCT unnest(COALESCE(p_ids_servicio, '{}')) ORDER BY 1);
    IF EXISTS (SELECT 1 FROM unnest(v_nuevos) AS x(id)
                WHERE NOT EXISTS (SELECT 1 FROM servicio s WHERE s.id_servicio = x.id AND s.activo)) THEN
        PERFORM interno.sp_comun_error('HH422', 'servicio_invalido', 'Uno de los servicios no existe o está inactivo');
    END IF;

    v_anterior := ARRAY(SELECT ths.id_servicio FROM tipo_habitacion_servicio ths
                         WHERE ths.id_tipo_habitacion = p_id_tipo_habitacion ORDER BY 1);

    DELETE FROM tipo_habitacion_servicio ths
     WHERE ths.id_tipo_habitacion = p_id_tipo_habitacion AND NOT (ths.id_servicio = ANY (v_nuevos));
    INSERT INTO tipo_habitacion_servicio (id_tipo_habitacion, id_servicio)
    SELECT p_id_tipo_habitacion, x.id FROM unnest(v_nuevos) AS x(id)
    ON CONFLICT DO NOTHING;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'habitaciones', 'tipo_habitacion_servicio',
        p_id_tipo_habitacion::text, 'modificar',
        jsonb_build_object('servicios', v_anterior), jsonb_build_object('servicios', v_nuevos));
END;
$$;


CREATE OR REPLACE FUNCTION sp_habitaciones_crear_tarifa_especial(
    p_id_usuario_actor    BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_nombre              TEXT,
    p_fecha_inicio        DATE,
    p_fecha_fin           DATE,
    p_precio_noche        DECIMAL(10,2))
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       interno.tp_actor;
    v_id_hotel    BIGINT;
    v_id_tarifa   BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'PRECIOS_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');

    IF p_fecha_inicio IS NULL OR p_fecha_fin IS NULL OR p_fecha_fin < p_fecha_inicio THEN
        PERFORM interno.sp_comun_error('HH422', 'fechas_invalidas', 'La fecha final no puede ser anterior a la inicial');
    END IF;
    IF p_precio_noche IS NULL OR p_precio_noche <= 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'precio_invalido', 'El precio debe ser mayor que cero');
    END IF;

    SELECT th.id_hotel INTO v_id_hotel FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'tipo_no_encontrado', 'Tipo de habitación no encontrado');
    END IF;

    INSERT INTO tarifa_especial (id_tipo_habitacion, nombre, periodo, precio_noche, creado_por)
    VALUES (p_id_tipo_habitacion, btrim(p_nombre), daterange(p_fecha_inicio, p_fecha_fin + 1, '[)'),
            p_precio_noche, p_id_usuario_actor)
    RETURNING id_tarifa_especial INTO v_id_tarifa;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'precios', 'tarifa_especial',
        v_id_tarifa::text, 'crear', NULL,
        (SELECT to_jsonb(te) FROM tarifa_especial te WHERE te.id_tarifa_especial = v_id_tarifa));
    RETURN v_id_tarifa;
EXCEPTION
    WHEN exclusion_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'tarifa_traslapada',
            'Ya existe una tarifa especial activa para este tipo de habitación en esas fechas');
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_desactivar_tarifa_especial(
    p_id_usuario_actor    BIGINT,
    p_id_tarifa_especial  BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_anterior  JSONB;
    v_id_hotel  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'PRECIOS_GESTIONAR');

    SELECT to_jsonb(te), th.id_hotel INTO v_anterior, v_id_hotel
      FROM tarifa_especial te
      JOIN tipo_habitacion th ON th.id_tipo_habitacion = te.id_tipo_habitacion
     WHERE te.id_tarifa_especial = p_id_tarifa_especial
       FOR UPDATE OF te;
    IF v_anterior IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'tarifa_no_encontrada', 'Tarifa especial no encontrada');
    END IF;
    IF NOT (v_anterior ->> 'activo')::boolean THEN
        RETURN;
    END IF;

    UPDATE tarifa_especial te SET activo = FALSE WHERE te.id_tarifa_especial = p_id_tarifa_especial;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'precios', 'tarifa_especial',
        p_id_tarifa_especial::text, 'desactivar', v_anterior, jsonb_build_object('activo', false));
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_listar_tarifas_especiales(
    p_id_usuario_actor    BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_incluir_inactivas   BOOLEAN)
RETURNS TABLE (
    id_tarifa_especial  BIGINT,
    nombre              VARCHAR,
    fecha_inicio        DATE,
    fecha_fin           DATE,
    precio_noche        DECIMAL(10,2),
    activo              BOOLEAN)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'PRECIOS_GESTIONAR', 'RESERVACIONES_GESTIONAR');

    SELECT th.id_hotel INTO v_id_hotel FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'tipo_no_encontrado', 'Tipo de habitación no encontrado');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);

    RETURN QUERY
    SELECT te.id_tarifa_especial, te.nombre, lower(te.periodo), upper(te.periodo) - 1, te.precio_noche, te.activo
      FROM tarifa_especial te
     WHERE te.id_tipo_habitacion = p_id_tipo_habitacion
       AND (te.activo OR COALESCE(p_incluir_inactivas, FALSE))
     ORDER BY lower(te.periodo);
END;
$$;


CREATE OR REPLACE FUNCTION sp_habitaciones_crear(
    p_id_usuario_actor    BIGINT,
    p_id_hotel            BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_numero              TEXT,
    p_piso                INTEGER)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor          interno.tp_actor;
    v_id_habitacion  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_numero, 'número');

    INSERT INTO habitacion (id_hotel, id_tipo_habitacion, numero, piso)
    VALUES (p_id_hotel, p_id_tipo_habitacion, btrim(p_numero), p_piso)
    RETURNING id_habitacion INTO v_id_habitacion;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'habitaciones', 'habitacion',
        v_id_habitacion::text, 'crear', NULL,
        (SELECT to_jsonb(h) FROM habitacion h WHERE h.id_habitacion = v_id_habitacion));
    RETURN v_id_habitacion;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'habitacion_duplicada', 'Ese hotel ya tiene una habitación con ese número');
    WHEN foreign_key_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'tipo_de_otro_hotel', 'El tipo de habitación no existe en ese hotel');
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_actualizar(
    p_id_usuario_actor    BIGINT,
    p_id_habitacion       BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_numero              TEXT,
    p_piso                INTEGER)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_numero, 'número');

    SELECT to_jsonb(h) INTO v_anterior FROM habitacion h WHERE h.id_habitacion = p_id_habitacion FOR UPDATE;
    IF v_anterior IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'habitacion_no_encontrada', 'Habitación no encontrada');
    END IF;

    UPDATE habitacion h
       SET id_tipo_habitacion = p_id_tipo_habitacion, numero = btrim(p_numero), piso = p_piso
     WHERE h.id_habitacion = p_id_habitacion;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, (v_anterior ->> 'id_hotel')::bigint,
        'habitaciones', 'habitacion', p_id_habitacion::text, 'modificar', v_anterior,
        (SELECT to_jsonb(h) FROM habitacion h WHERE h.id_habitacion = p_id_habitacion));
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'habitacion_duplicada', 'Ese hotel ya tiene una habitación con ese número');
    WHEN foreign_key_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'tipo_de_otro_hotel', 'El tipo de habitación no existe en ese hotel');
END;
$$;
CREATE OR REPLACE FUNCTION sp_habitaciones_cambiar_estado(
    p_id_usuario_actor  BIGINT,
    p_id_habitacion     BIGINT,
    p_estado            TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_anterior  VARCHAR;
    v_id_hotel  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_ESTADO');

    IF p_estado IS NULL OR p_estado NOT IN
        ('disponible', 'ocupada', 'en_limpieza', 'en_mantenimiento', 'fuera_de_servicio') THEN
        PERFORM interno.sp_comun_error('HH422', 'estado_invalido', 'Estado de habitación no válido');
    END IF;

    SELECT h.estado, h.id_hotel INTO v_anterior, v_id_hotel
      FROM habitacion h WHERE h.id_habitacion = p_id_habitacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'habitacion_no_encontrada', 'Habitación no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);

    IF v_anterior = p_estado THEN
        RETURN;
    END IF;

    UPDATE habitacion h SET estado = p_estado WHERE h.id_habitacion = p_id_habitacion;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'habitaciones', 'habitacion',
        p_id_habitacion::text, 'modificar',
        jsonb_build_object('estado', v_anterior), jsonb_build_object('estado', p_estado));
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_cambiar_activo(
    p_id_usuario_actor  BIGINT,
    p_id_habitacion     BIGINT,
    p_activo            BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_anterior  BOOLEAN;
    v_id_hotel  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_GESTIONAR');

    SELECT h.activo, h.id_hotel INTO v_anterior, v_id_hotel
      FROM habitacion h WHERE h.id_habitacion = p_id_habitacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'habitacion_no_encontrada', 'Habitación no encontrada');
    END IF;
    IF v_anterior = p_activo THEN
        RETURN;
    END IF;

    IF NOT p_activo AND EXISTS (
        SELECT 1 FROM reservacion_habitacion rh
         WHERE rh.id_habitacion = p_id_habitacion AND rh.activa
           AND upper(rh.periodo) > interno.sp_comun_hoy()) THEN
        PERFORM interno.sp_comun_error('HH409', 'habitacion_con_reservaciones',
            'No se puede desactivar: tiene reservaciones activas. Reasígnelas primero');
    END IF;

    UPDATE habitacion h SET activo = p_activo WHERE h.id_habitacion = p_id_habitacion;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'habitaciones', 'habitacion',
        p_id_habitacion::text, CASE WHEN p_activo THEN 'modificar' ELSE 'desactivar' END,
        jsonb_build_object('activo', v_anterior), jsonb_build_object('activo', p_activo));
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_listar(
    p_id_usuario_actor    BIGINT,
    p_id_hotel            BIGINT,
    p_estado              TEXT,
    p_id_tipo_habitacion  BIGINT,
    p_busqueda            TEXT,
    p_incluir_inactivas   BOOLEAN,
    p_pagina              INTEGER,
    p_tamano              INTEGER,
    p_orden               TEXT,
    p_direccion           TEXT)
RETURNS TABLE (
    id_habitacion       BIGINT,
    numero              VARCHAR,
    piso                INTEGER,
    estado              VARCHAR,
    activo              BOOLEAN,
    id_tipo_habitacion  BIGINT,
    tipo                VARCHAR,
    total_registros     BIGINT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'HABITACIONES_VER');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    PERFORM interno.sp_comun_validar_direccion(p_direccion);
    IF p_orden IS NULL OR p_orden NOT IN ('numero', 'piso', 'estado', 'tipo') THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_invalido', 'Orden no válido: use numero, piso, estado o tipo');
    END IF;

    RETURN QUERY
    SELECT h.id_habitacion, h.numero, h.piso, h.estado, h.activo, th.id_tipo_habitacion, th.nombre,
           count(*) OVER ()
      FROM habitacion h
      JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
     WHERE h.id_hotel = p_id_hotel
       AND (h.activo OR COALESCE(p_incluir_inactivas, FALSE))
       AND (p_estado IS NULL OR h.estado = p_estado)
       AND (p_id_tipo_habitacion IS NULL OR h.id_tipo_habitacion = p_id_tipo_habitacion)
       AND (p_busqueda IS NULL OR h.numero ILIKE '%' || p_busqueda || '%')
     ORDER BY
        CASE WHEN p_orden = 'numero' AND p_direccion = 'asc'  THEN h.numero END ASC,
        CASE WHEN p_orden = 'numero' AND p_direccion = 'desc' THEN h.numero END DESC,
        CASE WHEN p_orden = 'piso'   AND p_direccion = 'asc'  THEN h.piso END ASC,
        CASE WHEN p_orden = 'piso'   AND p_direccion = 'desc' THEN h.piso END DESC,
        CASE WHEN p_orden = 'estado' AND p_direccion = 'asc'  THEN h.estado END ASC,
        CASE WHEN p_orden = 'estado' AND p_direccion = 'desc' THEN h.estado END DESC,
        CASE WHEN p_orden = 'tipo'   AND p_direccion = 'asc'  THEN th.nombre END ASC,
        CASE WHEN p_orden = 'tipo'   AND p_direccion = 'desc' THEN th.nombre END DESC,
        h.id_habitacion
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_hoteles_listar_publico(),
    sp_hoteles_crear(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT),
    sp_hoteles_actualizar(BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN),
    sp_hoteles_obtener_configuracion(BIGINT, BIGINT),
    sp_hoteles_actualizar_configuracion(BIGINT, BIGINT, TIME, DECIMAL, INTEGER, INTEGER, DECIMAL, BOOLEAN),
    sp_servicios_listar_publico(),
    sp_servicios_crear(BIGINT, TEXT, TEXT),
    sp_habitaciones_listar_tipos_publico(BIGINT),
    sp_habitaciones_crear_tipo(BIGINT, BIGINT, TEXT, TEXT, INTEGER, DECIMAL),
    sp_habitaciones_actualizar_tipo(BIGINT, BIGINT, TEXT, TEXT, INTEGER, BOOLEAN),
    sp_habitaciones_cambiar_precio_base(BIGINT, BIGINT, DECIMAL),
    sp_habitaciones_asignar_servicios(BIGINT, BIGINT, BIGINT[]),
    sp_habitaciones_crear_tarifa_especial(BIGINT, BIGINT, TEXT, DATE, DATE, DECIMAL),
    sp_habitaciones_desactivar_tarifa_especial(BIGINT, BIGINT),
    sp_habitaciones_listar_tarifas_especiales(BIGINT, BIGINT, BOOLEAN),
    sp_habitaciones_crear(BIGINT, BIGINT, BIGINT, TEXT, INTEGER),
    sp_habitaciones_actualizar(BIGINT, BIGINT, BIGINT, TEXT, INTEGER),
    sp_habitaciones_cambiar_estado(BIGINT, BIGINT, TEXT),
    sp_habitaciones_cambiar_activo(BIGINT, BIGINT, BOOLEAN),
    sp_habitaciones_listar(BIGINT, BIGINT, TEXT, BIGINT, TEXT, BOOLEAN, INTEGER, INTEGER, TEXT, TEXT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('022_sp_hoteles_habitaciones.sql');