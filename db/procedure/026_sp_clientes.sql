-- =============================================================================
-- 026_sp_clientes.sql
-- Clientes (RN-06). Los clientes son de la cadena: el mismo cliente reserva
-- en cualquiera de los 4 hoteles y su historial se ve completo.
-- =============================================================================

CREATE OR REPLACE FUNCTION interno.sp_clientes_estadisticas(p_id_cliente BIGINT)
RETURNS TABLE (
    estancias           INTEGER,
    noches              INTEGER,
    total_pagado        DECIMAL(12,2),
    cancelaciones       INTEGER,
    no_presentaciones   INTEGER,
    ultima_estancia     DATE)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT count(*) FILTER (WHERE r.estado = 'finalizada')::int,
           COALESCE(sum(r.fecha_salida - r.fecha_entrada) FILTER (WHERE r.estado = 'finalizada'), 0)::int,
           COALESCE((SELECT sum(CASE WHEN p.tipo <> 'reembolso' THEN p.monto
                                     WHEN o.estado = 'aprobado' THEN -p.monto
                                     ELSE 0 END)
                       FROM pago p
                       JOIN reservacion r2 ON r2.id_reservacion = p.id_reservacion
                       LEFT JOIN pago o ON o.id_pago = p.id_pago_origen
                      WHERE r2.id_cliente = p_id_cliente AND p.estado = 'aprobado'), 0)::numeric(12,2),
           count(*) FILTER (WHERE r.estado = 'cancelada')::int,
           count(*) FILTER (WHERE r.estado = 'no_presentado')::int,
           max(r.fecha_entrada) FILTER (WHERE r.estado IN ('finalizada', 'en_curso'))
      FROM reservacion r
     WHERE r.id_cliente = p_id_cliente;
$$;

CREATE OR REPLACE FUNCTION sp_clientes_registrar_en_recepcion(
    p_id_usuario_actor  BIGINT,
    p_nombres           TEXT,
    p_apellidos         TEXT,
    p_telefono          TEXT,
    p_tipo_documento    TEXT,
    p_numero_documento  TEXT,
    p_pais              TEXT,
    p_correo            TEXT)
RETURNS TABLE (id_cliente BIGINT, id_usuario BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor        interno.tp_actor;
    v_id_usuario   BIGINT;
    v_id_cliente   BIGINT;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CLIENTES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombres, 'nombres');
    PERFORM interno.sp_comun_exigir_texto(p_apellidos, 'apellidos');
    PERFORM interno.sp_comun_exigir_texto(p_telefono, 'teléfono');
    PERFORM interno.sp_comun_exigir_texto(p_tipo_documento, 'tipo de documento');
    PERFORM interno.sp_comun_exigir_texto(p_numero_documento, 'número de documento');

    IF EXISTS (SELECT 1 FROM cliente c
                WHERE c.tipo_documento = lower(btrim(p_tipo_documento))
                  AND c.numero_documento = btrim(p_numero_documento)) THEN
        PERFORM interno.sp_comun_error('HH409', 'documento_registrado',
            'Ya existe un cliente con ese documento; búsquelo en el listado');
    END IF;

    IF NULLIF(btrim(p_correo), '') IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM usuario u WHERE u.correo = btrim(p_correo)::citext) THEN
            PERFORM interno.sp_comun_error('HH409', 'correo_registrado', 'Ya existe una cuenta con ese correo');
        END IF;
        INSERT INTO usuario (correo, contrasena_hash, id_rol)
        VALUES (lower(btrim(p_correo)), NULL, (SELECT r.id_rol FROM rol r WHERE r.nombre = 'cliente'))
        RETURNING usuario.id_usuario INTO v_id_usuario;
    END IF;

    INSERT INTO cliente (id_usuario, nombres, apellidos, telefono, tipo_documento, numero_documento, pais)
    VALUES (v_id_usuario, btrim(p_nombres), btrim(p_apellidos), btrim(p_telefono),
            lower(btrim(p_tipo_documento)), btrim(p_numero_documento),
            COALESCE(NULLIF(btrim(p_pais), ''), 'Guatemala'))
    RETURNING cliente.id_cliente INTO v_id_cliente;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'clientes', 'cliente',
        v_id_cliente::text, 'crear', NULL,
        (SELECT to_jsonb(c) || jsonb_build_object('correo', lower(btrim(p_correo)))
           FROM cliente c WHERE c.id_cliente = v_id_cliente));

    RETURN QUERY SELECT v_id_cliente, v_id_usuario;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'registro_duplicado', 'El correo o el documento ya están registrados');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'Los datos no tienen un formato válido');
END;
$$;
CREATE OR REPLACE FUNCTION sp_clientes_crear_cuenta(p_id_usuario_actor BIGINT, p_id_cliente BIGINT, p_correo TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor        interno.tp_actor;
    v_id_usuario   BIGINT;
    v_actual       BIGINT;
    v_restriccion  TEXT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CLIENTES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_correo, 'correo');

    SELECT c.id_usuario INTO v_actual FROM cliente c WHERE c.id_cliente = p_id_cliente FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'cliente_no_encontrado', 'Cliente no encontrado');
    END IF;
    IF v_actual IS NOT NULL THEN
        PERFORM interno.sp_comun_error('HH409', 'cliente_con_cuenta', 'Este cliente ya tiene una cuenta');
    END IF;
    IF EXISTS (SELECT 1 FROM usuario u WHERE u.correo = btrim(p_correo)::citext) THEN
        PERFORM interno.sp_comun_error('HH409', 'correo_registrado', 'Ya existe una cuenta con ese correo');
    END IF;

    INSERT INTO usuario (correo, contrasena_hash, id_rol)
    VALUES (lower(btrim(p_correo)), NULL, (SELECT r.id_rol FROM rol r WHERE r.nombre = 'cliente'))
    RETURNING id_usuario INTO v_id_usuario;

    UPDATE cliente c SET id_usuario = v_id_usuario WHERE c.id_cliente = p_id_cliente;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'clientes', 'cliente',
        p_id_cliente::text, 'modificar', jsonb_build_object('id_usuario', NULL),
        jsonb_build_object('id_usuario', v_id_usuario, 'correo', lower(btrim(p_correo))));
    RETURN v_id_usuario;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'correo_registrado', 'Ya existe una cuenta con ese correo');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'El correo no tiene un formato válido');
END;
$$;

CREATE OR REPLACE FUNCTION sp_clientes_actualizar(
    p_id_usuario_actor  BIGINT,
    p_id_cliente        BIGINT,
    p_nombres           TEXT,
    p_apellidos         TEXT,
    p_telefono          TEXT,
    p_tipo_documento    TEXT,
    p_numero_documento  TEXT,
    p_pais              TEXT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CLIENTES_GESTIONAR');
    PERFORM interno.sp_comun_exigir_texto(p_nombres, 'nombres');
    PERFORM interno.sp_comun_exigir_texto(p_apellidos, 'apellidos');
    PERFORM interno.sp_comun_exigir_texto(p_telefono, 'teléfono');
    PERFORM interno.sp_comun_exigir_texto(p_tipo_documento, 'tipo de documento');
    PERFORM interno.sp_comun_exigir_texto(p_numero_documento, 'número de documento');

    SELECT to_jsonb(c) INTO v_anterior FROM cliente c WHERE c.id_cliente = p_id_cliente FOR UPDATE;
    IF v_anterior IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'cliente_no_encontrado', 'Cliente no encontrado');
    END IF;

    UPDATE cliente c
       SET nombres = btrim(p_nombres), apellidos = btrim(p_apellidos), telefono = btrim(p_telefono),
           tipo_documento = lower(btrim(p_tipo_documento)), numero_documento = btrim(p_numero_documento),
           pais = COALESCE(NULLIF(btrim(p_pais), ''), c.pais)
     WHERE c.id_cliente = p_id_cliente;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'clientes', 'cliente',
        p_id_cliente::text, 'modificar', v_anterior,
        (SELECT to_jsonb(c) FROM cliente c WHERE c.id_cliente = p_id_cliente));
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'documento_registrado', 'Ya existe otro cliente con ese documento');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'Los datos no tienen un formato válido');
END;
$$;

CREATE OR REPLACE FUNCTION sp_clientes_actualizar_mi_perfil(
    p_id_usuario_actor  BIGINT,
    p_nombres           TEXT,
    p_apellidos         TEXT,
    p_telefono          TEXT,
    p_pais              TEXT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVAR');
    IF v_actor.id_cliente IS NULL THEN
        PERFORM interno.sp_comun_error('HH403', 'cliente_inactivo', 'Su cuenta de cliente no está activa');
    END IF;
    PERFORM interno.sp_comun_exigir_texto(p_nombres, 'nombres');
    PERFORM interno.sp_comun_exigir_texto(p_apellidos, 'apellidos');
    PERFORM interno.sp_comun_exigir_texto(p_telefono, 'teléfono');

    SELECT to_jsonb(c) INTO v_anterior FROM cliente c WHERE c.id_cliente = v_actor.id_cliente FOR UPDATE;

    UPDATE cliente c
       SET nombres = btrim(p_nombres), apellidos = btrim(p_apellidos), telefono = btrim(p_telefono),
           pais = COALESCE(NULLIF(btrim(p_pais), ''), c.pais)
     WHERE c.id_cliente = v_actor.id_cliente;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'clientes', 'cliente',
        v_actor.id_cliente::text, 'modificar', v_anterior,
        (SELECT to_jsonb(c) FROM cliente c WHERE c.id_cliente = v_actor.id_cliente));
END;
$$;

CREATE OR REPLACE FUNCTION sp_clientes_cambiar_activo(
    p_id_usuario_actor  BIGINT,
    p_id_cliente        BIGINT,
    p_activo            BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor       interno.tp_actor;
    v_actual      BOOLEAN;
    v_id_usuario  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CLIENTES_GESTIONAR');
    IF p_activo IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'campo_requerido', 'Indique si el cliente queda activo o no');
    END IF;

    SELECT c.activo, c.id_usuario INTO v_actual, v_id_usuario
      FROM cliente c WHERE c.id_cliente = p_id_cliente FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'cliente_no_encontrado', 'Cliente no encontrado');
    END IF;
    IF v_actual = p_activo THEN
        RETURN;
    END IF;

    IF NOT p_activo AND EXISTS (
        SELECT 1 FROM reservacion r
         WHERE r.id_cliente = p_id_cliente AND r.estado IN ('pendiente_pago', 'confirmada', 'en_curso')) THEN
        PERFORM interno.sp_comun_error('HH409', 'cliente_con_reservaciones',
            'El cliente tiene reservaciones activas; cancélelas o finalícelas primero');
    END IF;

    UPDATE cliente c SET activo = p_activo WHERE c.id_cliente = p_id_cliente;
    IF v_id_usuario IS NOT NULL THEN
        UPDATE usuario u SET activo = p_activo WHERE u.id_usuario = v_id_usuario;
        IF NOT p_activo THEN
            UPDATE token_refresco t SET revocado_en = now()
             WHERE t.id_usuario = v_id_usuario AND t.revocado_en IS NULL;
        END IF;
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'clientes', 'cliente',
        p_id_cliente::text, CASE WHEN p_activo THEN 'modificar' ELSE 'desactivar' END,
        jsonb_build_object('activo', v_actual), jsonb_build_object('activo', p_activo));
END;
$$;

CREATE OR REPLACE FUNCTION sp_clientes_obtener(p_id_usuario_actor BIGINT, p_id_cliente BIGINT)
RETURNS TABLE (
    id_cliente          BIGINT,
    nombres             VARCHAR,
    apellidos           VARCHAR,
    telefono            VARCHAR,
    tipo_documento      VARCHAR,
    numero_documento    VARCHAR,
    pais                VARCHAR,
    correo              CITEXT,
    tiene_contrasena    BOOLEAN,
    activo              BOOLEAN,
    creado_en           TIMESTAMPTZ,
    estancias           INTEGER,
    noches              INTEGER,
    total_pagado        DECIMAL(12,2),
    cancelaciones       INTEGER,
    no_presentaciones   INTEGER,
    ultima_estancia     DATE)
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
    IF NOT interno.sp_comun_tiene_permiso(v_actor, 'CLIENTES_GESTIONAR') THEN
        PERFORM interno.sp_comun_exigir_permiso(v_actor, 'RESERVAR');
        IF v_actor.id_cliente IS DISTINCT FROM p_id_cliente THEN
            PERFORM interno.sp_comun_error('HH404', 'cliente_no_encontrado', 'Cliente no encontrado');
        END IF;
    END IF;

    RETURN QUERY
    SELECT c.id_cliente, c.nombres, c.apellidos, c.telefono, c.tipo_documento, c.numero_documento, c.pais,
           u.correo, (u.contrasena_hash IS NOT NULL), c.activo, c.creado_en,
           e.estancias, e.noches, e.total_pagado, e.cancelaciones, e.no_presentaciones, e.ultima_estancia
      FROM cliente c
      LEFT JOIN usuario u ON u.id_usuario = c.id_usuario
     CROSS JOIN interno.sp_clientes_estadisticas(c.id_cliente) e
     WHERE c.id_cliente = p_id_cliente;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'cliente_no_encontrado', 'Cliente no encontrado');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION sp_clientes_listar(
    p_id_usuario_actor  BIGINT,
    p_busqueda          TEXT,
    p_activo            BOOLEAN,
    p_pagina            INTEGER,
    p_tamano            INTEGER,
    p_orden             TEXT,
    p_direccion         TEXT)
RETURNS TABLE (
    id_cliente          BIGINT,
    nombre              TEXT,
    telefono            VARCHAR,
    tipo_documento      VARCHAR,
    numero_documento    VARCHAR,
    correo              CITEXT,
    activo              BOOLEAN,
    estancias           INTEGER,
    total_pagado        DECIMAL(12,2),
    cancelaciones       INTEGER,
    no_presentaciones   INTEGER,
    total_registros     BIGINT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CLIENTES_GESTIONAR');
    PERFORM interno.sp_comun_validar_paginacion(p_pagina, p_tamano);
    PERFORM interno.sp_comun_validar_direccion(p_direccion);
    IF p_orden IS NULL OR p_orden NOT IN ('nombre', 'creado_en', 'estancias', 'total_pagado') THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_invalido',
            'Orden no válido: use nombre, creado_en, estancias o total_pagado');
    END IF;

    RETURN QUERY
    SELECT c.id_cliente, c.nombres || ' ' || c.apellidos, c.telefono, c.tipo_documento, c.numero_documento,
           u.correo, c.activo, e.estancias, e.total_pagado, e.cancelaciones, e.no_presentaciones,
           count(*) OVER ()
      FROM cliente c
      LEFT JOIN usuario u ON u.id_usuario = c.id_usuario
     CROSS JOIN LATERAL interno.sp_clientes_estadisticas(c.id_cliente) e
     WHERE (p_activo IS NULL OR c.activo = p_activo)
       AND (v_busqueda IS NULL
            OR (c.nombres || ' ' || c.apellidos) ILIKE '%' || v_busqueda || '%'
            OR c.telefono ILIKE '%' || v_busqueda || '%'
            OR u.correo ILIKE '%' || v_busqueda || '%'
            OR c.numero_documento = v_busqueda)
     ORDER BY
        CASE WHEN p_orden = 'nombre'       AND p_direccion = 'asc'  THEN c.apellidos || ' ' || c.nombres END ASC,
        CASE WHEN p_orden = 'nombre'       AND p_direccion = 'desc' THEN c.apellidos || ' ' || c.nombres END DESC,
        CASE WHEN p_orden = 'creado_en'    AND p_direccion = 'asc'  THEN c.creado_en END ASC,
        CASE WHEN p_orden = 'creado_en'    AND p_direccion = 'desc' THEN c.creado_en END DESC,
        CASE WHEN p_orden = 'estancias'    AND p_direccion = 'asc'  THEN e.estancias END ASC,
        CASE WHEN p_orden = 'estancias'    AND p_direccion = 'desc' THEN e.estancias END DESC,
        CASE WHEN p_orden = 'total_pagado' AND p_direccion = 'asc'  THEN e.total_pagado END ASC,
        CASE WHEN p_orden = 'total_pagado' AND p_direccion = 'desc' THEN e.total_pagado END DESC,
        c.id_cliente
     LIMIT p_tamano OFFSET (p_pagina - 1) * p_tamano;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_clientes_registrar_en_recepcion(BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT),
    sp_clientes_crear_cuenta(BIGINT, BIGINT, TEXT),
    sp_clientes_actualizar(BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT),
    sp_clientes_actualizar_mi_perfil(BIGINT, TEXT, TEXT, TEXT, TEXT),
    sp_clientes_cambiar_activo(BIGINT, BIGINT, BOOLEAN),
    sp_clientes_obtener(BIGINT, BIGINT),
    sp_clientes_listar(BIGINT, TEXT, BOOLEAN, INTEGER, INTEGER, TEXT, TEXT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('026_sp_clientes.sql');