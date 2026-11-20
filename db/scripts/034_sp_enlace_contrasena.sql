-- Enlaces de un solo uso para definir (o, cuando haya correo, recuperar) la contraseña.
-- La API genera el token aleatorio y solo envía su hash SHA-256; la base nunca ve el token.

CREATE OR REPLACE FUNCTION sp_seguridad_generar_enlace_contrasena(
    p_id_usuario_actor  BIGINT,
    p_id_usuario        BIGINT,
    p_token_hash        TEXT,
    p_horas_vigencia    INTEGER DEFAULT 24)
RETURNS TABLE (id_enlace_contrasena BIGINT, correo CITEXT, expira_en TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_actor        interno.tp_actor;
    v_usuario      usuario%ROWTYPE;
    v_rol          VARCHAR;
    v_id_empleado  BIGINT;
    v_id           BIGINT;
    v_expira       TIMESTAMPTZ;
BEGIN
    v_actor := interno.sp_comun_obtener_actor(p_id_usuario_actor);
    PERFORM interno.sp_comun_exigir_texto(p_token_hash, 'token');
    IF p_horas_vigencia IS NULL OR p_horas_vigencia < 1 OR p_horas_vigencia > 72 THEN
        PERFORM interno.sp_comun_error('HH422', 'vigencia_invalida', 'La vigencia del enlace debe estar entre 1 y 72 horas');
    END IF;

    SELECT u.* INTO v_usuario FROM usuario u WHERE u.id_usuario = p_id_usuario FOR UPDATE;
    IF NOT FOUND THEN
        PERFORM interno.sp_comun_error('HH404', 'usuario_no_encontrado', 'El usuario no existe');
    END IF;
    SELECT r.nombre INTO v_rol FROM rol r WHERE r.id_rol = v_usuario.id_rol;

    IF v_rol = 'cliente' THEN
        PERFORM interno.sp_comun_exigir_permiso(v_actor, 'CLIENTES_GESTIONAR');
    ELSE
        PERFORM interno.sp_comun_exigir_permiso(v_actor, 'EMPLEADOS_GESTIONAR');
        SELECT e.id_empleado INTO v_id_empleado FROM empleado e WHERE e.id_usuario = p_id_usuario;
        IF v_id_empleado IS NOT NULL THEN
            PERFORM interno.sp_empleados_exigir_acceso(v_actor, v_id_empleado);
        ELSIF v_actor.rol <> 'administrador' THEN
            PERFORM interno.sp_comun_error('HH403', 'sin_permiso', 'Solo el administrador puede generar este enlace');
        END IF;
    END IF;

    IF NOT v_usuario.activo THEN
        PERFORM interno.sp_comun_error('HH409', 'usuario_inactivo', 'El usuario está desactivado');
    END IF;
    IF v_usuario.contrasena_hash IS NOT NULL THEN
        PERFORM interno.sp_comun_error('HH409', 'contrasena_ya_definida',
            'El usuario ya tiene contraseña; puede cambiarla desde su perfil');
    END IF;

    UPDATE enlace_contrasena ec SET revocado_en = now()
     WHERE ec.id_usuario = p_id_usuario AND ec.usado_en IS NULL AND ec.revocado_en IS NULL;

    v_expira := now() + make_interval(hours => p_horas_vigencia);
    INSERT INTO enlace_contrasena (id_usuario, token_hash, tipo, expira_en, creado_por)
    VALUES (p_id_usuario, p_token_hash, 'definir', v_expira, p_id_usuario_actor)
    RETURNING enlace_contrasena.id_enlace_contrasena INTO v_id;

    PERFORM interno.sp_comun_registrar_bitacora(p_id_usuario_actor, NULL, 'usuarios', 'enlace_contrasena', v_id::text,
        'crear', NULL, jsonb_build_object('id_usuario', p_id_usuario, 'expira_en', v_expira));

    RETURN QUERY SELECT v_id, v_usuario.correo, v_expira;
END;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_validar_enlace_contrasena(p_token_hash TEXT)
RETURNS TABLE (correo CITEXT, nombres VARCHAR, tipo VARCHAR, expira_en TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT u.correo, COALESCE(c.nombres, e.nombres), ec.tipo, ec.expira_en
      FROM enlace_contrasena ec
      JOIN usuario u ON u.id_usuario = ec.id_usuario
      LEFT JOIN cliente c ON c.id_usuario = u.id_usuario
      LEFT JOIN empleado e ON e.id_usuario = u.id_usuario
     WHERE ec.token_hash = p_token_hash
       AND ec.usado_en IS NULL AND ec.revocado_en IS NULL
       AND ec.expira_en > now()
       AND u.activo;
$$;

CREATE OR REPLACE FUNCTION sp_seguridad_usar_enlace_contrasena(p_token_hash TEXT, p_contrasena_hash TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_enlace  enlace_contrasena%ROWTYPE;
    v_activo  BOOLEAN;
BEGIN
    PERFORM interno.sp_comun_exigir_texto(p_token_hash, 'token');
    PERFORM interno.sp_comun_exigir_texto(p_contrasena_hash, 'contraseña');

    SELECT ec.* INTO v_enlace FROM enlace_contrasena ec WHERE ec.token_hash = p_token_hash FOR UPDATE;
    IF NOT FOUND OR v_enlace.usado_en IS NOT NULL OR v_enlace.revocado_en IS NOT NULL OR v_enlace.expira_en <= now() THEN
        PERFORM interno.sp_comun_error('HH422', 'enlace_invalido', 'El enlace no es válido o ya venció. Solicite uno nuevo');
    END IF;

    SELECT u.activo INTO v_activo FROM usuario u WHERE u.id_usuario = v_enlace.id_usuario FOR UPDATE;
    IF NOT v_activo THEN
        PERFORM interno.sp_comun_error('HH422', 'enlace_invalido', 'El enlace no es válido o ya venció. Solicite uno nuevo');
    END IF;

    UPDATE usuario u
       SET contrasena_hash = p_contrasena_hash, intentos_fallidos = 0, bloqueado_hasta = NULL
     WHERE u.id_usuario = v_enlace.id_usuario;
    UPDATE enlace_contrasena ec SET usado_en = now() WHERE ec.id_enlace_contrasena = v_enlace.id_enlace_contrasena;
    PERFORM sp_seguridad_cerrar_todas_sesiones(v_enlace.id_usuario);

    PERFORM interno.sp_comun_registrar_bitacora(v_enlace.id_usuario, NULL, 'usuarios', 'usuario', v_enlace.id_usuario::text,
        'modificar', '{"contrasena": "por enlace"}'::jsonb, jsonb_build_object('contrasena', 'definida', 'tipo', v_enlace.tipo));
    RETURN v_enlace.id_usuario;
END;
$$;

GRANT EXECUTE ON FUNCTION
    sp_seguridad_generar_enlace_contrasena(BIGINT, BIGINT, TEXT, INTEGER),
    sp_seguridad_validar_enlace_contrasena(TEXT),
    sp_seguridad_usar_enlace_contrasena(TEXT, TEXT)
TO horiani_api;

INSERT INTO version_esquema (script) VALUES ('034_sp_enlace_contrasena.sql');