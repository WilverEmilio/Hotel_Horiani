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

INSERT INTO rol (nombre, descripcion) VALUES
    ('cliente',       'Reserva, paga y consulta sus propias reservaciones'),
    ('administrador', 'Acceso total: precios, habitaciones, empleados, inventario, contenido web y bitácora'),
    ('operador',      'Recepción: reservaciones, check-in, check-out, cobro de saldo y registro de clientes'),
    ('oficinista',    'Todo lo del operador más reportes, clientes, cupones, asistencia y consulta de pagos'),
    ('limpieza',      'Habitaciones asignadas, tareas de limpieza, reporte de daños y consumo de insumos'),
    ('lavanderia',    'Control de blancos: recepción, devolución, bajas y faltantes');

CREATE TABLE permiso (
    id_permiso   SMALLINT GENERATED ALWAYS AS IDENTITY,
    codigo       VARCHAR(40)  NOT NULL,
    descripcion  VARCHAR(200) NOT NULL,
    creado_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_permiso PRIMARY KEY (id_permiso),
    CONSTRAINT uq_permiso_codigo UNIQUE (codigo),
    CONSTRAINT ck_permiso_codigo CHECK (codigo ~ '^[A-Z]+(_[A-Z]+)*$')
);

CREATE TABLE rol_permiso (
    id_rol      SMALLINT     NOT NULL,
    id_permiso  SMALLINT     NOT NULL,
    creado_en   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_rol_permiso PRIMARY KEY (id_rol, id_permiso),
    CONSTRAINT fk_rol_permiso_rol FOREIGN KEY (id_rol) REFERENCES rol (id_rol),
    CONSTRAINT fk_rol_permiso_permiso FOREIGN KEY (id_permiso) REFERENCES permiso (id_permiso)
);

CREATE INDEX ix_rol_permiso_permiso ON rol_permiso (id_permiso);

INSERT INTO permiso (codigo, descripcion) VALUES
    ('RESERVAR',                'Reservar, pagar, ver y cancelar sus propias reservaciones'),
    ('RESERVACIONES_GESTIONAR', 'Crear, modificar, cancelar y reasignar reservaciones; check-in y check-out'),
    ('PAGOS_REGISTRAR',         'Registrar cobros del saldo en el hotel'),
    ('PAGOS_VER',               'Consultar pagos y reembolsos'),
    ('CLIENTES_GESTIONAR',      'Registrar, consultar y editar clientes'),
    ('HABITACIONES_VER',        'Consultar habitaciones y su estado'),
    ('HABITACIONES_ESTADO',     'Cambiar el estado operativo de una habitación'),
    ('HABITACIONES_GESTIONAR',  'Administrar tipos de habitación, habitaciones y servicios'),
    ('PRECIOS_GESTIONAR',       'Modificar precio base y tarifas especiales'),
    ('CUPONES_GESTIONAR',       'Administrar cupones'),
    ('EMPLEADOS_GESTIONAR',     'Administrar empleados, turnos y usuarios del personal'),
    ('ASISTENCIA_REGISTRAR',    'Registrar la asistencia del personal'),
    ('INVENTARIO_GESTIONAR',    'Artículos, entradas, salidas y ajustes de inventario'),
    ('INSUMOS_CONSUMIR',        'Registrar consumo de insumos en habitaciones'),
    ('LAVANDERIA_GESTIONAR',    'Recepción, devolución, bajas y faltantes de blancos'),
    ('LIMPIEZA_GESTIONAR',      'Tareas de limpieza de habitaciones'),
    ('MANTENIMIENTO_REPORTAR',  'Reportar daños y fallas'),
    ('MANTENIMIENTO_GESTIONAR', 'Atender reportes y bloquear habitaciones por mantenimiento'),
    ('REPORTES_VER',            'Dashboard y reportes'),
    ('CONTENIDO_WEB_GESTIONAR', 'Editar el contenido de la página web'),
    ('HOTELES_GESTIONAR',       'Administrar hoteles y su configuración'),
    ('USUARIOS_GESTIONAR',      'Activar y desactivar usuarios'),
    ('BITACORA_VER',            'Consultar la bitácora');

INSERT INTO rol_permiso (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
  FROM (VALUES
        ('cliente',    'RESERVAR'),

        ('operador',   'RESERVACIONES_GESTIONAR'),
        ('operador',   'PAGOS_REGISTRAR'),
        ('operador',   'CLIENTES_GESTIONAR'),
        ('operador',   'HABITACIONES_VER'),
        ('operador',   'HABITACIONES_ESTADO'),
        ('operador',   'MANTENIMIENTO_REPORTAR'),
        ('operador',   'MANTENIMIENTO_GESTIONAR'),

        ('oficinista', 'RESERVACIONES_GESTIONAR'),
        ('oficinista', 'PAGOS_REGISTRAR'),
        ('oficinista', 'PAGOS_VER'),
        ('oficinista', 'CLIENTES_GESTIONAR'),
        ('oficinista', 'HABITACIONES_VER'),
        ('oficinista', 'HABITACIONES_ESTADO'),
        ('oficinista', 'CUPONES_GESTIONAR'),
        ('oficinista', 'ASISTENCIA_REGISTRAR'),
        ('oficinista', 'MANTENIMIENTO_REPORTAR'),
        ('oficinista', 'MANTENIMIENTO_GESTIONAR'),
        ('oficinista', 'REPORTES_VER'),

        ('limpieza',   'HABITACIONES_VER'),
        ('limpieza',   'LIMPIEZA_GESTIONAR'),
        ('limpieza',   'INSUMOS_CONSUMIR'),
        ('limpieza',   'MANTENIMIENTO_REPORTAR'),

        ('lavanderia', 'LAVANDERIA_GESTIONAR'),
        ('lavanderia', 'MANTENIMIENTO_REPORTAR')
       ) AS m (rol, permiso)
  JOIN rol r ON r.nombre = m.rol
  JOIN permiso p ON p.codigo = m.permiso;

INSERT INTO rol_permiso (id_rol, id_permiso)
SELECT r.id_rol, p.id_permiso
  FROM rol r CROSS JOIN permiso p
 WHERE r.nombre = 'administrador' AND p.codigo <> 'RESERVAR';

CREATE TABLE usuario (
    id_usuario         BIGINT GENERATED ALWAYS AS IDENTITY,
    correo             CITEXT       NOT NULL,
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

CREATE TRIGGER tr_usuario_no_eliminar
    BEFORE DELETE ON usuario
    FOR EACH ROW EXECUTE FUNCTION tg_comun_no_eliminar();

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

INSERT INTO version_esquema (script) VALUES ('002_seguridad.sql');