-- =============================================================================
-- 003_hoteles_habitaciones.sql
-- Hoteles, configuración, tipos de habitación, tarifas y habitaciones (RN-02).
-- =============================================================================

CREATE TABLE hotel (
    id_hotel        BIGINT GENERATED ALWAYS AS IDENTITY,
    nombre          VARCHAR(120) NOT NULL,
    slug            VARCHAR(120) NOT NULL,
    direccion       VARCHAR(250) NOT NULL,
    ciudad          VARCHAR(100) NOT NULL,
    telefono        VARCHAR(20),
    correo          CITEXT,
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_hotel PRIMARY KEY (id_hotel),
    CONSTRAINT uq_hotel_nombre UNIQUE (nombre),
    CONSTRAINT uq_hotel_slug UNIQUE (slug),
    CONSTRAINT ck_hotel_slug CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

CREATE TRIGGER tr_hotel_actualizado_en
    BEFORE UPDATE ON hotel
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Una fila por hotel. Aquí viven los parámetros de negocio que pueden cambiar
-- sin tocar código, incluida la política de cancelación (pendiente del cliente:
-- NULL significa "sin política definida todavía").
CREATE TABLE hotel_configuracion (
    id_hotel                         BIGINT        NOT NULL,
    hora_checkout                    TIME          NOT NULL DEFAULT '11:00',
    porcentaje_anticipo              DECIMAL(5,2)  NOT NULL DEFAULT 50.00,
    minutos_bloqueo_pago             INTEGER       NOT NULL DEFAULT 15,
    horas_limite_cancelacion         INTEGER,
    porcentaje_reembolso             DECIMAL(5,2),
    no_presentacion_pierde_anticipo  BOOLEAN,
    creado_en                        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    actualizado_en                   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT pk_hotel_configuracion PRIMARY KEY (id_hotel),
    CONSTRAINT fk_hotel_configuracion_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT ck_hotel_configuracion_anticipo CHECK (porcentaje_anticipo > 0 AND porcentaje_anticipo <= 100),
    CONSTRAINT ck_hotel_configuracion_bloqueo CHECK (minutos_bloqueo_pago > 0),
    CONSTRAINT ck_hotel_configuracion_horas CHECK (horas_limite_cancelacion IS NULL OR horas_limite_cancelacion >= 0),
    CONSTRAINT ck_hotel_configuracion_reembolso CHECK (porcentaje_reembolso IS NULL
        OR (porcentaje_reembolso >= 0 AND porcentaje_reembolso <= 100))
);

CREATE TRIGGER tr_hotel_configuracion_actualizado_en
    BEFORE UPDATE ON hotel_configuracion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE TABLE tipo_habitacion (
    id_tipo_habitacion  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_hotel            BIGINT         NOT NULL,
    nombre              VARCHAR(80)    NOT NULL,
    descripcion         TEXT,
    capacidad_maxima    INTEGER        NOT NULL,
    -- Precio fijo por noche, IVA incluido. Solo lo cambia el administrador y
    -- cada cambio queda en bitácora con valor anterior y valor nuevo.
    precio_base         DECIMAL(10,2)  NOT NULL,
    activo              BOOLEAN        NOT NULL DEFAULT TRUE,
    creado_en           TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en      TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_tipo_habitacion PRIMARY KEY (id_tipo_habitacion),
    CONSTRAINT fk_tipo_habitacion_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT uq_tipo_habitacion_hotel_nombre UNIQUE (id_hotel, nombre),
    -- Necesaria para la llave foránea compuesta de habitacion.
    CONSTRAINT uq_tipo_habitacion_id_hotel UNIQUE (id_tipo_habitacion, id_hotel),
    CONSTRAINT ck_tipo_habitacion_capacidad CHECK (capacidad_maxima > 0),
    CONSTRAINT ck_tipo_habitacion_precio CHECK (precio_base > 0)
);

CREATE TRIGGER tr_tipo_habitacion_actualizado_en
    BEFORE UPDATE ON tipo_habitacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Precio distinto al base en fechas especiales (días festivos, temporada).
-- periodo es [desde, hasta): la fecha final no se incluye.
CREATE TABLE tarifa_especial (
    id_tarifa_especial  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_tipo_habitacion  BIGINT         NOT NULL,
    nombre              VARCHAR(100)   NOT NULL,
    periodo             DATERANGE      NOT NULL,
    precio_noche        DECIMAL(10,2)  NOT NULL,
    creado_por          BIGINT         NOT NULL,
    activo              BOOLEAN        NOT NULL DEFAULT TRUE,
    creado_en           TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en      TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_tarifa_especial PRIMARY KEY (id_tarifa_especial),
    CONSTRAINT fk_tarifa_especial_tipo FOREIGN KEY (id_tipo_habitacion)
        REFERENCES tipo_habitacion (id_tipo_habitacion),
    CONSTRAINT fk_tarifa_especial_usuario FOREIGN KEY (creado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_tarifa_especial_precio CHECK (precio_noche > 0),
    CONSTRAINT ck_tarifa_especial_periodo CHECK (
        NOT isempty(periodo) AND NOT lower_inf(periodo) AND NOT upper_inf(periodo)),
    -- Un tipo de habitación no puede tener dos tarifas especiales activas
    -- con fechas cruzadas: el precio de una noche nunca es ambiguo.
    CONSTRAINT ex_tarifa_especial_traslape EXCLUDE USING gist
        (id_tipo_habitacion WITH =, periodo WITH &&) WHERE (activo)
);

CREATE TRIGGER tr_tarifa_especial_actualizado_en
    BEFORE UPDATE ON tarifa_especial
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE TABLE servicio (
    id_servicio  BIGINT GENERATED ALWAYS AS IDENTITY,
    nombre       VARCHAR(80)  NOT NULL,
    icono        VARCHAR(60),
    activo       BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_servicio PRIMARY KEY (id_servicio),
    CONSTRAINT uq_servicio_nombre UNIQUE (nombre)
);

CREATE TABLE tipo_habitacion_servicio (
    id_tipo_habitacion  BIGINT       NOT NULL,
    id_servicio         BIGINT       NOT NULL,
    creado_en           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_tipo_habitacion_servicio PRIMARY KEY (id_tipo_habitacion, id_servicio),
    CONSTRAINT fk_tipo_habitacion_servicio_tipo FOREIGN KEY (id_tipo_habitacion)
        REFERENCES tipo_habitacion (id_tipo_habitacion),
    CONSTRAINT fk_tipo_habitacion_servicio_servicio FOREIGN KEY (id_servicio)
        REFERENCES servicio (id_servicio)
);

CREATE TABLE tipo_habitacion_imagen (
    id_tipo_habitacion_imagen  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_tipo_habitacion         BIGINT        NOT NULL,
    url                        VARCHAR(500)  NOT NULL,
    texto_alternativo          VARCHAR(200),
    orden                      INTEGER       NOT NULL DEFAULT 0,
    creado_en                  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT pk_tipo_habitacion_imagen PRIMARY KEY (id_tipo_habitacion_imagen),
    CONSTRAINT fk_tipo_habitacion_imagen_tipo FOREIGN KEY (id_tipo_habitacion)
        REFERENCES tipo_habitacion (id_tipo_habitacion),
    CONSTRAINT ck_tipo_habitacion_imagen_orden CHECK (orden >= 0)
);

CREATE TABLE habitacion (
    id_habitacion       BIGINT GENERATED ALWAYS AS IDENTITY,
    id_hotel            BIGINT       NOT NULL,
    id_tipo_habitacion  BIGINT       NOT NULL,
    numero              VARCHAR(10)  NOT NULL,
    piso                INTEGER,
    estado              VARCHAR(20)  NOT NULL DEFAULT 'disponible',
    activo              BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_habitacion PRIMARY KEY (id_habitacion),
    CONSTRAINT fk_habitacion_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    -- Llave compuesta: impide asignar a una habitación un tipo de otro hotel.
    CONSTRAINT fk_habitacion_tipo FOREIGN KEY (id_tipo_habitacion, id_hotel)
        REFERENCES tipo_habitacion (id_tipo_habitacion, id_hotel),
    CONSTRAINT uq_habitacion_hotel_numero UNIQUE (id_hotel, numero),
    -- Necesaria para las llaves foráneas compuestas de reservaciones.
    CONSTRAINT uq_habitacion_id_hotel UNIQUE (id_habitacion, id_hotel),
    CONSTRAINT ck_habitacion_estado CHECK (estado IN
        ('disponible', 'ocupada', 'en_limpieza', 'en_mantenimiento', 'fuera_de_servicio'))
);

CREATE TRIGGER tr_habitacion_actualizado_en
    BEFORE UPDATE ON habitacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();
