-- =============================================================================
-- 021_sp_seguridad.sql
-- Registro de clientes, inicio de sesión, refresh tokens y perfil (RN-01).
--
-- Las contraseñas se verifican en la API (Argon2id): la base de datos solo
-- recibe y guarda el hash. Flujo de inicio de sesión:
--   1. sp_seguridad_obtener_credenciales(correo)
--   2. La API revisa activo / bloqueado_hasta y verifica el hash.
--   3. sp_seguridad_registrar_intento_login(id_usuario, exitoso)
--   4. Si fue exitoso: sp_seguridad_crear_token_refresco(...)
-- =============================================================================

CREATE OR REPLACE FUNCTION sp_seguridad_registrar_cliente(
    p_correo            TEXT,
    p_contrasena_hash   TEXT,
    p_nombres           TEXT,
    p_apellidos         TEXT,
    p_telefono          TEXT,
    p_tipo_documento    TEXT,
    p_numero_documento  TEXT,
    p_pais              TEXT)
RETURNS TABLE (id_usuario BIGINT, id_cliente BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_id_usuario  BIGINT;
    v_id_cliente  BIGINT;
    v_restriccion TEXT;
BEGIN
    PERFORM interno.sp_comun_exigir_texto(p_correo, 'correo');
    PERFORM interno.sp_comun_exigir_texto(p_contrasena_hash, 'contraseña');
    PERFORM interno.sp_comun_exigir_texto(p_nombres, 'nombres');
    PERFORM interno.sp_comun_exigir_texto(p_apellidos, 'apellidos');
    PERFORM interno.sp_comun_exigir_texto(p_telefono, 'teléfono');
    PERFORM interno.sp_comun_exigir_texto(p_tipo_documento, 'tipo de documento');
    PERFORM interno.sp_comun_exigir_texto(p_numero_documento, 'número de documento');

    IF EXISTS (SELECT 1 FROM usuario u WHERE u.correo = btrim(p_correo)::citext) THEN
        PERFORM interno.sp_comun_error('HH409', 'correo_registrado', 'Ya existe una cuenta con ese correo');
    END IF;

    IF EXISTS (SELECT 1 FROM cliente c
                WHERE c.tipo_documento = lower(btrim(p_tipo_documento))
                  AND c.numero_documento = btrim(p_numero_documento)) THEN
        PERFORM interno.sp_comun_error('HH409', 'documento_registrado',
            'Ya existe un cliente con ese documento. Acérquese a recepción para vincular su cuenta');
    END IF;

    INSERT INTO usuario (correo, contrasena_hash, id_rol)
    VALUES (lower(btrim(p_correo)), p_contrasena_hash,
            (SELECT r.id_rol FROM rol r WHERE r.nombre = 'cliente'))
    RETURNING usuario.id_usuario INTO v_id_usuario;

    INSERT INTO cliente (id_usuario, nombres, apellidos, telefono, tipo_documento, numero_documento, pais)
    VALUES (v_id_usuario, btrim(p_nombres), btrim(p_apellidos), btrim(p_telefono),
            lower(btrim(p_tipo_documento)), btrim(p_numero_documento),
            COALESCE(NULLIF(btrim(p_pais), ''), 'Guatemala'))
    RETURNING cliente.id_cliente INTO v_id_cliente;

    RETURN QUERY SELECT v_id_usuario, v_id_cliente;
EXCEPTION
    WHEN unique_violation THEN
        PERFORM interno.sp_comun_error('HH409', 'registro_duplicado', 'El correo o el documento ya están registrados');
    WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_restriccion = CONSTRAINT_NAME;
        PERFORM interno.sp_comun_error('HH422', v_restriccion, 'Los datos no tienen un formato válido');
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_obtener_credenciales(p_correo TEXT)
RETURNS TABLE (
    id_usuario       BIGINT,
    contrasena_hash  VARCHAR,
    rol              VARCHAR,
    activo           BOOLEAN,
    bloqueado_hasta  TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.id_usuario, u.contrasena_hash, r.nombre, u.activo, u.bloqueado_hasta
      FROM usuario u
      JOIN rol r ON r.id_rol = u.id_rol
     WHERE u.correo = btrim(p_correo)::citext;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_registrar_intento_login(p_id_usuario BIGINT, p_exitoso BOOLEAN)
RETURNS TABLE (bloqueado_hasta TIMESTAMPTZ, intentos_restantes INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    c_max_intentos CONSTANT INTEGER  := 5;
    c_bloqueo      CONSTANT INTERVAL := interval '15 minutes';
    v_usuario      usuario%ROWTYPE;
    v_intentos     INTEGER;
BEGIN
    SELECT * INTO v_usuario FROM usuario u WHERE u.id_usuario = p_id_usuario FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'usuario_no_encontrado', 'Usuario no encontrado');
    END IF;

    IF v_usuario.bloqueado_hasta IS NOT NULL AND v_usuario.bloqueado_hasta > now() THEN
        RETURN QUERY SELECT v_usuario.bloqueado_hasta, 0;
        RETURN;
    END IF;

    IF p_exitoso THEN
        UPDATE usuario u
           SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso_en = now()
         WHERE u.id_usuario = p_id_usuario;
        RETURN QUERY SELECT NULL::timestamptz, c_max_intentos;
        RETURN;
    END IF;

    v_intentos := v_usuario.intentos_fallidos + 1;
    IF v_intentos >= c_max_intentos THEN
        UPDATE usuario u
           SET intentos_fallidos = 0, bloqueado_hasta = now() + c_bloqueo
         WHERE u.id_usuario = p_id_usuario;
        RETURN QUERY SELECT now() + c_bloqueo, 0;
    ELSE
        UPDATE usuario u SET intentos_fallidos = v_intentos WHERE u.id_usuario = p_id_usuario;
        RETURN QUERY SELECT NULL::timestamptz, c_max_intentos - v_intentos;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_crear_token_refresco(
    p_id_usuario      BIGINT,
    p_token_hash      TEXT,
    p_id_familia      UUID,
    p_expira_en       TIMESTAMPTZ,
    p_direccion_ip    INET,
    p_agente_usuario  TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM interno.sp_comun_obtener_actor(p_id_usuario);
    INSERT INTO token_refresco (id_usuario, token_hash, id_familia, expira_en, direccion_ip, agente_usuario)
    VALUES (p_id_usuario, p_token_hash, p_id_familia, p_expira_en, p_direccion_ip, left(p_agente_usuario, 300));
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_rotar_token_refresco(
    p_token_hash_actual  TEXT,
    p_token_hash_nuevo   TEXT,
    p_expira_en          TIMESTAMPTZ,
    p_direccion_ip       INET,
    p_agente_usuario     TEXT)
RETURNS TABLE (resultado TEXT, id_usuario BIGINT, rol VARCHAR, id_familia UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_token   token_refresco%ROWTYPE;
    v_activo  BOOLEAN;
    v_rol     VARCHAR;
BEGIN
    SELECT * INTO v_token FROM token_refresco t WHERE t.token_hash = p_token_hash_actual FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'invalido'::text, NULL::bigint, NULL::varchar, NULL::uuid;
        RETURN;
    END IF;

    IF v_token.usado_en IS NOT NULL THEN
        UPDATE token_refresco t SET revocado_en = now()
         WHERE t.id_usuario = v_token.id_usuario AND t.revocado_en IS NULL;
        RETURN QUERY SELECT 'reutilizado'::text, v_token.id_usuario, NULL::varchar, NULL::uuid;
        RETURN;
    END IF;

    IF v_token.revocado_en IS NOT NULL OR v_token.expira_en <= now() THEN
        RETURN QUERY SELECT 'invalido'::text, NULL::bigint, NULL::varchar, NULL::uuid;
        RETURN;
    END IF;

    SELECT u.activo, r.nombre INTO v_activo, v_rol
      FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
     WHERE u.id_usuario = v_token.id_usuario;

    IF NOT v_activo THEN
        UPDATE token_refresco t SET revocado_en = now()
         WHERE t.id_familia = v_token.id_familia AND t.revocado_en IS NULL;
        RETURN QUERY SELECT 'invalido'::text, NULL::bigint, NULL::varchar, NULL::uuid;
        RETURN;
    END IF;

    UPDATE token_refresco t SET usado_en = now() WHERE t.id_token_refresco = v_token.id_token_refresco;

    INSERT INTO token_refresco (id_usuario, token_hash, id_familia, expira_en, direccion_ip, agente_usuario)
    VALUES (v_token.id_usuario, p_token_hash_nuevo, v_token.id_familia, p_expira_en,
            p_direccion_ip, left(p_agente_usuario, 300));

    RETURN QUERY SELECT 'valido'::text, v_token.id_usuario, v_rol, v_token.id_familia;
END;
$$;
CREATE OR REPLACE FUNCTION sp_seguridad_cerrar_sesion(p_token_hash TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE token_refresco t SET revocado_en = now()
     WHERE t.revocado_en IS NULL
       AND t.id_familia = (SELECT t2.id_familia FROM token_refresco t2 WHERE t2.token_hash = p_token_hash);
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_cerrar_todas_sesiones(p_id_usuario BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE token_refresco t SET revocado_en = now()
     WHERE t.id_usuario = p_id_usuario AND t.revocado_en IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_obtener_perfil(p_id_usuario BIGINT)
RETURNS TABLE (
    id_usuario   BIGINT,
    correo       CITEXT,
    rol          VARCHAR,
    id_cliente   BIGINT,
    id_empleado  BIGINT,
    nombres      VARCHAR,
    apellidos    VARCHAR,
    telefono     VARCHAR,
    hoteles      BIGINT[],
    permisos     TEXT[])
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor interno.tp_actor;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario);

    RETURN QUERY
    SELECT u.id_usuario, u.correo, v_actor.rol, c.id_cliente, e.id_empleado,
           COALESCE(c.nombres, e.nombres), COALESCE(c.apellidos, e.apellidos),
           COALESCE(c.telefono, e.telefono),
           CASE
               WHEN v_actor.rol = 'administrador' THEN
                   (SELECT array_agg(h.id_hotel ORDER BY h.id_hotel) FROM hotel h WHERE h.activo)
               WHEN e.id_empleado IS NOT NULL THEN
                   (SELECT array_agg(eh.id_hotel ORDER BY eh.id_hotel)
                      FROM empleado_hotel eh WHERE eh.id_empleado = e.id_empleado AND eh.activo)
           END,
           v_actor.permisos
      FROM usuario u
      LEFT JOIN cliente c ON c.id_usuario = u.id_usuario
      LEFT JOIN empleado e ON e.id_usuario = u.id_usuario
     WHERE u.id_usuario = p_id_usuario;
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_cambiar_contrasena(p_id_usuario BIGINT, p_contrasena_hash_nueva TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM interno.sp_comun_obtener_actor(p_id_usuario);
    PERFORM interno.sp_comun_exigir_texto(p_contrasena_hash_nueva, 'contraseña');

    UPDATE usuario u SET contrasena_hash = p_contrasena_hash_nueva WHERE u.id_usuario = p_id_usuario;
    PERFORM sp_seguridad_cerrar_todas_sesiones(p_id_usuario);
    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario, NULL, 'usuarios', 'usuario', p_id_usuario::text,
        'modificar', '{"contrasena": "anterior"}'::jsonb, '{"contrasena": "cambiada"}'::jsonb);
END;
$$;
CREATE OR REPLACE FUNCTION sp_seguridad_cambiar_estado_usuario(
    p_id_usuario_actor  BIGINT,
    p_id_usuario        BIGINT,
    p_activo            BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actor   interno.tp_actor;
    v_actual  BOOLEAN;
    v_rol     VARCHAR;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'USUARIOS_GESTIONAR');

    IF p_id_usuario = p_id_usuario_actor THEN
        PERFORM interno.sp_comun_error('HH409', 'no_desactivarse_a_si_mismo', 'No puede cambiar el estado de su propio usuario');
    END IF;

    SELECT u.activo, r.nombre INTO v_actual, v_rol
      FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
     WHERE u.id_usuario = p_id_usuario
       FOR UPDATE OF u;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'usuario_no_encontrado', 'Usuario no encontrado');
    END IF;
    IF v_actual = p_activo THEN
        RETURN;
    END IF;

    IF NOT p_activo AND v_rol = 'administrador' THEN
        PERFORM 1 FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
         WHERE r.nombre = 'administrador' AND u.activo
           FOR UPDATE OF u;
        IF NOT EXISTS (SELECT 1 FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
                        WHERE r.nombre = 'administrador' AND u.activo AND u.id_usuario <> p_id_usuario) THEN
            PERFORM interno.sp_comun_error('HH409', 'ultimo_administrador',
                'No se puede desactivar al último administrador activo');
        END IF;
    END IF;

    UPDATE usuario u SET activo = p_activo, intentos_fallidos = 0, bloqueado_hasta = NULL
     WHERE u.id_usuario = p_id_usuario;
    IF NOT p_activo THEN
        PERFORM sp_seguridad_cerrar_todas_sesiones(p_id_usuario);
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'usuarios', 'usuario', p_id_usuario::text,
        CASE WHEN p_activo THEN 'modificar' ELSE 'desactivar' END,
        jsonb_build_object('activo', v_actual), jsonb_build_object('activo', p_activo));
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_crear_administrador_semilla(p_correo TEXT, p_contrasena_hash TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id_usuario  BIGINT;
    v_rol         VARCHAR;
    v_activo      BOOLEAN;
BEGIN
    PERFORM interno.sp_comun_exigir_texto(p_correo, 'correo');
    PERFORM interno.sp_comun_exigir_texto(p_contrasena_hash, 'contraseña');

    SELECT u.id_usuario, r.nombre, u.activo INTO v_id_usuario, v_rol, v_activo
      FROM usuario u JOIN rol r ON r.id_rol = u.id_rol
     WHERE u.correo = btrim(p_correo)::citext;

    IF FOUND THEN
        IF v_rol <> 'administrador' THEN
            PERFORM interno.sp_comun_error('HH409', 'correo_de_otro_rol',
                'El correo del administrador semilla ya pertenece a un usuario con otro rol');
        END IF;
        IF NOT v_activo THEN
            PERFORM interno.sp_comun_error('HH409', 'administrador_inactivo',
                'El administrador semilla existe pero está desactivado; revíselo manualmente');
        END IF;
        RETURN v_id_usuario;
    END IF;

    INSERT INTO usuario (correo, contrasena_hash, id_rol)
    VALUES (lower(btrim(p_correo)), p_contrasena_hash,
            (SELECT r.id_rol FROM rol r WHERE r.nombre = 'administrador'))
    RETURNING id_usuario INTO v_id_usuario;

    PERFORM interno.sp_comun_registrar_bitacora(v_id_usuario, NULL, 'usuarios', 'usuario', v_id_usuario::text,
        'crear', NULL, jsonb_build_object('correo', lower(btrim(p_correo)), 'rol', 'administrador'));
    RETURN v_id_usuario;
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_listar_roles(p_id_usuario_actor BIGINT)
RETURNS TABLE (id_rol SMALLINT, nombre VARCHAR, descripcion VARCHAR, permisos TEXT[])
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
    PERFORM interno.sp_comun_exigir_permiso(v_actor, 'USUARIOS_GESTIONAR', 'EMPLEADOS_GESTIONAR');

    RETURN QUERY
    SELECT r.id_rol, r.nombre, r.descripcion,
           ARRAY(SELECT p.codigo::text FROM rol_permiso rp JOIN permiso p ON p.id_permiso = rp.id_permiso
                  WHERE rp.id_rol = r.id_rol ORDER BY p.codigo)
      FROM rol r
     ORDER BY r.id_rol;
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_establecer_contrasena_inicial(p_correo TEXT, p_contrasena_hash TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id_usuario BIGINT;
BEGIN
    PERFORM interno.sp_comun_exigir_texto(p_correo, 'correo');
    PERFORM interno.sp_comun_exigir_texto(p_contrasena_hash, 'contraseña');

    UPDATE usuario u SET contrasena_hash = p_contrasena_hash
     WHERE u.correo = btrim(p_correo)::citext AND u.contrasena_hash IS NULL AND u.activo
    RETURNING u.id_usuario INTO v_id_usuario;
    IF v_id_usuario IS NULL THEN
        RETURN FALSE;
    END IF;

    PERFORM interno.sp_comun_registrar_bitacora(v_id_usuario, NULL, 'usuarios', 'usuario', v_id_usuario::text,
        'modificar', '{"contrasena": "sin definir"}'::jsonb, '{"contrasena": "definida"}'::jsonb);
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_seguridad_registrar_cliente(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT),
    sp_seguridad_obtener_credenciales(TEXT),
    sp_seguridad_registrar_intento_login(BIGINT, BOOLEAN),
    sp_seguridad_crear_token_refresco(BIGINT, TEXT, UUID, TIMESTAMPTZ, INET, TEXT),
    sp_seguridad_rotar_token_refresco(TEXT, TEXT, TIMESTAMPTZ, INET, TEXT),
    sp_seguridad_cerrar_sesion(TEXT),
    sp_seguridad_cerrar_todas_sesiones(BIGINT),
    sp_seguridad_obtener_perfil(BIGINT),
    sp_seguridad_cambiar_contrasena(BIGINT, TEXT),
    sp_seguridad_cambiar_estado_usuario(BIGINT, BIGINT, BOOLEAN),
    sp_seguridad_crear_administrador_semilla(TEXT, TEXT),
    sp_seguridad_listar_roles(BIGINT),
    sp_seguridad_establecer_contrasena_inicial(TEXT, TEXT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('021_sp_seguridad.sql');