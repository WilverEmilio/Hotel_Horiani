-- =============================================================================
-- 028_sp_inventario.sql
-- Inventario de insumos y blancos, y lavandería (RN-08).
--
-- La existencia nunca se edita directamente: toda variación pasa por
-- interno.sp_inventario_mover, que bloquea las existencias, valida, las
-- actualiza y deja el movimiento (inmutable) con la existencia resultante.
--
-- Insumos (jabón, papel, cloro...): solo viven en 'bodega'.
--   entrada (compra) -> bodega;  salida (consumo) bodega -> habitación;
--   ajuste por conteo físico;  baja.
-- Blancos (toallas, sábanas, fundas): circulan entre ubicaciones.
--   entrada (compra) -> bodega
--   limpieza coloca blancos limpios:      bodega       -> habitaciones
--   lavandería recibe un lote (sucios):   habitaciones -> lavanderia
--   lavandería devuelve el lote (limpios): lavanderia  -> bodega
--   lo que no regresa es un faltante:     baja desde lavanderia, con responsable
-- Cada hotel tiene su propio inventario; no hay traslados entre hoteles.
-- =============================================================================

CREATE OR REPLACE FUNCTION interno.sp_inventario_mover(
    p_id_usuario          BIGINT,
    p_id_articulo         BIGINT,
    p_tipo                TEXT,
    p_origen              TEXT,
    p_destino             TEXT,
    p_cantidad            DECIMAL(12,2),
    p_motivo              TEXT,
    p_id_habitacion       BIGINT,
    p_id_lote_lavanderia  BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_articulo        articulo%ROWTYPE;
    v_disponible      NUMERIC;
    v_res_origen      NUMERIC;
    v_res_destino     NUMERIC;
    v_id_movimiento   BIGINT;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'cantidad_invalida', 'La cantidad debe ser mayor que cero');
    END IF;

    SELECT a.* INTO v_articulo FROM articulo a WHERE a.id_articulo = p_id_articulo;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'articulo_no_encontrado', 'Artículo no encontrado');
    END IF;
    IF NOT v_articulo.activo THEN
        PERFORM interno.sp_comun_error('HH409', 'articulo_inactivo', format('El artículo %s está inactivo', v_articulo.nombre));
    END IF;
    IF v_articulo.clase = 'insumo' AND (COALESCE(p_origen, 'bodega') <> 'bodega' OR COALESCE(p_destino, 'bodega') <> 'bodega') THEN
        PERFORM interno.sp_comun_error('HH422', 'ubicacion_invalida', 'Los insumos solo se manejan en bodega');
    END IF;
    IF p_id_habitacion IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM habitacion h WHERE h.id_habitacion = p_id_habitacion AND h.id_hotel = v_articulo.id_hotel) THEN
        PERFORM interno.sp_comun_error('HH422', 'habitacion_invalida', 'La habitación no es de este hotel');
    END IF;

    PERFORM 1 FROM existencia e
     WHERE e.id_articulo = p_id_articulo AND e.ubicacion IN (p_origen, p_destino)
     ORDER BY e.ubicacion
       FOR UPDATE;

    IF p_origen IS NOT NULL THEN
        SELECT e.cantidad INTO v_disponible FROM existencia e
         WHERE e.id_articulo = p_id_articulo AND e.ubicacion = p_origen;
        IF COALESCE(v_disponible, 0) < p_cantidad THEN
            PERFORM interno.sp_comun_error('HH409', 'existencia_insuficiente',
                format('Solo hay %s %s de %s en %s', to_char(COALESCE(v_disponible, 0), 'FM999999990.##'),
                       v_articulo.unidad_medida, v_articulo.nombre, p_origen));
        END IF;
        UPDATE existencia e SET cantidad = e.cantidad - p_cantidad
         WHERE e.id_articulo = p_id_articulo AND e.ubicacion = p_origen
        RETURNING e.cantidad INTO v_res_origen;
    END IF;

    IF p_destino IS NOT NULL THEN
        INSERT INTO existencia (id_articulo, ubicacion, cantidad)
        VALUES (p_id_articulo, p_destino, p_cantidad)
        ON CONFLICT (id_articulo, ubicacion) DO UPDATE SET cantidad = existencia.cantidad + EXCLUDED.cantidad
        RETURNING existencia.cantidad INTO v_res_destino;
    END IF;

    INSERT INTO movimiento_inventario (id_articulo, tipo, ubicacion_origen, ubicacion_destino, cantidad,
                                       existencia_resultante_origen, existencia_resultante_destino, motivo,
                                       id_habitacion, id_lote_lavanderia, id_usuario)
    VALUES (p_id_articulo, p_tipo, p_origen, p_destino, p_cantidad, v_res_origen, v_res_destino,
            NULLIF(btrim(p_motivo), ''), p_id_habitacion, p_id_lote_lavanderia, p_id_usuario)
    RETURNING id_movimiento_inventario INTO v_id_movimiento;

    RETURN v_id_movimiento;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_inventario_articulo(p_actor interno.tp_actor, p_id_articulo BIGINT)
RETURNS articulo
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_articulo articulo%ROWTYPE;
BEGIN
    SELECT a.* INTO v_articulo FROM articulo a WHERE a.id_articulo = p_id_articulo;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'articulo_no_encontrado', 'Artículo no encontrado');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(p_actor, v_articulo.id_hotel);
    RETURN v_articulo;
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_inventario_leer_items(p_items JSONB)
RETURNS TABLE (id_articulo BIGINT, cantidad DECIMAL(12,2))
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'items_requeridos', 'Indique al menos un artículo con su cantidad');
    END IF;
    BEGIN
        RETURN QUERY
        SELECT (x ->> 'id_articulo')::bigint, (x ->> 'cantidad')::numeric(12,2)
          FROM jsonb_array_elements(p_items) AS t(x);
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
        PERFORM interno.sp_comun_error('HH422', 'items_formato', 'Cada artículo debe tener id_articulo y cantidad numéricos');
    END;
    IF (SELECT count(DISTINCT x ->> 'id_articulo') FROM jsonb_array_elements(p_items) AS t(x))
       <> jsonb_array_length(p_items) THEN
        PERFORM interno.sp_comun_error('HH422', 'articulo_repetido', 'Un artículo aparece dos veces');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_crear_categoria(p_id_usuario_actor BIGINT, p_nombre TEXT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');

    INSERT INTO categoria_articulo (nombre) VALUES (btrim(p_nombre)) RETURNING id_categoria_articulo INTO v_id;
    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'inventario', 'categoria_articulo',
        v_id::text, 'crear', NULL, jsonb_build_object('nombre', btrim(p_nombre)));
    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'categoria_duplicada', 'Ya existe una categoría con ese nombre');
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_listar_categorias(p_id_usuario_actor BIGINT)
RETURNS TABLE (id_categoria_articulo BIGINT, nombre VARCHAR)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR', 'INSUMOS_CONSUMIR', 'LAVANDERIA_GESTIONAR');
    RETURN QUERY SELECT c.id_categoria_articulo, c.nombre FROM categoria_articulo c WHERE c.activo ORDER BY c.nombre;
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_crear_articulo(
    p_id_usuario_actor       BIGINT,
    p_id_hotel               BIGINT,
    p_id_categoria_articulo  BIGINT,
    p_nombre                 TEXT,
    p_clase                  TEXT,
    p_unidad_medida          TEXT,
    p_existencia_minima      DECIMAL(12,2))
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_id           BIGINT;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');
    PERFORM interno.sp_comun_exigir_texto(p_unidad_medida, 'unidad de medida');
    IF p_clase IS NULL OR p_clase NOT IN ('insumo', 'blanco') THEN
        PERFORM interno.sp_comun_error('HH422', 'clase_invalida', 'La clase debe ser insumo o blanco');
    END IF;

    INSERT INTO articulo (id_hotel, id_categoria_articulo, nombre, clase, unidad_medida, existencia_minima)
    VALUES (p_id_hotel, p_id_categoria_articulo, btrim(p_nombre), p_clase, btrim(p_unidad_medida),
            COALESCE(p_existencia_minima, 0))
    RETURNING id_articulo INTO v_id;

    INSERT INTO existencia (id_articulo, ubicacion, cantidad)
    SELECT v_id, u, 0
      FROM unnest(CASE WHEN p_clase = 'insumo' THEN ARRAY['bodega']
                       ELSE ARRAY['bodega', 'habitaciones', 'lavanderia'] END) AS u;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'inventario', 'articulo',
        v_id::text, 'crear', NULL, (SELECT to_jsonb(a) FROM articulo a WHERE a.id_articulo = v_id));
    RETURN v_id;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'articulo_duplicado', 'Ese hotel ya tiene un artículo con ese nombre');
    WHEN foreign_key_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'categoria_invalida', 'La categoría o el hotel no existen');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'La existencia mínima no puede ser negativa');
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_actualizar_articulo(
    p_id_usuario_actor       BIGINT,
    p_id_articulo            BIGINT,
    p_id_categoria_articulo  BIGINT,
    p_nombre                 TEXT,
    p_unidad_medida          TEXT,
    p_existencia_minima      DECIMAL(12,2),
    p_activo                 BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_articulo     articulo%ROWTYPE;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR');
    v_articulo := interno.sp_inventario_articulo(v_actor, p_id_articulo);
    PERFORM interno.sp_comun_exigir_texto(p_nombre, 'nombre');
    PERFORM interno.sp_comun_exigir_texto(p_unidad_medida, 'unidad de medida');

    PERFORM 1 FROM articulo a WHERE a.id_articulo = p_id_articulo FOR UPDATE;
    IF p_activo IS FALSE AND v_articulo.activo AND EXISTS (
        SELECT 1 FROM existencia e WHERE e.id_articulo = p_id_articulo AND e.cantidad > 0) THEN
        PERFORM interno.sp_comun_error('HH409', 'articulo_con_existencia',
            'No se puede desactivar un artículo con existencias; dé de baja o ajuste primero');
    END IF;

    UPDATE articulo a
       SET id_categoria_articulo = p_id_categoria_articulo, nombre = btrim(p_nombre),
           unidad_medida = btrim(p_unidad_medida), existencia_minima = COALESCE(p_existencia_minima, 0),
           activo = COALESCE(p_activo, a.activo)
     WHERE a.id_articulo = p_id_articulo;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_articulo.id_hotel, 'inventario', 'articulo',
        p_id_articulo::text,
        CASE WHEN p_activo IS FALSE AND v_articulo.activo THEN 'desactivar' ELSE 'modificar' END,
        to_jsonb(v_articulo), (SELECT to_jsonb(a) FROM articulo a WHERE a.id_articulo = p_id_articulo));
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'articulo_duplicado', 'Ese hotel ya tiene un artículo con ese nombre');
    WHEN foreign_key_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'categoria_invalida', 'La categoría no existe');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'La existencia mínima no puede ser negativa');
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_registrar_entrada(
    p_id_usuario_actor  BIGINT,
    p_id_articulo       BIGINT,
    p_cantidad          DECIMAL(12,2),
    p_motivo            TEXT)
RETURNS TABLE (id_movimiento BIGINT, existencia_bodega DECIMAL(12,2))
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor  interno.tp_actor;
    v_id     BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR');
    PERFORM interno.sp_inventario_articulo(v_actor, p_id_articulo);

    v_id := interno.sp_inventario_mover(p_id_usuario_actor, p_id_articulo, 'entrada', NULL, 'bodega',
                                        p_cantidad, p_motivo, NULL, NULL);
    RETURN QUERY SELECT v_id, m.existencia_resultante_destino
                   FROM movimiento_inventario m WHERE m.id_movimiento_inventario = v_id;
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_registrar_conteo(
    p_id_usuario_actor  BIGINT,
    p_id_articulo       BIGINT,
    p_ubicacion         TEXT,
    p_cantidad_contada  DECIMAL(12,2),
    p_motivo            TEXT)
RETURNS TABLE (id_movimiento BIGINT, existencia_anterior DECIMAL(12,2), diferencia DECIMAL(12,2))
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_articulo  articulo%ROWTYPE;
    v_actual    NUMERIC;
    v_dif       NUMERIC;
    v_id        BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR');
    v_articulo := interno.sp_inventario_articulo(v_actor, p_id_articulo);
    PERFORM interno.sp_comun_exigir_texto(p_motivo, 'motivo');
    IF p_cantidad_contada IS NULL OR p_cantidad_contada < 0 THEN
        PERFORM interno.sp_comun_error('HH422', 'cantidad_invalida', 'La cantidad contada no puede ser negativa');
    END IF;

    SELECT e.cantidad INTO v_actual FROM existencia e
     WHERE e.id_articulo = p_id_articulo AND e.ubicacion = p_ubicacion FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH422', 'ubicacion_invalida',
            format('El artículo %s no se maneja en %s', v_articulo.nombre, COALESCE(p_ubicacion, '(sin ubicación)')));
    END IF;

    v_dif := p_cantidad_contada - v_actual;
    IF v_dif > 0 THEN
        v_id := interno.sp_inventario_mover(p_id_usuario_actor, p_id_articulo, 'ajuste_positivo', NULL, p_ubicacion,
                                            v_dif, p_motivo, NULL, NULL);
    ELSIF v_dif < 0 THEN
        v_id := interno.sp_inventario_mover(p_id_usuario_actor, p_id_articulo, 'ajuste_negativo', p_ubicacion, NULL,
                                            -v_dif, p_motivo, NULL, NULL);
    END IF;

    RETURN QUERY SELECT v_id, v_actual::numeric(12,2), v_dif::numeric(12,2);
END;
$$;
CREATE OR REPLACE FUNCTION sp_inventario_registrar_consumo(
    p_id_usuario_actor  BIGINT,
    p_id_articulo       BIGINT,
    p_cantidad          DECIMAL(12,2),
    p_id_habitacion     BIGINT,
    p_motivo            TEXT)
RETURNS TABLE (id_movimiento BIGINT, existencia_bodega DECIMAL(12,2), bajo_minimo BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor     interno.tp_actor;
    v_articulo  articulo%ROWTYPE;
    v_id        BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INSUMOS_CONSUMIR', 'INVENTARIO_GESTIONAR');
    v_articulo := interno.sp_inventario_articulo(v_actor, p_id_articulo);
    IF v_articulo.clase <> 'insumo' THEN
        PERFORM interno.sp_comun_error('HH422', 'no_es_insumo',
            'Los blancos no se consumen: se colocan en habitaciones y pasan por lavandería');
    END IF;

    v_id := interno.sp_inventario_mover(p_id_usuario_actor, p_id_articulo, 'salida', 'bodega', NULL,
                                        p_cantidad, COALESCE(NULLIF(btrim(p_motivo), ''), 'Consumo'), p_id_habitacion, NULL);
    RETURN QUERY SELECT v_id, m.existencia_resultante_origen,
                        m.existencia_resultante_origen < v_articulo.existencia_minima
                   FROM movimiento_inventario m WHERE m.id_movimiento_inventario = v_id;
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_colocar_blancos(
    p_id_usuario_actor  BIGINT,
    p_id_habitacion     BIGINT,
    p_items             JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_id_hotel  BIGINT;
    v_item      RECORD;
    v_articulo  articulo%ROWTYPE;
    v_total     INTEGER := 0;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'LIMPIEZA_GESTIONAR', 'INVENTARIO_GESTIONAR');
    SELECT h.id_hotel INTO v_id_hotel FROM habitacion h WHERE h.id_habitacion = p_id_habitacion;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'habitacion_no_encontrada', 'Habitación no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);

    FOR v_item IN SELECT * FROM interno.sp_inventario_leer_items(p_items) ORDER BY 1 LOOP
        v_articulo := interno.sp_inventario_articulo(v_actor, v_item.id_articulo);
        IF v_articulo.clase <> 'blanco' OR v_articulo.id_hotel <> v_id_hotel THEN
            PERFORM interno.sp_comun_error('HH422', 'no_es_blanco_del_hotel',
                format('El artículo %s no es un blanco de este hotel', v_articulo.nombre));
        END IF;
        PERFORM interno.sp_inventario_mover(p_id_usuario_actor, v_item.id_articulo, 'traslado', 'bodega', 'habitaciones',
                                            v_item.cantidad, 'Colocado en habitación', p_id_habitacion, NULL);
        v_total := v_total + 1;
    END LOOP;
    RETURN v_total;
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_dar_baja(
    p_id_usuario_actor  BIGINT,
    p_id_articulo       BIGINT,
    p_ubicacion         TEXT,
    p_cantidad          DECIMAL(12,2),
    p_motivo            TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_articulo  articulo%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR', 'LAVANDERIA_GESTIONAR');
    v_articulo := interno.sp_inventario_articulo(v_actor, p_id_articulo);
    PERFORM interno.sp_comun_exigir_texto(p_motivo, 'motivo');
    IF NOT interno.sp_comun_tiene_permiso(v_actor, 'INVENTARIO_GESTIONAR') AND v_articulo.clase <> 'blanco' THEN
        PERFORM interno.sp_comun_error('HH403', 'sin_permiso', 'Lavandería solo da de baja blancos');
    END IF;
    IF p_ubicacion IS NULL OR p_ubicacion NOT IN ('bodega', 'habitaciones', 'lavanderia') THEN
        PERFORM interno.sp_comun_error('HH422', 'ubicacion_invalida', 'Ubicación no válida: bodega, habitaciones o lavanderia');
    END IF;

    RETURN interno.sp_inventario_mover(p_id_usuario_actor, p_id_articulo, 'baja', p_ubicacion, NULL,
                                       p_cantidad, p_motivo, NULL, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION sp_lavanderia_recibir_lote(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_items             JSONB,
    p_observacion       TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_id_lote   BIGINT;
    v_item      RECORD;
    v_articulo  articulo%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'LAVANDERIA_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);

    INSERT INTO lote_lavanderia (id_hotel, recibido_por, observacion)
    VALUES (p_id_hotel, p_id_usuario_actor, NULLIF(btrim(p_observacion), ''))
    RETURNING id_lote_lavanderia INTO v_id_lote;

    FOR v_item IN SELECT * FROM interno.sp_inventario_leer_items(p_items) ORDER BY 1 LOOP
        v_articulo := interno.sp_inventario_articulo(v_actor, v_item.id_articulo);
        IF v_articulo.clase <> 'blanco' OR v_articulo.id_hotel <> p_id_hotel THEN
            PERFORM interno.sp_comun_error('HH422', 'no_es_blanco_del_hotel',
                format('El artículo %s no es un blanco de este hotel', v_articulo.nombre));
        END IF;
        INSERT INTO lote_lavanderia_detalle (id_lote_lavanderia, id_hotel, id_articulo, cantidad_recibida)
        VALUES (v_id_lote, p_id_hotel, v_item.id_articulo, v_item.cantidad);
        PERFORM interno.sp_inventario_mover(p_id_usuario_actor, v_item.id_articulo, 'traslado', 'habitaciones',
                                            'lavanderia', v_item.cantidad, format('Lote de lavandería %s', v_id_lote),
                                            NULL, v_id_lote);
    END LOOP;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'inventario', 'lote_lavanderia',
        v_id_lote::text, 'crear', NULL, jsonb_build_object('items', p_items));
    RETURN v_id_lote;
EXCEPTION
    WHEN check_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'cantidad_invalida', 'Las cantidades deben ser mayores que cero');
END;
$$;

CREATE OR REPLACE FUNCTION sp_lavanderia_devolver_lote(
    p_id_usuario_actor  BIGINT,
    p_id_lote           BIGINT,
    p_items             JSONB,
    p_observacion       TEXT)
RETURNS TABLE (id_articulo BIGINT, articulo VARCHAR, recibido DECIMAL(12,2), devuelto DECIMAL(12,2), faltante DECIMAL(12,2))
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor    interno.tp_actor;
    v_lote     lote_lavanderia%ROWTYPE;
    v_det      RECORD;
    v_correo   TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'LAVANDERIA_GESTIONAR');

    SELECT l.* INTO v_lote FROM lote_lavanderia l WHERE l.id_lote_lavanderia = p_id_lote FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'lote_no_encontrado', 'Lote de lavandería no encontrado');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_lote.id_hotel);
    IF v_lote.estado = 'devuelto' THEN
        PERFORM interno.sp_comun_error('HH409', 'lote_cerrado', 'Este lote ya fue devuelto');
    END IF;

    CREATE TEMP TABLE IF NOT EXISTS tmp_devolucion (id_articulo BIGINT PRIMARY KEY, cantidad DECIMAL(12,2)) ON COMMIT DROP;
    TRUNCATE tmp_devolucion;
    INSERT INTO tmp_devolucion SELECT * FROM interno.sp_inventario_leer_items(p_items);

    IF EXISTS (SELECT 1 FROM tmp_devolucion t WHERE t.cantidad < 0) THEN
        PERFORM interno.sp_comun_error('HH422', 'cantidad_invalida', 'Las cantidades devueltas no pueden ser negativas');
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_devolucion t WHERE NOT EXISTS (
                   SELECT 1 FROM lote_lavanderia_detalle d
                    WHERE d.id_lote_lavanderia = p_id_lote AND d.id_articulo = t.id_articulo))
       OR EXISTS (SELECT 1 FROM lote_lavanderia_detalle d WHERE d.id_lote_lavanderia = p_id_lote
                     AND NOT EXISTS (SELECT 1 FROM tmp_devolucion t WHERE t.id_articulo = d.id_articulo)) THEN
        PERFORM interno.sp_comun_error('HH422', 'lote_incompleto',
            'Indique lo devuelto de cada artículo del lote, y solo de esos artículos');
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_devolucion t JOIN lote_lavanderia_detalle d
                 ON d.id_lote_lavanderia = p_id_lote AND d.id_articulo = t.id_articulo
                WHERE t.cantidad > d.cantidad_recibida) THEN
        PERFORM interno.sp_comun_error('HH422', 'devuelto_mayor_a_recibido', 'No se puede devolver más de lo recibido');
    END IF;

    SELECT u.correo INTO v_correo FROM usuario u WHERE u.id_usuario = p_id_usuario_actor;

    FOR v_det IN
        SELECT d.id_lote_lavanderia_detalle, d.id_articulo, d.cantidad_recibida, t.cantidad AS devuelta
          FROM lote_lavanderia_detalle d JOIN tmp_devolucion t ON t.id_articulo = d.id_articulo
         WHERE d.id_lote_lavanderia = p_id_lote
         ORDER BY d.id_articulo
    LOOP
        UPDATE lote_lavanderia_detalle d SET cantidad_devuelta = v_det.devuelta
         WHERE d.id_lote_lavanderia_detalle = v_det.id_lote_lavanderia_detalle;
        IF v_det.devuelta > 0 THEN
            PERFORM interno.sp_inventario_mover(p_id_usuario_actor, v_det.id_articulo, 'traslado', 'lavanderia', 'bodega',
                                                v_det.devuelta, format('Devolución del lote %s', p_id_lote), NULL, p_id_lote);
        END IF;
        IF v_det.cantidad_recibida > v_det.devuelta THEN
            PERFORM interno.sp_inventario_mover(p_id_usuario_actor, v_det.id_articulo, 'baja', 'lavanderia', NULL,
                v_det.cantidad_recibida - v_det.devuelta,
                format('Faltante del lote %s; responsable: %s', p_id_lote, v_correo), NULL, p_id_lote);
        END IF;
    END LOOP;

    UPDATE lote_lavanderia l
       SET estado = 'devuelto', devuelto_por = p_id_usuario_actor, devuelto_en = now(),
           observacion = COALESCE(NULLIF(btrim(p_observacion), ''), l.observacion)
     WHERE l.id_lote_lavanderia = p_id_lote;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_lote.id_hotel, 'inventario', 'lote_lavanderia',
        p_id_lote::text, 'cambio_estado', jsonb_build_object('estado', 'recibido'),
        jsonb_build_object('estado', 'devuelto', 'items', p_items));

    RETURN QUERY
    SELECT d.id_articulo, a.nombre, d.cantidad_recibida, d.cantidad_devuelta, d.cantidad_recibida - d.cantidad_devuelta
      FROM lote_lavanderia_detalle d JOIN articulo a ON a.id_articulo = d.id_articulo
     WHERE d.id_lote_lavanderia = p_id_lote
     ORDER BY a.nombre;
END;
$$;

CREATE OR REPLACE FUNCTION sp_lavanderia_listar_lotes(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_estado            TEXT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_lote_lavanderia  BIGINT,
    estado              VARCHAR,
    recibido_en         TIMESTAMPTZ,
    recibido_por        CITEXT,
    devuelto_en         TIMESTAMPTZ,
    devuelto_por        CITEXT,
    piezas_recibidas    DECIMAL(12,2),
    piezas_devueltas    DECIMAL(12,2),
    faltante            DECIMAL(12,2),
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'LAVANDERIA_GESTIONAR', 'INVENTARIO_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);

    RETURN QUERY
    SELECT l.id_lote_lavanderia, l.estado, l.recibido_en, ur.correo, l.devuelto_en, ud.correo,
           s.recibidas, s.devueltas, CASE WHEN l.estado = 'devuelto' THEN s.recibidas - s.devueltas END,
           count(*) OVER ()
      FROM lote_lavanderia l
      JOIN usuario ur ON ur.id_usuario = l.recibido_por
      LEFT JOIN usuario ud ON ud.id_usuario = l.devuelto_por
     CROSS JOIN LATERAL (
           SELECT sum(d.cantidad_recibida)::numeric(12,2) AS recibidas,
                  COALESCE(sum(d.cantidad_devuelta), 0)::numeric(12,2) AS devueltas
             FROM lote_lavanderia_detalle d WHERE d.id_lote_lavanderia = l.id_lote_lavanderia) s
     WHERE l.id_hotel = p_id_hotel
       AND (p_estado IS NULL OR l.estado = p_estado)
       AND (p_fecha_desde IS NULL OR (l.recibido_en AT TIME ZONE 'America/Guatemala')::date >= p_fecha_desde)
       AND (p_fecha_hasta IS NULL OR (l.recibido_en AT TIME ZONE 'America/Guatemala')::date <= p_fecha_hasta)
     ORDER BY l.recibido_en DESC, l.id_lote_lavanderia DESC
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_lavanderia_obtener_lote(p_id_usuario_actor BIGINT, p_id_lote BIGINT)
RETURNS TABLE (
    id_lote_lavanderia  BIGINT,
    estado              VARCHAR,
    recibido_en         TIMESTAMPTZ,
    devuelto_en         TIMESTAMPTZ,
    observacion         VARCHAR,
    detalle             JSONB)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'LAVANDERIA_GESTIONAR', 'INVENTARIO_GESTIONAR');
    SELECT l.id_hotel INTO v_id_hotel FROM lote_lavanderia l WHERE l.id_lote_lavanderia = p_id_lote;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'lote_no_encontrado', 'Lote de lavandería no encontrado');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);

    RETURN QUERY
    SELECT l.id_lote_lavanderia, l.estado, l.recibido_en, l.devuelto_en, l.observacion,
           (SELECT jsonb_agg(jsonb_build_object('id_articulo', a.id_articulo, 'articulo', a.nombre,
                                                'recibido', d.cantidad_recibida, 'devuelto', d.cantidad_devuelta,
                                                'faltante', d.cantidad_recibida - d.cantidad_devuelta)
                             ORDER BY a.nombre)
              FROM lote_lavanderia_detalle d JOIN articulo a ON a.id_articulo = d.id_articulo
             WHERE d.id_lote_lavanderia = l.id_lote_lavanderia)
      FROM lote_lavanderia l
     WHERE l.id_lote_lavanderia = p_id_lote;
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_listar_existencias(
    p_id_usuario_actor   BIGINT,
    p_id_hotel           BIGINT,
    p_clase              TEXT,
    p_busqueda           TEXT,
    p_solo_bajo_minimo   BOOLEAN,
    p_incluir_inactivos  BOOLEAN,
    p_pagina             INTEGER,
    p_tamano             INTEGER,
    p_orden              TEXT,
    p_direccion          TEXT)
RETURNS TABLE (
    id_articulo        BIGINT,
    nombre             VARCHAR,
    categoria          VARCHAR,
    clase              VARCHAR,
    unidad_medida      VARCHAR,
    bodega             DECIMAL(12,2),
    habitaciones       DECIMAL(12,2),
    lavanderia         DECIMAL(12,2),
    total              DECIMAL(12,2),
    existencia_minima  DECIMAL(12,2),
    bajo_minimo        BOOLEAN,
    activo             BOOLEAN,
    total_registros    BIGINT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR', 'INSUMOS_CONSUMIR', 'LAVANDERIA_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    PERFORM interno.sp_comun_validar_direccion(p_direccion);
    IF p_orden IS NULL OR p_orden NOT IN ('nombre', 'bodega', 'categoria') THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_invalido', 'Orden no válido: use nombre, bodega o categoria');
    END IF;

    RETURN QUERY
    WITH x AS (
        SELECT a.id_articulo, a.nombre, c.nombre AS categoria, a.clase, a.unidad_medida,
               COALESCE(sum(e.cantidad) FILTER (WHERE e.ubicacion = 'bodega'), 0)::numeric(12,2) AS bodega,
               COALESCE(sum(e.cantidad) FILTER (WHERE e.ubicacion = 'habitaciones'), 0)::numeric(12,2) AS habitaciones,
               COALESCE(sum(e.cantidad) FILTER (WHERE e.ubicacion = 'lavanderia'), 0)::numeric(12,2) AS lavanderia,
               COALESCE(sum(e.cantidad), 0)::numeric(12,2) AS total,
               a.existencia_minima, a.activo
          FROM articulo a
          JOIN categoria_articulo c ON c.id_categoria_articulo = a.id_categoria_articulo
          LEFT JOIN existencia e ON e.id_articulo = a.id_articulo
         WHERE a.id_hotel = p_id_hotel
           AND (a.activo OR COALESCE(p_incluir_inactivos, FALSE))
           AND (p_clase IS NULL OR a.clase = p_clase)
           AND (v_busqueda IS NULL OR a.nombre ILIKE '%' || v_busqueda || '%' OR c.nombre ILIKE '%' || v_busqueda || '%')
         GROUP BY a.id_articulo, c.nombre
    )
    SELECT x.id_articulo, x.nombre, x.categoria, x.clase, x.unidad_medida, x.bodega, x.habitaciones, x.lavanderia,
           x.total, x.existencia_minima, x.bodega < x.existencia_minima, x.activo, count(*) OVER ()
      FROM x
     WHERE NOT COALESCE(p_solo_bajo_minimo, FALSE) OR x.bodega < x.existencia_minima
     ORDER BY
        CASE WHEN p_orden = 'nombre'    AND p_direccion = 'asc'  THEN x.nombre END ASC,
        CASE WHEN p_orden = 'nombre'    AND p_direccion = 'desc' THEN x.nombre END DESC,
        CASE WHEN p_orden = 'bodega'    AND p_direccion = 'asc'  THEN x.bodega END ASC,
        CASE WHEN p_orden = 'bodega'    AND p_direccion = 'desc' THEN x.bodega END DESC,
        CASE WHEN p_orden = 'categoria' AND p_direccion = 'asc'  THEN x.categoria END ASC,
        CASE WHEN p_orden = 'categoria' AND p_direccion = 'desc' THEN x.categoria END DESC,
        x.id_articulo
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_listar_movimientos(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_id_articulo       BIGINT,
    p_tipo              TEXT,
    p_fecha_desde       DATE,
    p_fecha_hasta       DATE,
    p_pagina            INTEGER,
    p_tamano            INTEGER)
RETURNS TABLE (
    id_movimiento        BIGINT,
    fecha                TIMESTAMPTZ,
    id_articulo          BIGINT,
    articulo             VARCHAR,
    tipo                 VARCHAR,
    origen               VARCHAR,
    destino              VARCHAR,
    cantidad             DECIMAL(12,2),
    resultante_origen    DECIMAL(12,2),
    resultante_destino   DECIMAL(12,2),
    motivo               VARCHAR,
    habitacion           VARCHAR,
    id_lote_lavanderia   BIGINT,
    usuario              CITEXT,
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR', 'LAVANDERIA_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);

    RETURN QUERY
    SELECT m.id_movimiento_inventario, m.creado_en, a.id_articulo, a.nombre, m.tipo, m.ubicacion_origen,
           m.ubicacion_destino, m.cantidad, m.existencia_resultante_origen, m.existencia_resultante_destino,
           m.motivo, h.numero, m.id_lote_lavanderia, u.correo, count(*) OVER ()
      FROM movimiento_inventario m
      JOIN articulo a ON a.id_articulo = m.id_articulo
      JOIN usuario u ON u.id_usuario = m.id_usuario
      LEFT JOIN habitacion h ON h.id_habitacion = m.id_habitacion
     WHERE a.id_hotel = p_id_hotel
       AND (p_id_articulo IS NULL OR m.id_articulo = p_id_articulo)
       AND (p_tipo IS NULL OR m.tipo = p_tipo)
       AND (p_fecha_desde IS NULL OR (m.creado_en AT TIME ZONE 'America/Guatemala')::date >= p_fecha_desde)
       AND (p_fecha_hasta IS NULL OR (m.creado_en AT TIME ZONE 'America/Guatemala')::date <= p_fecha_hasta)
     ORDER BY m.creado_en DESC, m.id_movimiento_inventario DESC
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

CREATE OR REPLACE FUNCTION sp_inventario_alertas(p_id_usuario_actor BIGINT, p_id_hotel BIGINT)
RETURNS TABLE (id_articulo BIGINT, nombre VARCHAR, clase VARCHAR, unidad_medida VARCHAR,
               bodega DECIMAL(12,2), existencia_minima DECIMAL(12,2), faltan DECIMAL(12,2))
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'INVENTARIO_GESTIONAR', 'INSUMOS_CONSUMIR',
                                            'LAVANDERIA_GESTIONAR', 'REPORTES_VER');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);

    RETURN QUERY
    SELECT a.id_articulo, a.nombre, a.clase, a.unidad_medida, e.cantidad, a.existencia_minima,
           (a.existencia_minima - e.cantidad)::numeric(12,2)
      FROM articulo a
      JOIN existencia e ON e.id_articulo = a.id_articulo AND e.ubicacion = 'bodega'
     WHERE a.id_hotel = p_id_hotel AND a.activo AND e.cantidad < a.existencia_minima
     ORDER BY (a.existencia_minima - e.cantidad) / NULLIF(a.existencia_minima, 0) DESC, a.nombre;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_inventario_crear_categoria(BIGINT, TEXT),
    sp_inventario_listar_categorias(BIGINT),
    sp_inventario_crear_articulo(BIGINT, BIGINT, BIGINT, TEXT, TEXT, TEXT, DECIMAL),
    sp_inventario_actualizar_articulo(BIGINT, BIGINT, BIGINT, TEXT, TEXT, DECIMAL, BOOLEAN),
    sp_inventario_registrar_entrada(BIGINT, BIGINT, DECIMAL, TEXT),
    sp_inventario_registrar_conteo(BIGINT, BIGINT, TEXT, DECIMAL, TEXT),
    sp_inventario_registrar_consumo(BIGINT, BIGINT, DECIMAL, BIGINT, TEXT),
    sp_inventario_colocar_blancos(BIGINT, BIGINT, JSONB),
    sp_inventario_dar_baja(BIGINT, BIGINT, TEXT, DECIMAL, TEXT),
    sp_lavanderia_recibir_lote(BIGINT, BIGINT, JSONB, TEXT),
    sp_lavanderia_devolver_lote(BIGINT, BIGINT, JSONB, TEXT),
    sp_lavanderia_listar_lotes(BIGINT, BIGINT, TEXT, DATE, DATE, INTEGER, INTEGER),
    sp_lavanderia_obtener_lote(BIGINT, BIGINT),
    sp_inventario_listar_existencias(BIGINT, BIGINT, TEXT, TEXT, BOOLEAN, BOOLEAN, INTEGER, INTEGER, TEXT, TEXT),
    sp_inventario_listar_movimientos(BIGINT, BIGINT, BIGINT, TEXT, DATE, DATE, INTEGER, INTEGER),
    sp_inventario_alertas(BIGINT, BIGINT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('028_sp_inventario.sql');