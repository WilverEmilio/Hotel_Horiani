-- =============================================================================
-- 004_clientes_empleados.sql
-- Clientes (RN-06), empleados, turnos y asistencia (RN-07).
-- =============================================================================

CREATE TABLE cliente (
    id_cliente        BIGINT GENERATED ALWAYS AS IDENTITY,
    -- NULL: cliente registrado en recepción solo con nombre, documento y
    -- teléfono, sin cuenta. Si después crea su cuenta, se enlaza aquí.
    id_usuario        BIGINT,
    nombres           VARCHAR(100) NOT NULL,
    apellidos         VARCHAR(100) NOT NULL,
    telefono          VARCHAR(20)  NOT NULL,
    tipo_documento    VARCHAR(10)  NOT NULL,
    numero_documento  VARCHAR(30)  NOT NULL,
    pais              VARCHAR(80)  NOT NULL DEFAULT 'Guatemala',
    activo            BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT fk_cliente_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario),
    CONSTRAINT uq_cliente_usuario UNIQUE (id_usuario),
    CONSTRAINT uq_cliente_documento UNIQUE (tipo_documento, numero_documento),
    CONSTRAINT ck_cliente_tipo_documento CHECK (tipo_documento IN ('dpi', 'pasaporte')),
    CONSTRAINT ck_cliente_dpi CHECK (tipo_documento <> 'dpi' OR numero_documento ~ '^[0-9]{13}$')
);

CREATE TRIGGER tr_cliente_actualizado_en
    BEFORE UPDATE ON cliente
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE TABLE empleado (
    id_empleado     BIGINT GENERATED ALWAYS AS IDENTITY,
    -- NULL: empleado que no usa el sistema ni la aplicación.
    id_usuario      BIGINT,
    nombres         VARCHAR(100) NOT NULL,
    apellidos       VARCHAR(100) NOT NULL,
    dpi             VARCHAR(13)  NOT NULL,
    telefono        VARCHAR(20),
    puesto          VARCHAR(80)  NOT NULL,
    fecha_ingreso   DATE         NOT NULL,
    fecha_baja      DATE,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_empleado PRIMARY KEY (id_empleado),
    CONSTRAINT fk_empleado_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario),
    CONSTRAINT uq_empleado_usuario UNIQUE (id_usuario),
    CONSTRAINT uq_empleado_dpi UNIQUE (dpi),
    CONSTRAINT ck_empleado_dpi CHECK (dpi ~ '^[0-9]{13}$'),
    CONSTRAINT ck_empleado_fechas CHECK (fecha_baja IS NULL OR fecha_baja >= fecha_ingreso)
);

CREATE TRIGGER tr_empleado_actualizado_en
    BEFORE UPDATE ON empleado
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Hoteles en los que trabaja cada empleado; limita qué datos puede ver.
CREATE TABLE empleado_hotel (
    id_empleado  BIGINT       NOT NULL,
    id_hotel     BIGINT       NOT NULL,
    creado_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_empleado_hotel PRIMARY KEY (id_empleado, id_hotel),
    CONSTRAINT fk_empleado_hotel_empleado FOREIGN KEY (id_empleado) REFERENCES empleado (id_empleado),
    CONSTRAINT fk_empleado_hotel_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel)
);

-- Turnos fijos de cada hotel. hora_fin puede ser menor que hora_inicio:
-- significa que el turno termina al día siguiente (ejemplo 18:00 a 08:00).
CREATE TABLE turno (
    id_turno        BIGINT GENERATED ALWAYS AS IDENTITY,
    id_hotel        BIGINT       NOT NULL,
    nombre          VARCHAR(60)  NOT NULL,
    hora_inicio     TIME         NOT NULL,
    hora_fin        TIME         NOT NULL,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_turno PRIMARY KEY (id_turno),
    CONSTRAINT fk_turno_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT uq_turno_hotel_nombre UNIQUE (id_hotel, nombre),
    CONSTRAINT uq_turno_id_hotel UNIQUE (id_turno, id_hotel),
    CONSTRAINT ck_turno_horas CHECK (hora_inicio <> hora_fin)
);

CREATE TRIGGER tr_turno_actualizado_en
    BEFORE UPDATE ON turno
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Turno fijo asignado a un empleado. vigencia con fin abierto = sigue vigente.
-- Un empleado puede cubrir más de un turno, pero no el mismo turno dos veces
-- en fechas cruzadas.
CREATE TABLE empleado_turno (
    id_empleado_turno  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_empleado        BIGINT       NOT NULL,
    id_hotel           BIGINT       NOT NULL,
    id_turno           BIGINT       NOT NULL,
    vigencia           DATERANGE    NOT NULL,
    creado_por         BIGINT       NOT NULL,
    creado_en          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_empleado_turno PRIMARY KEY (id_empleado_turno),
    CONSTRAINT fk_empleado_turno_empleado_hotel FOREIGN KEY (id_empleado, id_hotel)
        REFERENCES empleado_hotel (id_empleado, id_hotel),
    CONSTRAINT fk_empleado_turno_turno FOREIGN KEY (id_turno, id_hotel)
        REFERENCES turno (id_turno, id_hotel),
    CONSTRAINT fk_empleado_turno_usuario FOREIGN KEY (creado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_empleado_turno_vigencia CHECK (NOT isempty(vigencia) AND NOT lower_inf(vigencia)),
    CONSTRAINT ex_empleado_turno_traslape EXCLUDE USING gist
        (id_empleado WITH =, id_turno WITH =, vigencia WITH &&)
);

CREATE TRIGGER tr_empleado_turno_actualizado_en
    BEFORE UPDATE ON empleado_turno
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Control de asistencia. Lo registra el administrador o el oficinista.
-- id_turno es NULL en estados que cubren el día completo (vacaciones, descanso).
CREATE TABLE asistencia (
    id_asistencia   BIGINT GENERATED ALWAYS AS IDENTITY,
    id_empleado     BIGINT       NOT NULL,
    id_hotel        BIGINT       NOT NULL,
    id_turno        BIGINT,
    fecha           DATE         NOT NULL,
    estado          VARCHAR(20)  NOT NULL,
    observacion     VARCHAR(300),
    registrado_por  BIGINT       NOT NULL,
    creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_asistencia PRIMARY KEY (id_asistencia),
    CONSTRAINT fk_asistencia_empleado_hotel FOREIGN KEY (id_empleado, id_hotel)
        REFERENCES empleado_hotel (id_empleado, id_hotel),
    CONSTRAINT fk_asistencia_turno FOREIGN KEY (id_turno, id_hotel)
        REFERENCES turno (id_turno, id_hotel),
    CONSTRAINT fk_asistencia_usuario FOREIGN KEY (registrado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT uq_asistencia_empleado_fecha_turno UNIQUE NULLS NOT DISTINCT
        (id_empleado, id_hotel, fecha, id_turno),
    CONSTRAINT ck_asistencia_estado CHECK (estado IN
        ('asistio', 'llegada_tarde', 'falto', 'permiso', 'descanso', 'vacaciones', 'suspension')),
    -- Asistir, llegar tarde o faltar siempre se refiere a un turno concreto.
    CONSTRAINT ck_asistencia_turno CHECK (
        estado NOT IN ('asistio', 'llegada_tarde', 'falto') OR id_turno IS NOT NULL)
);

CREATE TRIGGER tr_asistencia_actualizado_en
    BEFORE UPDATE ON asistencia
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();
