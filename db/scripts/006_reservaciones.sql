-- =============================================================================
-- 006_reservaciones.sql
-- Reservaciones, habitaciones reservadas, precio por noche e historial (RN-03).
-- =============================================================================

-- Encabezado. Un solo total y un solo anticipo aunque incluya varias
-- habitaciones; todas comparten fecha de entrada y de salida.
CREATE TABLE reservacion (
    id_reservacion      BIGINT GENERATED ALWAYS AS IDENTITY,
    codigo              VARCHAR(20)    NOT NULL,
    id_hotel            BIGINT         NOT NULL,
    id_cliente          BIGINT         NOT NULL,
    fecha_entrada       DATE           NOT NULL,
    fecha_salida        DATE           NOT NULL,
    estado              VARCHAR(20)    NOT NULL DEFAULT 'pendiente_pago',
    origen              VARCHAR(15)    NOT NULL,
    creado_por          BIGINT         NOT NULL,
    -- Fotografía de montos al momento de reservar. Cambios posteriores de
    -- precio, tarifa o cupón no la afectan.
    subtotal            DECIMAL(10,2)  NOT NULL,
    descuento           DECIMAL(10,2)  NOT NULL DEFAULT 0,
    total               DECIMAL(10,2)  NOT NULL,
    iva_incluido        DECIMAL(10,2)  NOT NULL,
    monto_anticipo      DECIMAL(10,2)  NOT NULL,
    id_cupon            BIGINT,
    codigo_cupon        VARCHAR(30),
    -- Vencimiento del bloqueo mientras se espera el pago del anticipo.
    expira_en           TIMESTAMPTZ,
    -- La genera el cliente (web o app). Repetir la petición con la misma llave
    -- devuelve la reservación existente en vez de crear otra.
    llave_idempotencia  UUID           NOT NULL,
    checkin_en          TIMESTAMPTZ,
    checkout_en         TIMESTAMPTZ,
    cancelada_en        TIMESTAMPTZ,
    motivo_cancelacion  VARCHAR(300),
    creado_en           TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en      TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_reservacion PRIMARY KEY (id_reservacion),
    CONSTRAINT uq_reservacion_codigo UNIQUE (codigo),
    CONSTRAINT uq_reservacion_idempotencia UNIQUE (id_cliente, llave_idempotencia),
    -- Necesaria para la llave foránea compuesta de reservacion_habitacion.
    CONSTRAINT uq_reservacion_id_hotel UNIQUE (id_reservacion, id_hotel),
    CONSTRAINT fk_reservacion_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT fk_reservacion_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente),
    CONSTRAINT fk_reservacion_usuario FOREIGN KEY (creado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT fk_reservacion_cupon FOREIGN KEY (id_cupon) REFERENCES cupon (id_cupon),
    CONSTRAINT ck_reservacion_fechas CHECK (fecha_salida > fecha_entrada),
    CONSTRAINT ck_reservacion_estado CHECK (estado IN
        ('pendiente_pago', 'confirmada', 'en_curso', 'finalizada', 'cancelada', 'expirada', 'no_presentado')),
    CONSTRAINT ck_reservacion_origen CHECK (origen IN ('web', 'movil', 'recepcion')),
    CONSTRAINT ck_reservacion_subtotal CHECK (subtotal > 0),
    CONSTRAINT ck_reservacion_descuento CHECK (descuento >= 0 AND descuento <= subtotal),
    CONSTRAINT ck_reservacion_total CHECK (total = subtotal - descuento),
    CONSTRAINT ck_reservacion_iva CHECK (iva_incluido >= 0 AND iva_incluido <= total),
    CONSTRAINT ck_reservacion_anticipo CHECK (monto_anticipo >= 0 AND monto_anticipo <= total),
    CONSTRAINT ck_reservacion_cupon CHECK ((id_cupon IS NULL) = (codigo_cupon IS NULL)),
    CONSTRAINT ck_reservacion_expira CHECK (estado <> 'pendiente_pago' OR expira_en IS NOT NULL),
    CONSTRAINT ck_reservacion_cancelada CHECK (estado <> 'cancelada' OR cancelada_en IS NOT NULL)
);

CREATE TRIGGER tr_reservacion_actualizado_en
    BEFORE UPDATE ON reservacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Una fila por habitación reservada.
CREATE TABLE reservacion_habitacion (
    id_reservacion_habitacion  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_reservacion             BIGINT         NOT NULL,
    id_hotel                   BIGINT         NOT NULL,
    id_habitacion              BIGINT         NOT NULL,
    -- Tipo al momento de reservar (la habitación podría cambiar de tipo después).
    id_tipo_habitacion         BIGINT         NOT NULL,
    -- [entrada, salida): la noche de salida no cuenta, así que salir el día 10
    -- y entrar el día 10 no chocan.
    periodo                    DATERANGE      NOT NULL,
    huespedes                  INTEGER        NOT NULL,
    subtotal                   DECIMAL(10,2)  NOT NULL,
    -- TRUE mientras la reservación ocupa la habitación (pendiente de pago,
    -- confirmada o en curso). Pasa a FALSE al cancelar, expirar, no presentarse
    -- o finalizar, y la habitación queda libre para esas fechas.
    activa                     BOOLEAN        NOT NULL DEFAULT TRUE,
    creado_en                  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en             TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_reservacion_habitacion PRIMARY KEY (id_reservacion_habitacion),
    CONSTRAINT uq_reservacion_habitacion UNIQUE (id_reservacion, id_habitacion),
    -- Llaves compuestas: la habitación debe ser del mismo hotel que la reservación.
    CONSTRAINT fk_reservacion_habitacion_reservacion FOREIGN KEY (id_reservacion, id_hotel)
        REFERENCES reservacion (id_reservacion, id_hotel),
    CONSTRAINT fk_reservacion_habitacion_habitacion FOREIGN KEY (id_habitacion, id_hotel)
        REFERENCES habitacion (id_habitacion, id_hotel),
    CONSTRAINT fk_reservacion_habitacion_tipo FOREIGN KEY (id_tipo_habitacion)
        REFERENCES tipo_habitacion (id_tipo_habitacion),
    CONSTRAINT ck_reservacion_habitacion_periodo CHECK (
        NOT isempty(periodo) AND NOT lower_inf(periodo) AND NOT upper_inf(periodo)),
    CONSTRAINT ck_reservacion_habitacion_huespedes CHECK (huespedes > 0),
    CONSTRAINT ck_reservacion_habitacion_subtotal CHECK (subtotal > 0),
    -- REGLA CRÍTICA: una habitación no puede tener dos reservaciones activas
    -- con fechas cruzadas. La garantiza PostgreSQL, incluso si dos clientes
    -- confirman en el mismo instante.
    CONSTRAINT ex_reservacion_habitacion_traslape EXCLUDE USING gist
        (id_habitacion WITH =, periodo WITH &&) WHERE (activa)
);

CREATE TRIGGER tr_reservacion_habitacion_actualizado_en
    BEFORE UPDATE ON reservacion_habitacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Precio congelado de cada noche de cada habitación.
CREATE TABLE reservacion_noche (
    id_reservacion_noche       BIGINT GENERATED ALWAYS AS IDENTITY,
    id_reservacion_habitacion  BIGINT         NOT NULL,
    fecha                      DATE           NOT NULL,
    precio_noche               DECIMAL(10,2)  NOT NULL,
    -- NULL = se cobró el precio base.
    id_tarifa_especial         BIGINT,
    creado_en                  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_reservacion_noche PRIMARY KEY (id_reservacion_noche),
    CONSTRAINT uq_reservacion_noche UNIQUE (id_reservacion_habitacion, fecha),
    CONSTRAINT fk_reservacion_noche_habitacion FOREIGN KEY (id_reservacion_habitacion)
        REFERENCES reservacion_habitacion (id_reservacion_habitacion),
    CONSTRAINT fk_reservacion_noche_tarifa FOREIGN KEY (id_tarifa_especial)
        REFERENCES tarifa_especial (id_tarifa_especial),
    CONSTRAINT ck_reservacion_noche_precio CHECK (precio_noche > 0)
);

-- Cada cambio de estado: responde quién canceló, cuándo y por qué.
CREATE TABLE reservacion_estado_historial (
    id_reservacion_estado_historial  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_reservacion                   BIGINT       NOT NULL,
    estado_anterior                  VARCHAR(20),
    estado_nuevo                     VARCHAR(20)  NOT NULL,
    -- NULL = cambio hecho por el sistema (expiración automática, pasarela).
    id_usuario                       BIGINT,
    motivo                           VARCHAR(300),
    creado_en                        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_reservacion_estado_historial PRIMARY KEY (id_reservacion_estado_historial),
    CONSTRAINT fk_reservacion_estado_historial_reservacion FOREIGN KEY (id_reservacion)
        REFERENCES reservacion (id_reservacion),
    CONSTRAINT fk_reservacion_estado_historial_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario),
    CONSTRAINT ck_reservacion_estado_historial_cambio CHECK (
        estado_anterior IS DISTINCT FROM estado_nuevo)
);

-- Uso de un cupón en una reservación. Si la reservación se cancela o expira,
-- pasa a 'devuelto' y se descuenta de cupon.usos_actuales.
CREATE TABLE cupon_uso (
    id_cupon_uso     BIGINT GENERATED ALWAYS AS IDENTITY,
    id_cupon         BIGINT         NOT NULL,
    id_cliente       BIGINT         NOT NULL,
    id_reservacion   BIGINT         NOT NULL,
    monto_descuento  DECIMAL(10,2)  NOT NULL,
    estado           VARCHAR(10)    NOT NULL DEFAULT 'aplicado',
    creado_en        TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_cupon_uso PRIMARY KEY (id_cupon_uso),
    -- Un solo cupón por reservación.
    CONSTRAINT uq_cupon_uso_reservacion UNIQUE (id_reservacion),
    CONSTRAINT fk_cupon_uso_cupon FOREIGN KEY (id_cupon) REFERENCES cupon (id_cupon),
    CONSTRAINT fk_cupon_uso_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente),
    CONSTRAINT fk_cupon_uso_reservacion FOREIGN KEY (id_reservacion)
        REFERENCES reservacion (id_reservacion),
    CONSTRAINT ck_cupon_uso_monto CHECK (monto_descuento > 0),
    CONSTRAINT ck_cupon_uso_estado CHECK (estado IN ('aplicado', 'devuelto'))
);

CREATE TRIGGER tr_cupon_uso_actualizado_en
    BEFORE UPDATE ON cupon_uso
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();
