-- =============================================================================
-- 031_sp_contenido_web.sql
-- Contenido editable de la página web (RN-12) e imágenes.
--
-- El contenido se organiza por página / sección / clave. id_hotel NULL es
-- contenido de la cadena (por ejemplo, la portada general); con hotel, es el
-- contenido de ese hotel. Tipos de valor (JSON):
--   texto        -> "cadena"  (hasta 300 caracteres)
--   texto_largo  -> "cadena"  (hasta 10 000 caracteres)
--   imagen       -> {"url": "...", "texto_alternativo": "..."}
--   lista        -> [ ... ]   (por ejemplo, servicios o preguntas frecuentes)
-- Las imágenes se suben desde la API a su almacenamiento; aquí solo se
-- guarda la URL (https://... o una ruta que empiece con /).
-- =============================================================================

CREATE OR REPLACE FUNCTION interno.sp_contenido_validar_url(p_url TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_url IS NULL OR NOT (btrim(p_url) ~ '^(https://[^\s]+|/[^\s]*)$') OR length(btrim(p_url)) > 500 THEN
        PERFORM interno.sp_comun_error('HH422', 'url_invalida',
            'La URL debe empezar con https:// o con / y no tener espacios');
    END IF;
    RETURN btrim(p_url);
END;
$$;

CREATE OR REPLACE FUNCTION interno.sp_contenido_hotel_por_slug(p_slug TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    IF p_slug IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT h.id_hotel INTO v_id FROM hotel h WHERE h.slug = lower(btrim(p_slug)) AND h.activo;
    IF v_id IS NULL THEN
        PERFORM interno.sp_comun_error('HH404', 'hotel_no_encontrado', 'Hotel no encontrado');
    END IF;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION sp_hoteles_obtener_publico(p_slug TEXT)
RETURNS TABLE (
    id_hotel   BIGINT,
    nombre     VARCHAR,
    slug       VARCHAR,
    direccion  VARCHAR,
    ciudad     VARCHAR,
    telefono   VARCHAR,
    correo     CITEXT,
    hora_checkout  TIME,
    carrusel   JSONB,
    galeria    JSONB)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_id BIGINT;
BEGIN
    v_id := interno.sp_contenido_hotel_por_slug(p_slug);
    IF v_id IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'slug_requerido', 'Indique el hotel');
    END IF;

    RETURN QUERY
    SELECT h.id_hotel, h.nombre, h.slug, h.direccion, h.ciudad, h.telefono, h.correo, hc.hora_checkout,
           COALESCE((SELECT jsonb_agg(jsonb_build_object('url', i.url, 'texto_alternativo', i.texto_alternativo)
                                      ORDER BY i.orden, i.id_hotel_imagen)
                       FROM hotel_imagen i WHERE i.id_hotel = h.id_hotel AND i.activo AND i.seccion = 'carrusel'), '[]'),
           COALESCE((SELECT jsonb_agg(jsonb_build_object('url', i.url, 'texto_alternativo', i.texto_alternativo)
                                      ORDER BY i.orden, i.id_hotel_imagen)
                       FROM hotel_imagen i WHERE i.id_hotel = h.id_hotel AND i.activo AND i.seccion = 'galeria'), '[]')
      FROM hotel h
      JOIN hotel_configuracion hc ON hc.id_hotel = h.id_hotel
     WHERE h.id_hotel = v_id;
END;
$$;
CREATE OR REPLACE FUNCTION sp_contenido_obtener_publico(p_slug TEXT, p_pagina TEXT)
RETURNS TABLE (seccion VARCHAR, clave VARCHAR, tipo VARCHAR, valor JSONB, orden INTEGER, de_hotel BOOLEAN)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_id_hotel BIGINT;
BEGIN
    PERFORM interno.sp_comun_exigir_texto(p_pagina, 'página');
    v_id_hotel := interno.sp_contenido_hotel_por_slug(p_slug);

    RETURN QUERY
    SELECT DISTINCT ON (c.seccion, c.clave) c.seccion, c.clave, c.tipo, c.valor, c.orden, (c.id_hotel IS NOT NULL)
      FROM contenido_web c
     WHERE c.pagina = lower(btrim(p_pagina))
       AND c.publicado
       AND (c.id_hotel IS NULL OR c.id_hotel = v_id_hotel)
     ORDER BY c.seccion, c.clave, (c.id_hotel IS NULL);
END;
$$;

CREATE OR REPLACE FUNCTION sp_contenido_guardar(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_pagina            TEXT,
    p_seccion           TEXT,
    p_clave             TEXT,
    p_tipo              TEXT,
    p_valor             JSONB,
    p_orden             INTEGER,
    p_publicado         BOOLEAN)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_anterior  JSONB;
    v_id        BIGINT;
    v_limite    INTEGER;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR');
    IF p_id_hotel IS NULL THEN
        IF v_actor.rol <> 'administrador' THEN
            PERFORM interno.sp_comun_error('HH403', 'contenido_de_cadena', 'Solo el administrador edita el contenido de la cadena');
        END IF;
    ELSE
        PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    END IF;
    PERFORM interno.sp_comun_exigir_texto(p_pagina, 'página');
    PERFORM interno.sp_comun_exigir_texto(p_seccion, 'sección');
    PERFORM interno.sp_comun_exigir_texto(p_clave, 'clave');
    IF NOT (lower(btrim(p_pagina)) ~ '^[a-z0-9_-]{1,60}$' AND lower(btrim(p_seccion)) ~ '^[a-z0-9_-]{1,60}$'
            AND lower(btrim(p_clave)) ~ '^[a-z0-9_-]{1,60}$') THEN
        PERFORM interno.sp_comun_error('HH422', 'identificador_invalido',
            'Página, sección y clave solo admiten minúsculas, números, guion y guion bajo');
    END IF;

    IF p_tipo IS NULL OR p_tipo NOT IN ('texto', 'texto_largo', 'imagen', 'lista') OR p_valor IS NULL THEN
        PERFORM interno.sp_comun_error('HH422', 'tipo_invalido', 'El tipo debe ser texto, texto_largo, imagen o lista, con su valor');
    END IF;
    IF p_tipo IN ('texto', 'texto_largo') THEN
        IF jsonb_typeof(p_valor) <> 'string' THEN
            PERFORM interno.sp_comun_error('HH422', 'valor_invalido', 'El valor de un texto debe ser una cadena');
        END IF;
        v_limite := CASE p_tipo WHEN 'texto' THEN 300 ELSE 10000 END;
        IF length(p_valor #>> '{}') > v_limite THEN
            PERFORM interno.sp_comun_error('HH422', 'texto_muy_largo', format('El texto supera %s caracteres', v_limite));
        END IF;
    ELSIF p_tipo = 'imagen' THEN
        IF jsonb_typeof(p_valor) <> 'object' OR NOT (p_valor ? 'url') THEN
            PERFORM interno.sp_comun_error('HH422', 'valor_invalido', 'Una imagen necesita {"url": ...}');
        END IF;
        PERFORM interno.sp_contenido_validar_url(p_valor ->> 'url');
    ELSIF jsonb_typeof(p_valor) <> 'array' THEN
        PERFORM interno.sp_comun_error('HH422', 'valor_invalido', 'El valor de una lista debe ser un arreglo');
    END IF;

    SELECT to_jsonb(c) INTO v_anterior FROM contenido_web c
     WHERE c.id_hotel IS NOT DISTINCT FROM p_id_hotel AND c.pagina = lower(btrim(p_pagina))
       AND c.seccion = lower(btrim(p_seccion)) AND c.clave = lower(btrim(p_clave))
       FOR UPDATE;

    INSERT INTO contenido_web (id_hotel, pagina, seccion, clave, tipo, valor, orden, publicado, actualizado_por)
    VALUES (p_id_hotel, lower(btrim(p_pagina)), lower(btrim(p_seccion)), lower(btrim(p_clave)), p_tipo, p_valor,
            COALESCE(p_orden, 0), COALESCE(p_publicado, TRUE), p_id_usuario_actor)
    ON CONFLICT ON CONSTRAINT uq_contenido_web
    DO UPDATE SET tipo = EXCLUDED.tipo, valor = EXCLUDED.valor, orden = EXCLUDED.orden,
                  publicado = EXCLUDED.publicado, actualizado_por = EXCLUDED.actualizado_por
    RETURNING id_contenido_web INTO v_id;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'contenido_web', 'contenido_web',
        v_id::text, CASE WHEN v_anterior IS NULL THEN 'crear' ELSE 'modificar' END, v_anterior,
        (SELECT to_jsonb(c) FROM contenido_web c WHERE c.id_contenido_web = v_id));
    RETURN v_id;
EXCEPTION
    WHEN check_violation THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_invalido', 'El orden no puede ser negativo');
END;
$$;

CREATE OR REPLACE FUNCTION sp_contenido_cambiar_publicado(
    p_id_usuario_actor  BIGINT,
    p_id_contenido_web  BIGINT,
    p_publicado         BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  interno.tp_actor;
    v_c      contenido_web%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR');
    SELECT c.* INTO v_c FROM contenido_web c WHERE c.id_contenido_web = p_id_contenido_web FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'contenido_no_encontrado', 'Contenido no encontrado');
    END IF;
    IF v_c.id_hotel IS NULL THEN
        IF v_actor.rol <> 'administrador' THEN
            PERFORM interno.sp_comun_error('HH403', 'contenido_de_cadena', 'Solo el administrador edita el contenido de la cadena');
        END IF;
    ELSE
        PERFORM interno.sp_comun_exigir_hotel(v_actor, v_c.id_hotel);
    END IF;
    IF p_publicado IS NULL OR v_c.publicado = p_publicado THEN
        RETURN;
    END IF;

    UPDATE contenido_web c SET publicado = p_publicado, actualizado_por = p_id_usuario_actor
     WHERE c.id_contenido_web = p_id_contenido_web;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_c.id_hotel, 'contenido_web', 'contenido_web',
        p_id_contenido_web::text, 'modificar', jsonb_build_object('publicado', v_c.publicado),
        jsonb_build_object('publicado', p_publicado));
END;
$$;

CREATE OR REPLACE FUNCTION sp_contenido_listar(p_id_usuario_actor BIGINT, p_id_hotel BIGINT, p_pagina TEXT)
RETURNS TABLE (
    id_contenido_web  BIGINT,
    pagina            VARCHAR,
    seccion           VARCHAR,
    clave             VARCHAR,
    tipo              VARCHAR,
    valor             JSONB,
    orden             INTEGER,
    publicado         BOOLEAN,
    actualizado_por   CITEXT,
    actualizado_en    TIMESTAMPTZ)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR');
    IF p_id_hotel IS NOT NULL THEN
        PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    END IF;

    RETURN QUERY
    SELECT c.id_contenido_web, c.pagina, c.seccion, c.clave, c.tipo, c.valor, c.orden, c.publicado,
           u.correo, c.actualizado_en
      FROM contenido_web c
      JOIN usuario u ON u.id_usuario = c.actualizado_por
     WHERE c.id_hotel IS NOT DISTINCT FROM p_id_hotel
       AND (p_pagina IS NULL OR c.pagina = lower(btrim(p_pagina)))
     ORDER BY c.pagina, c.seccion, c.orden, c.clave;
END;
$$;


CREATE OR REPLACE FUNCTION sp_hoteles_agregar_imagen(
    p_id_usuario_actor   BIGINT,
    p_id_hotel           BIGINT,
    p_url                TEXT,
    p_texto_alternativo  TEXT,
    p_seccion            TEXT)
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);
    PERFORM interno.sp_comun_exigir_texto(p_texto_alternativo, 'texto alternativo');
    IF p_seccion IS NULL OR p_seccion NOT IN ('carrusel', 'galeria') THEN
        PERFORM interno.sp_comun_error('HH422', 'seccion_invalida', 'La sección debe ser carrusel o galeria');
    END IF;

    INSERT INTO hotel_imagen (id_hotel, url, texto_alternativo, seccion, orden)
    VALUES (p_id_hotel, interno.sp_contenido_validar_url(p_url), btrim(p_texto_alternativo), p_seccion,
            (SELECT COALESCE(max(i.orden) + 1, 0) FROM hotel_imagen i
              WHERE i.id_hotel = p_id_hotel AND i.seccion = p_seccion AND i.activo))
    RETURNING id_hotel_imagen INTO v_id;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'contenido_web', 'hotel_imagen',
        v_id::text, 'crear', NULL, jsonb_build_object('url', p_url, 'seccion', p_seccion));
    RETURN v_id;
EXCEPTION
    WHEN foreign_key_violation THEN
        PERFORM interno.sp_comun_error('HH404', 'hotel_no_encontrado', 'Hotel no encontrado');
END;
$$;

CREATE OR REPLACE FUNCTION sp_hoteles_quitar_imagen(p_id_usuario_actor BIGINT, p_id_hotel_imagen BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  interno.tp_actor;
    v_img    hotel_imagen%ROWTYPE;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR');
    SELECT i.* INTO v_img FROM hotel_imagen i WHERE i.id_hotel_imagen = p_id_hotel_imagen FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'imagen_no_encontrada', 'Imagen no encontrada');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_img.id_hotel);
    IF NOT v_img.activo THEN
        RETURN;
    END IF;

    UPDATE hotel_imagen i SET activo = FALSE WHERE i.id_hotel_imagen = p_id_hotel_imagen;
    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_img.id_hotel, 'contenido_web', 'hotel_imagen',
        p_id_hotel_imagen::text, 'desactivar', to_jsonb(v_img), jsonb_build_object('activo', false));
END;
$$;

CREATE OR REPLACE FUNCTION sp_hoteles_ordenar_imagenes(
    p_id_usuario_actor  BIGINT,
    p_id_hotel          BIGINT,
    p_seccion           TEXT,
    p_ids               BIGINT[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor  interno.tp_actor;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR');
    PERFORM interno.sp_comun_exigir_hotel(v_actor, p_id_hotel);

    PERFORM 1 FROM hotel_imagen i WHERE i.id_hotel = p_id_hotel AND i.seccion = p_seccion AND i.activo FOR UPDATE;
    IF cardinality(COALESCE(p_ids, '{}')) <> (SELECT count(DISTINCT x) FROM unnest(p_ids) x)
       OR ARRAY(SELECT x FROM unnest(p_ids) x ORDER BY x) IS DISTINCT FROM
          ARRAY(SELECT i.id_hotel_imagen FROM hotel_imagen i
                 WHERE i.id_hotel = p_id_hotel AND i.seccion = p_seccion AND i.activo ORDER BY 1) THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_incompleto',
            'Envíe todas las imágenes activas de la sección, cada una una vez');
    END IF;

    UPDATE hotel_imagen i SET orden = o.pos - 1
      FROM unnest(p_ids) WITH ORDINALITY AS o(id, pos)
     WHERE i.id_hotel_imagen = o.id;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, p_id_hotel, 'contenido_web', 'hotel_imagen',
        p_id_hotel::text, 'modificar', jsonb_build_object('seccion', p_seccion),
        jsonb_build_object('seccion', p_seccion, 'orden', to_jsonb(p_ids)));
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_agregar_imagen(
    p_id_usuario_actor    BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_url                 TEXT,
    p_texto_alternativo   TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_id_hotel  BIGINT;
    v_id        BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR', 'HABITACIONES_GESTIONAR');
    SELECT th.id_hotel INTO v_id_hotel FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'tipo_no_encontrado', 'Tipo de habitación no encontrado');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);
    PERFORM interno.sp_comun_exigir_texto(p_texto_alternativo, 'texto alternativo');

    INSERT INTO tipo_habitacion_imagen (id_tipo_habitacion, url, texto_alternativo, orden)
    VALUES (p_id_tipo_habitacion, interno.sp_contenido_validar_url(p_url), btrim(p_texto_alternativo),
            (SELECT COALESCE(max(i.orden) + 1, 0) FROM tipo_habitacion_imagen i
              WHERE i.id_tipo_habitacion = p_id_tipo_habitacion))
    RETURNING id_tipo_habitacion_imagen INTO v_id;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'contenido_web', 'tipo_habitacion_imagen',
        v_id::text, 'crear', NULL, jsonb_build_object('id_tipo_habitacion', p_id_tipo_habitacion, 'url', p_url));
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_quitar_imagen(p_id_usuario_actor BIGINT, p_id_tipo_habitacion_imagen BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_img       tipo_habitacion_imagen%ROWTYPE;
    v_id_hotel  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR', 'HABITACIONES_GESTIONAR');
    SELECT i.* INTO v_img FROM tipo_habitacion_imagen i WHERE i.id_tipo_habitacion_imagen = p_id_tipo_habitacion_imagen;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'imagen_no_encontrada', 'Imagen no encontrada');
    END IF;
    SELECT th.id_hotel INTO v_id_hotel FROM tipo_habitacion th WHERE th.id_tipo_habitacion = v_img.id_tipo_habitacion;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);

    DELETE FROM tipo_habitacion_imagen i WHERE i.id_tipo_habitacion_imagen = p_id_tipo_habitacion_imagen;
    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, v_id_hotel, 'contenido_web', 'tipo_habitacion_imagen',
        p_id_tipo_habitacion_imagen::text, 'desactivar', to_jsonb(v_img), jsonb_build_object('eliminada', true));
END;
$$;

CREATE OR REPLACE FUNCTION sp_habitaciones_ordenar_imagenes(
    p_id_usuario_actor    BIGINT,
    p_id_tipo_habitacion  BIGINT,
    p_ids                 BIGINT[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor     interno.tp_actor;
    v_id_hotel  BIGINT;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CONTENIDO_WEB_GESTIONAR', 'HABITACIONES_GESTIONAR');
    SELECT th.id_hotel INTO v_id_hotel FROM tipo_habitacion th WHERE th.id_tipo_habitacion = p_id_tipo_habitacion;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'tipo_no_encontrado', 'Tipo de habitación no encontrado');
    END IF;
    PERFORM interno.sp_comun_exigir_hotel(v_actor, v_id_hotel);

    PERFORM 1 FROM tipo_habitacion_imagen i WHERE i.id_tipo_habitacion = p_id_tipo_habitacion FOR UPDATE;
    IF cardinality(COALESCE(p_ids, '{}')) <> (SELECT count(DISTINCT x) FROM unnest(p_ids) x)
       OR ARRAY(SELECT x FROM unnest(p_ids) x ORDER BY x) IS DISTINCT FROM
          ARRAY(SELECT i.id_tipo_habitacion_imagen FROM tipo_habitacion_imagen i
                 WHERE i.id_tipo_habitacion = p_id_tipo_habitacion ORDER BY 1) THEN
        PERFORM interno.sp_comun_error('HH422', 'orden_incompleto', 'Envíe todas las imágenes del tipo, cada una una vez');
    END IF;

    UPDATE tipo_habitacion_imagen i SET orden = o.pos - 1
      FROM unnest(p_ids) WITH ORDINALITY AS o(id, pos)
     WHERE i.id_tipo_habitacion_imagen = o.id;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_hoteles_obtener_publico(TEXT),
    sp_contenido_obtener_publico(TEXT, TEXT),
    sp_contenido_guardar(BIGINT, BIGINT, TEXT, TEXT, TEXT, TEXT, JSONB, INTEGER, BOOLEAN),
    sp_contenido_cambiar_publicado(BIGINT, BIGINT, BOOLEAN),
    sp_contenido_listar(BIGINT, BIGINT, TEXT),
    sp_hoteles_agregar_imagen(BIGINT, BIGINT, TEXT, TEXT, TEXT),
    sp_hoteles_quitar_imagen(BIGINT, BIGINT),
    sp_hoteles_ordenar_imagenes(BIGINT, BIGINT, TEXT, BIGINT[]),
    sp_habitaciones_agregar_imagen(BIGINT, BIGINT, TEXT, TEXT),
    sp_habitaciones_quitar_imagen(BIGINT, BIGINT),
    sp_habitaciones_ordenar_imagenes(BIGINT, BIGINT, BIGINT[])
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('031_sp_contenido_web.sql');