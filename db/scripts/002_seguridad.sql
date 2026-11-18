-- =============================================================================
-- 002_seguridad.sql
-- Roles, usuarios y tokens de refresco (RN-01).
-- =============================================================================

CREATE TABLE rol (
    id_rol       SMALLINT GENERATED ALWAYS AS IDENTITY,
    nombre       VARCHAR(30)  NOT NULL,
    descripcion  VARCHAR(200) NOT NULL,
    creado_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_rol PRIMARY KEY (id_rol),
    CONSTRAINT uq_rol_nombre UNIQUE (nombre),
    CONSTRAINT ck_rol_nombre CHECK (nombre IN
        ('cliente', 'administrador', 'operador', 'oficinista', 'limpieza', 'lavanderia'))
);

-- Catálogo fijo: forma parte de la estructura, no de los datos de prueba.
INSERT INTO rol (nombre, descripcion) VALUES
    ('cliente',       'Reserva, paga y consulta sus propias reservaciones'),
    ('administrador', 'Acceso total: precios, habitaciones, empleados, inventario, contenido web y bitácora'),
    ('operador',      'Recepción: reservaciones, check-in, check-out, cobro de saldo y registro de clientes'),
    ('oficinista',    'Todo lo del operador más reportes, clientes, cupones, asistencia y consulta de pagos'),
    ('limpieza',      'Habitaciones asignadas, tareas de limpieza, reporte de daños y consumo de insumos'),
    ('lavanderia',    'Control de blancos: recepción, devolución, bajas y faltantes');

CREATE TABLE usuario (
    id_usuario         BIGINT GENERATED ALWAYS AS IDENTITY,
    correo             CITEXT       NOT NULL,
    -- NULL solo mientras el cliente no ha definido su contraseña (cuenta creada
    -- en recepción con su correo). Sin contraseña no se puede iniciar sesión.
    contrasena_hash    VARCHAR(255),
    id_rol             SMALLINT     NOT NULL,
    intentos_fallidos  INTEGER      NOT NULL DEFAULT 0,
    bloqueado_hasta    TIMESTAMPTZ,
    activo             BOOLEAN      NOT NULL DEFAULT TRUE,
    ultimo_acceso_en   TIMESTAMPTZ,
    creado_en          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_usuario PRIMARY KEY (id_usuario),
    CONSTRAINT uq_usuario_correo UNIQUE (correo),
    CONSTRAINT fk_usuario_rol FOREIGN KEY (id_rol) REFERENCES rol (id_rol),
    CONSTRAINT ck_usuario_correo CHECK (correo ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CONSTRAINT ck_usuario_intentos CHECK (intentos_fallidos >= 0)
);

CREATE TRIGGER tr_usuario_actualizado_en
    BEFORE UPDATE ON usuario
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Refresh tokens con rotación. Se guarda el hash, nunca el token.
-- id_familia agrupa todos los tokens de una misma sesión: si se reutiliza uno
-- ya usado, se revoca la familia completa.
CREATE TABLE token_refresco (
    id_token_refresco  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_usuario         BIGINT       NOT NULL,
    token_hash         VARCHAR(128) NOT NULL,
    id_familia         UUID         NOT NULL,
    expira_en          TIMESTAMPTZ  NOT NULL,
    usado_en           TIMESTAMPTZ,
    revocado_en        TIMESTAMPTZ,
    direccion_ip       INET,
    agente_usuario     VARCHAR(300),
    creado_en          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_token_refresco PRIMARY KEY (id_token_refresco),
    CONSTRAINT uq_token_refresco_hash UNIQUE (token_hash),
    CONSTRAINT fk_token_refresco_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_token_refresco_expira CHECK (expira_en > creado_en)
);
