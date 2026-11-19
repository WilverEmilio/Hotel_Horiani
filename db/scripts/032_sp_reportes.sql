-- =============================================================================
-- 032_sp_reportes.sql
-- Dashboard y reportes (RN-10).
--
-- Criterios:
--   * Ingresos = dinero cobrado: pagos aprobados por fecha de cobro, menos
--     reembolsos de esos pagos. Un pago anulado (cobrado tarde sobre una
--     reservación vencida) no cuenta, y su reembolso tampoco resta.
--   * Reservaciones contadas = confirmadas, en curso o finalizadas (RN-10.7),
--     por fecha en que se hicieron. Canceladas, expiradas y no presentadas
--     no cuentan como venta.
--   * Ocupación = noches vendidas / noches disponibles. Disponibles =
--     habitaciones activas x días, menos las noches bloqueadas por mantenimiento.
--   * p_id_hotel NULL = consolidado de los 4 hoteles (solo administrador).
--   * Fechas en hora de Guatemala; p_fecha_hasta incluida.
-- =============================================================================

CREATE OR REPLACE FUNCTION interno.sp_reportes_validar(
    p_actor        interno.tp_actor,
    p_id_hotel     BIGINT,
    p_fecha_desde  DATE,
    p_fecha_hasta  DATE)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    PERFORM interno.sp_comun_exigir_permiso(p_actor, 'REPORTES_VER');
    IF p_id_hotel IS NULL THEN
        IF p_actor.rol <> 'administrador' THEN
            PERFORM interno.sp_comun_error('HH403', 'consolidado_solo_admin',
                'El consolidado de todos los hoteles es solo para el administrador; seleccione un hotel');
        END IF;
    ELSE
        PERFORM interno.sp_comun_exigir_hotel(p_actor, p_id_hotel);
    END IF;
    IF p_fecha_desde IS NULL OR p_fecha_hasta IS NULL OR p_fecha_hasta < p_fecha_desde THEN
        PERFORM interno.sp_comun_error('HH422', 'periodo_invalido', 'Indique un periodo válido');
    END IF;
    IF p_fecha_hasta - p_fecha_desde > 731 THEN
        PERFORM interno.sp_comun_error('HH422', 'periodo_muy_largo', 'El periodo no puede pasar de 2 años');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_resumen_dashboard(p_id_usuario_actor BIGINT, p_id_hotel BIGINT)
RETURNS TABLE (
    fecha                       DATE,
    llegadas_hoy                INTEGER,
    llegadas_pendientes         INTEGER,
    salidas_hoy                 INTEGER,
    huespedes_en_casa           INTEGER,
    habitaciones_activas        INTEGER,
    habitaciones_ocupadas_hoy   INTEGER,
    ocupacion_hoy               DECIMAL(5,2),
    habitaciones_en_limpieza    INTEGER,
    habitaciones_mantenimiento  INTEGER,
    pendientes_de_pago          INTEGER,
    ingresos_hoy                DECIMAL(12,2),
    ingresos_mes                DECIMAL(12,2),
    tareas_limpieza_abiertas    INTEGER,
    reportes_abiertos           INTEGER,
    alertas_inventario          INTEGER)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'REPORTES_VER', 'RESERVACIONES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    v_hoy := interno.sp_comun_hoy();

    RETURN QUERY
    WITH hab AS (
        SELECT count(*) FILTER (WHERE h.activo)::int AS activas,
               count(*) FILTER (WHERE h.activo AND h.estado = 'en_limpieza')::int AS limpieza,
               count(*) FILTER (WHERE h.activo AND h.estado IN ('en_mantenimiento', 'fuera_de_servicio'))::int AS mant
          FROM habitacion h WHERE h.id_hotel = p_id_hotel
    ), ocup AS (
        SELECT count(*)::int AS ocupadas
          FROM reservacion_noche rn
          JOIN reservacion_habitacion rh ON rh.id_reservacion_habitacion = rn.id_reservacion_habitacion
          JOIN reservacion r ON r.id_reservacion = rh.id_reservacion
         WHERE rh.id_hotel = p_id_hotel AND rn.fecha = v_hoy
           AND r.estado IN ('confirmada', 'en_curso', 'finalizada')
    ), res AS (
        SELECT count(*) FILTER (WHERE r.fecha_entrada = v_hoy AND r.estado IN ('confirmada', 'en_curso'))::int AS llegadas,
               count(*) FILTER (WHERE r.fecha_entrada = v_hoy AND r.estado = 'confirmada')::int AS llegadas_pend,
               count(*) FILTER (WHERE r.fecha_salida = v_hoy AND r.estado IN ('en_curso', 'finalizada'))::int AS salidas,
               count(*) FILTER (WHERE r.estado = 'en_curso')::int AS en_casa,
               count(*) FILTER (WHERE r.estado = 'pendiente_pago' AND r.expira_en > now())::int AS pend_pago
          FROM reservacion r
         WHERE r.id_hotel = p_id_hotel
           AND (r.estado IN ('en_curso', 'pendiente_pago') OR r.fecha_entrada = v_hoy OR r.fecha_salida = v_hoy)
    ), ing AS (
        SELECT COALESCE(sum(CASE WHEN p.tipo <> 'reembolso' THEN p.monto WHEN o.estado = 'aprobado' THEN -p.monto ELSE 0 END)
                        FILTER (WHERE (p.confirmado_en AT TIME ZONE 'America/Guatemala')::date = v_hoy), 0)::numeric(12,2) AS hoy,
               COALESCE(sum(CASE WHEN p.tipo <> 'reembolso' THEN p.monto WHEN o.estado = 'aprobado' THEN -p.monto ELSE 0 END), 0)::numeric(12,2) AS mes
          FROM pago p
          JOIN reservacion r ON r.id_reservacion = p.id_reservacion
          LEFT JOIN pago o ON o.id_pago = p.id_pago_origen
         WHERE r.id_hotel = p_id_hotel AND p.estado = 'aprobado'
           AND p.confirmado_en >= (date_trunc('month', v_hoy)::timestamp AT TIME ZONE 'America/Guatemala')
    )
    SELECT v_hoy, res.llegadas, res.llegadas_pend, res.salidas, res.en_casa, hab.activas, ocup.ocupadas,
           CASE WHEN hab.activas = 0 THEN 0 ELSE round(100.0 * ocup.ocupadas / hab.activas, 2) END::numeric(5,2),
           hab.limpieza, hab.mant, res.pend_pago, ing.hoy, ing.mes,
           (SELECT count(*)::int FROM tarea_limpieza t JOIN habitacion h ON h.id_habitacion = t.id_habitacion
             WHERE h.id_hotel = p_id_hotel AND t.estado <> 'completada'),
           (SELECT count(*)::int FROM reporte_mantenimiento m WHERE m.id_hotel = p_id_hotel AND m.estado <> 'resuelto'),
           (SELECT count(*)::int FROM articulo a JOIN existencia e ON e.id_articulo = a.id_articulo AND e.ubicacion = 'bodega'
             WHERE a.id_hotel = p_id_hotel AND a.activo AND e.cantidad < a.existencia_minima)
      FROM hab, ocup, res, ing;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_ingresos(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_agrupacion        TEXT)
RETURNS TABLE (
    periodo          DATE,
    anticipos        DECIMAL(12,2),
    saldos           DECIMAL(12,2),
    reembolsos       DECIMAL(12,2),
    ingresos         DECIMAL(12,2),
    reservaciones    INTEGER,
    valor_reservado  DECIMAL(12,2))
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor  interno.tp_actor;
    v_unidad TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_reportes_validar(v_actor, p_id_hotel, p_fecha_desde, p_fecha_hasta);
    v_unidad := CASE p_agrupacion WHEN 'dia' THEN 'day' WHEN 'semana' THEN 'week' WHEN 'mes' THEN 'month' END;
    IF v_unidad IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'agrupacion_invalida', 'La agrupación debe ser dia, semana o mes');
    END IF;

    RETURN QUERY
    WITH periodos AS (
        SELECT g::date AS periodo
          FROM generate_series(date_trunc(v_unidad, p_fecha_desde::timestamp), p_fecha_hasta::timestamp,
                               ('1 ' || v_unidad)::interval) g
    ), pagos AS (
        SELECT date_trunc(v_unidad, (p.confirmado_en AT TIME ZONE 'America/Guatemala'))::date AS periodo,
               sum(p.monto) FILTER (WHERE p.tipo = 'anticipo') AS anticipos,
               sum(p.monto) FILTER (WHERE p.tipo = 'saldo') AS saldos,
               sum(p.monto) FILTER (WHERE p.tipo = 'reembolso' AND o.estado = 'aprobado') AS reembolsos
          FROM pago p
          JOIN reservacion r ON r.id_reservacion = p.id_reservacion
          LEFT JOIN pago o ON o.id_pago = p.id_pago_origen
         WHERE p.estado = 'aprobado'
           AND (p_id_hotel IS NULL OR r.id_hotel = p_id_hotel)
           AND p.confirmado_en >= (p_fecha_desde::timestamp AT TIME ZONE 'America/Guatemala')
           AND p.confirmado_en <  ((p_fecha_hasta + 1)::timestamp AT TIME ZONE 'America/Guatemala')
         GROUP BY 1
    ), ventas AS (
        SELECT date_trunc(v_unidad, (r.creado_en AT TIME ZONE 'America/Guatemala'))::date AS periodo,
               count(*) AS reservaciones, sum(r.total) AS valor
          FROM reservacion r
         WHERE r.estado IN ('confirmada', 'en_curso', 'finalizada')
           AND (p_id_hotel IS NULL OR r.id_hotel = p_id_hotel)
           AND r.creado_en >= (p_fecha_desde::timestamp AT TIME ZONE 'America/Guatemala')
           AND r.creado_en <  ((p_fecha_hasta + 1)::timestamp AT TIME ZONE 'America/Guatemala')
         GROUP BY 1
    )
    SELECT pe.periodo,
           COALESCE(pa.anticipos, 0)::numeric(12,2),
           COALESCE(pa.saldos, 0)::numeric(12,2),
           COALESCE(pa.reembolsos, 0)::numeric(12,2),
           (COALESCE(pa.anticipos, 0) + COALESCE(pa.saldos, 0) - COALESCE(pa.reembolsos, 0))::numeric(12,2),
           COALESCE(v.reservaciones, 0)::int,
           COALESCE(v.valor, 0)::numeric(12,2)
      FROM periodos pe
      LEFT JOIN pagos pa ON pa.periodo = pe.periodo
      LEFT JOIN ventas v ON v.periodo = pe.periodo
     ORDER BY pe.periodo;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_ocupacion(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE)
RETURNS TABLE (
    hotel                VARCHAR,
    tipo_habitacion      VARCHAR,
    habitaciones         INTEGER,
    noches_disponibles   INTEGER,
    noches_vendidas      INTEGER,
    ocupacion            DECIMAL(5,2),
    ingreso_por_noches   DECIMAL(12,2),
    tarifa_promedio      DECIMAL(10,2))
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
    PERFORM interno.sp_reportes_validar(v_actor, p_id_hotel, p_fecha_desde, p_fecha_hasta);

    RETURN QUERY
    WITH dias AS (
        SELECT g::date AS dia FROM generate_series(p_fecha_desde::timestamp, p_fecha_hasta::timestamp, interval '1 day') g
    ), hab AS (
        SELECT h.id_habitacion, h.id_tipo_habitacion, h.id_hotel
          FROM habitacion h WHERE h.activo AND (p_id_hotel IS NULL OR h.id_hotel = p_id_hotel)
    ), disp AS (
        SELECT hab.id_tipo_habitacion, count(DISTINCT hab.id_habitacion)::int AS habitaciones, count(*)::int AS noches
          FROM hab CROSS JOIN dias
         WHERE NOT EXISTS (SELECT 1 FROM bloqueo_habitacion b
                            WHERE b.id_habitacion = hab.id_habitacion AND b.activo AND b.periodo @> dias.dia)
         GROUP BY hab.id_tipo_habitacion
    ), vend AS (
        SELECT rh.id_tipo_habitacion, count(*)::int AS noches, sum(rn.precio_noche) AS ingreso
          FROM reservacion_noche rn
          JOIN reservacion_habitacion rh ON rh.id_reservacion_habitacion = rn.id_reservacion_habitacion
          JOIN reservacion r ON r.id_reservacion = rh.id_reservacion
         WHERE rn.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
           AND r.estado IN ('confirmada', 'en_curso', 'finalizada')
           AND (p_id_hotel IS NULL OR rh.id_hotel = p_id_hotel)
         GROUP BY rh.id_tipo_habitacion
    ), filas AS (
        SELECT ho.nombre AS hotel, th.nombre AS tipo, COALESCE(d.habitaciones, 0) AS habitaciones,
               COALESCE(d.noches, 0) AS disponibles, COALESCE(v.noches, 0) AS vendidas,
               COALESCE(v.ingreso, 0) AS ingreso, 0 AS orden
          FROM tipo_habitacion th
          JOIN hotel ho ON ho.id_hotel = th.id_hotel
          LEFT JOIN disp d ON d.id_tipo_habitacion = th.id_tipo_habitacion
          LEFT JOIN vend v ON v.id_tipo_habitacion = th.id_tipo_habitacion
         WHERE (p_id_hotel IS NULL OR th.id_hotel = p_id_hotel)
           AND (th.activo OR v.noches IS NOT NULL)
    ), todo AS (
        SELECT * FROM filas
        UNION ALL
        SELECT CASE WHEN p_id_hotel IS NULL THEN 'Todos' ELSE max(f.hotel) END, 'TOTAL', sum(f.habitaciones)::int,
               sum(f.disponibles)::int, sum(f.vendidas)::int, sum(f.ingreso), 1
          FROM filas f
    )
    SELECT t.hotel, t.tipo, t.habitaciones, t.disponibles, t.vendidas,
           CASE WHEN t.disponibles = 0 THEN 0 ELSE round(100.0 * t.vendidas / t.disponibles, 2) END::numeric(5,2),
           t.ingreso::numeric(12,2),
           CASE WHEN t.vendidas = 0 THEN 0 ELSE round(t.ingreso / t.vendidas, 2) END::numeric(10,2)
      FROM todo t
     ORDER BY t.orden, t.hotel, t.tipo;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_ocupacion_diaria(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE)
RETURNS TABLE (fecha DATE, disponibles INTEGER, vendidas INTEGER, ocupacion DECIMAL(5,2))
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
    PERFORM interno.sp_reportes_validar(v_actor, p_id_hotel, p_fecha_desde, p_fecha_hasta);
    IF p_fecha_hasta - p_fecha_desde > 366 THEN
        PERFORM interno.sp_comun_error('HH422', 'periodo_muy_largo', 'La ocupación diaria es de máximo un año');
    END IF;

    RETURN QUERY
    WITH dias AS (
        SELECT g::date AS dia FROM generate_series(p_fecha_desde::timestamp, p_fecha_hasta::timestamp, interval '1 day') g
    ), disp AS (
        SELECT dias.dia, count(*)::int AS n
          FROM dias
          JOIN habitacion h ON h.activo AND (p_id_hotel IS NULL OR h.id_hotel = p_id_hotel)
         WHERE NOT EXISTS (SELECT 1 FROM bloqueo_habitacion b
                            WHERE b.id_habitacion = h.id_habitacion AND b.activo AND b.periodo @> dias.dia)
         GROUP BY dias.dia
    ), vend AS (
        SELECT rn.fecha, count(*)::int AS n
          FROM reservacion_noche rn
          JOIN reservacion_habitacion rh ON rh.id_reservacion_habitacion = rn.id_reservacion_habitacion
          JOIN reservacion r ON r.id_reservacion = rh.id_reservacion
         WHERE rn.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
           AND r.estado IN ('confirmada', 'en_curso', 'finalizada')
           AND (p_id_hotel IS NULL OR rh.id_hotel = p_id_hotel)
         GROUP BY rn.fecha
    )
    SELECT d.dia, COALESCE(di.n, 0), COALESCE(v.n, 0),
           CASE WHEN COALESCE(di.n, 0) = 0 THEN 0 ELSE round(100.0 * COALESCE(v.n, 0) / di.n, 2) END::numeric(5,2)
      FROM dias d
      LEFT JOIN disp di ON di.dia = d.dia
      LEFT JOIN vend v ON v.fecha = d.dia
     ORDER BY d.dia;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_clientes_frecuentes(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_limite            INTEGER)
RETURNS TABLE (
    posicion        INTEGER,
    id_cliente      BIGINT,
    cliente         TEXT,
    correo          CITEXT,
    telefono        VARCHAR,
    estancias       INTEGER,
    noches          INTEGER,
    total_gastado   DECIMAL(12,2),
    ultima_llegada  DATE)
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
    PERFORM interno.sp_reportes_validar(v_actor, p_id_hotel, p_fecha_desde, p_fecha_hasta);
    IF p_limite IS NULL OR p_limite < 1 OR p_limite > 100 THEN
        PERFORM interno.sp_comun_error('HH422', 'limite_invalido', 'El límite debe estar entre 1 y 100');
    END IF;

    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY count(*) DESC, sum(r.fecha_salida - r.fecha_entrada) DESC, sum(r.total) DESC))::int,
           c.id_cliente, c.nombres || ' ' || c.apellidos, u.correo, c.telefono,
           count(*)::int, sum(r.fecha_salida - r.fecha_entrada)::int, sum(r.total)::numeric(12,2), max(r.fecha_entrada)
      FROM reservacion r
      JOIN cliente c ON c.id_cliente = r.id_cliente
      LEFT JOIN usuario u ON u.id_usuario = c.id_usuario
     WHERE r.estado IN ('en_curso', 'finalizada')
       AND r.fecha_entrada BETWEEN p_fecha_desde AND p_fecha_hasta
       AND (p_id_hotel IS NULL OR r.id_hotel = p_id_hotel)
     GROUP BY c.id_cliente, c.nombres, c.apellidos, u.correo, c.telefono
     ORDER BY 1
     LIMIT p_limite;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_cancelaciones(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_tipo              TEXT,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_reservacion       BIGINT,
    codigo               VARCHAR,
    hotel                VARCHAR,
    cliente              TEXT,
    estado               VARCHAR,
    fecha_evento         TIMESTAMPTZ,
    realizado_por        TEXT,
    motivo               VARCHAR,
    fecha_entrada        DATE,
    dias_anticipacion    INTEGER,
    total                DECIMAL(10,2),
    anticipo_pagado      DECIMAL(10,2),
    total_registros      BIGINT)
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
    PERFORM interno.sp_reportes_validar(v_actor, p_id_hotel, p_fecha_desde, p_fecha_hasta);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    IF p_tipo IS NOT NULL AND p_tipo NOT IN ('cancelada', 'no_presentado', 'expirada') THEN
        PERFORM interno.sp_comun_error('HH422', 'tipo_invalido', 'Tipo no válido: cancelada, no_presentado o expirada');
    END IF;

    RETURN QUERY
    SELECT r.id_reservacion, r.codigo, ho.nombre, c.nombres || ' ' || c.apellidos, r.estado, eh.creado_en,
           CASE WHEN eh.id_usuario IS NULL THEN 'Sistema'
                WHEN u.id_usuario = c.id_usuario THEN 'El cliente'
                ELSE u.correo::text END,
           eh.motivo, r.fecha_entrada,
           (r.fecha_entrada - (eh.creado_en AT TIME ZONE 'America/Guatemala')::date)::int,
           r.total,
           (SELECT COALESCE(sum(p.monto), 0)::numeric(10,2) FROM pago p
             WHERE p.id_reservacion = r.id_reservacion AND p.estado = 'aprobado' AND p.tipo <> 'reembolso'),
           count(*) OVER ()
      FROM reservacion r
      JOIN hotel ho ON ho.id_hotel = r.id_hotel
      JOIN cliente c ON c.id_cliente = r.id_cliente
      JOIN reservacion_estado_historial eh ON eh.id_reservacion = r.id_reservacion AND eh.estado_nuevo = r.estado
      LEFT JOIN usuario u ON u.id_usuario = eh.id_usuario
     WHERE r.estado IN ('cancelada', 'no_presentado', 'expirada')
       AND (p_tipo IS NULL OR r.estado = p_tipo)
       AND (p_id_hotel IS NULL OR r.id_hotel = p_id_hotel)
       AND eh.creado_en >= (p_fecha_desde::timestamp AT TIME ZONE 'America/Guatemala')
       AND eh.creado_en <  ((p_fecha_hasta + 1)::timestamp AT TIME ZONE 'America/Guatemala')
     ORDER BY eh.creado_en DESC, r.id_reservacion DESC
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_cancelaciones_resumen(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE)
RETURNS TABLE (estado VARCHAR, cantidad INTEGER, valor DECIMAL(12,2), dias_anticipacion_promedio DECIMAL(6,1))
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
    PERFORM interno.sp_reportes_validar(v_actor, p_id_hotel, p_fecha_desde, p_fecha_hasta);

    RETURN QUERY
    SELECT e.estado::varchar, count(x.id_reservacion)::int, COALESCE(sum(x.total), 0)::numeric(12,2),
           round(avg(x.dias), 1)::numeric(6,1)
      FROM (VALUES ('cancelada'), ('no_presentado'), ('expirada')) AS e(estado)
      LEFT JOIN (
            SELECT r.id_reservacion, r.estado, r.total,
                   r.fecha_entrada - (eh.creado_en AT TIME ZONE 'America/Guatemala')::date AS dias
              FROM reservacion r
              JOIN reservacion_estado_historial eh ON eh.id_reservacion = r.id_reservacion AND eh.estado_nuevo = r.estado
             WHERE r.estado IN ('cancelada', 'no_presentado', 'expirada')
               AND (p_id_hotel IS NULL OR r.id_hotel = p_id_hotel)
               AND eh.creado_en >= (p_fecha_desde::timestamp AT TIME ZONE 'America/Guatemala')
               AND eh.creado_en <  ((p_fecha_hasta + 1)::timestamp AT TIME ZONE 'America/Guatemala')
           ) x ON x.estado = e.estado
     GROUP BY e.estado
     ORDER BY e.estado;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_cupones(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE)
RETURNS TABLE (
    codigo              CITEXT,
    tipo                VARCHAR,
    valor               DECIMAL(10,2),
    usos                INTEGER,
    devueltos           INTEGER,
    descuento_otorgado  DECIMAL(12,2),
    ventas_con_cupon    DECIMAL(12,2))
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
    PERFORM interno.sp_reportes_validar(v_actor, p_id_hotel, p_fecha_desde, p_fecha_hasta);

    RETURN QUERY
    SELECT c.codigo, c.tipo, c.valor,
           count(*) FILTER (WHERE cu.estado = 'aplicado')::int,
           count(*) FILTER (WHERE cu.estado = 'devuelto')::int,
           COALESCE(sum(cu.monto_descuento) FILTER (WHERE cu.estado = 'aplicado'), 0)::numeric(12,2),
           COALESCE(sum(r.total) FILTER (WHERE cu.estado = 'aplicado'
                                          AND r.estado IN ('confirmada', 'en_curso', 'finalizada')), 0)::numeric(12,2)
      FROM cupon_uso cu
      JOIN cupon c ON c.id_cupon = cu.id_cupon
      JOIN reservacion r ON r.id_reservacion = cu.id_reservacion
     WHERE (p_id_hotel IS NULL OR r.id_hotel = p_id_hotel)
       AND cu.creado_en >= (p_fecha_desde::timestamp AT TIME ZONE 'America/Guatemala')
       AND cu.creado_en <  ((p_fecha_hasta + 1)::timestamp AT TIME ZONE 'America/Guatemala')
     GROUP BY c.id_cupon, c.codigo, c.tipo, c.valor
     ORDER BY 6 DESC, c.codigo;
END;
$$;

CREATE OR REPLACE FUNCTION sp_reportes_inventario(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_clase             TEXT)
RETURNS TABLE (
    id_articulo     BIGINT,
    articulo        VARCHAR,
    clase           VARCHAR,
    unidad_medida   VARCHAR,
    entradas        DECIMAL(12,2),
    consumo         DECIMAL(12,2),
    faltantes       DECIMAL(12,2),
    otras_bajas     DECIMAL(12,2),
    ajustes_neto    DECIMAL(12,2),
    existencia_hoy  DECIMAL(12,2))
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
    IF p_id_hotel IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'hotel_requerido', 'El reporte de inventario es por hotel');
    END IF;
    PERFORM interno.sp_reportes_validar(v_actor, p_id_hotel, p_fecha_desde, p_fecha_hasta);

    RETURN QUERY
    SELECT a.id_articulo, a.nombre, a.clase, a.unidad_medida,
           COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo = 'entrada'), 0)::numeric(12,2),
           COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo = 'salida'), 0)::numeric(12,2),
           COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo = 'baja' AND m.id_lote_lavanderia IS NOT NULL), 0)::numeric(12,2),
           COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo = 'baja' AND m.id_lote_lavanderia IS NULL), 0)::numeric(12,2),
           (COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo = 'ajuste_positivo'), 0)
            - COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo = 'ajuste_negativo'), 0))::numeric(12,2),
           (SELECT COALESCE(sum(e.cantidad), 0)::numeric(12,2) FROM existencia e WHERE e.id_articulo = a.id_articulo)
      FROM articulo a
      LEFT JOIN movimiento_inventario m ON m.id_articulo = a.id_articulo
            AND m.creado_en >= (p_fecha_desde::timestamp AT TIME ZONE 'America/Guatemala')
            AND m.creado_en <  ((p_fecha_hasta + 1)::timestamp AT TIME ZONE 'America/Guatemala')
     WHERE a.id_hotel = p_id_hotel
       AND (p_clase IS NULL OR a.clase = p_clase)
       AND (a.activo OR m.id_movimiento_inventario IS NOT NULL)
     GROUP BY a.id_articulo, a.nombre, a.clase, a.unidad_medida
     ORDER BY a.clase, a.nombre;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_reportes_resumen_dashboard(BIGINT, BIGINT),
    sp_reportes_ingresos(BIGINT, BIGINT, DATE, DATE, TEXT),
    sp_reportes_ocupacion(BIGINT, BIGINT, DATE, DATE),
    sp_reportes_ocupacion_diaria(BIGINT, BIGINT, DATE, DATE),
    sp_reportes_clientes_frecuentes(BIGINT, BIGINT, DATE, DATE, INTEGER),
    sp_reportes_cancelaciones(BIGINT, BIGINT, DATE, DATE, TEXT, INTEGER, INTEGER),
    sp_reportes_cancelaciones_resumen(BIGINT, BIGINT, DATE, DATE),
    sp_reportes_cupones(BIGINT, BIGINT, DATE, DATE),
    sp_reportes_inventario(BIGINT, BIGINT, DATE, DATE, TEXT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('032_sp_reportes.sql');