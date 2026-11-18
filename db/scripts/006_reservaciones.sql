-- =============================================================================
-- 006_reservaciones.sql
-- Reservaciones, habitaciones reservadas, precio por noche, historial,
-- transiciones de estado y uso de cupones (RN-03, RN-05).
-- =============================================================================

CREATE TABLE transicion_estado_reservacion (
    estado_origen   VARCHAR(20)  NOT NULL,
    estado_destino  VARCHAR(20)  NOT NULL,
    descripcion     VARCHAR(150) NOT NULL,
    CONSTRAINT pk_transicion_estado_reservacion PRIMARY KEY (estado_origen, estado_destino),
    CONSTRAINT ck_transicion_estado_reservacion_estados CHECK (
        estado_origen IN ('pendiente_pago', 'confirmada', 'en_curso')
        AND estado_destino IN ('confirmada', 'en_curso', 'finalizada', 'cancelada', 'expirada', 'no_presentado'))
);

INSERT INTO transicion_estado_reservacion (estado_origen, estado_destino, descripcion) VALUES
    ('pendiente_pago', 'confirmada',    'Se aprobó el pago del anticipo'),
    ('pendiente_pago', 'cancelada',     'El cliente o recepción cancela antes de pagar'),
    ('pendiente_pago', 'expirada',      'Venció el tiempo para pagar el anticipo'),
    ('confirmada',     'en_curso',      'Check-in'),
    ('confirmada',     'cancelada',     'Cancelación de una reservación confirmada'),
    ('confirmada',     'no_presentado', 'El cliente no llegó'),
    ('en_curso',       'finalizada',    'Check-out');

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
    subtotal            DECIMAL(10,2)  NOT NULL,
    descuento           DECIMAL(10,2)  NOT NULL DEFAULT 0,
    total               DECIMAL(10,2)  NOT NULL,
    base_imponible      DECIMAL(10,2)  NOT NULL,
    iva                 DECIMAL(10,2)  NOT NULL,
    monto_anticipo      DECIMAL(10,2)  NOT NULL,
    id_cupon            BIGINT,
    codigo_cupon        VARCHAR(30),
    expira_en           TIMESTAMPTZ,
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
    CONSTRAINT ck_reservacion_iva CHECK (base_imponible >= 0 AND iva >= 0 AND base_imponible + iva = total),
    CONSTRAINT ck_reservacion_anticipo CHECK (monto_anticipo >= 0 AND monto_anticipo <= total),
    CONSTRAINT ck_reservacion_cupon CHECK ((id_cupon IS NULL) = (codigo_cupon IS NULL)),
    CONSTRAINT ck_reservacion_expira CHECK (estado <> 'pendiente_pago' OR expira_en IS NOT NULL),
    CONSTRAINT ck_reservacion_cancelada CHECK (estado <> 'cancelada' OR cancelada_en IS NOT NULL)
);

CREATE TRIGGER tr_reservacion_actualizado_en
    BEFORE UPDATE ON reservacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE TRIGGER tr_reservacion_no_eliminar
    BEFORE DELETE ON reservacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_no_eliminar();

CREATE OR REPLACE FUNCTION tg_reservacion_proteger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (NEW.codigo, NEW.id_hotel, NEW.id_cliente, NEW.origen, NEW.creado_por, NEW.subtotal, NEW.descuento,
        NEW.total, NEW.base_imponible, NEW.iva, NEW.monto_anticipo, NEW.id_cupon, NEW.codigo_cupon,
        NEW.llave_idempotencia)
       IS DISTINCT FROM
       (OLD.codigo, OLD.id_hotel, OLD.id_cliente, OLD.origen, OLD.creado_por, OLD.subtotal, OLD.descuento,
        OLD.total, OLD.base_imponible, OLD.iva, OLD.monto_anticipo, OLD.id_cupon, OLD.codigo_cupon,
        OLD.llave_idempotencia) THEN
        RAISE EXCEPTION 'Los montos, el cliente y el cupón de una reservación no pueden modificarse'
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF NEW.estado IS DISTINCT FROM OLD.estado AND NOT EXISTS (
        SELECT 1 FROM transicion_estado_reservacion t
         WHERE t.estado_origen = OLD.estado AND t.estado_destino = NEW.estado) THEN
        RAISE EXCEPTION 'Una reservación en estado % no puede pasar a %', OLD.estado, NEW.estado
            USING ERRCODE = 'HH409', DETAIL = 'transicion_no_permitida';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tr_reservacion_proteger
    BEFORE UPDATE ON reservacion
    FOR EACH ROW EXECUTE FUNCTION tg_reservacion_proteger();

CREATE TABLE reservacion_habitacion (
    id_reservacion_habitacion  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_reservacion             BIGINT         NOT NULL,
    id_hotel                   BIGINT         NOT NULL,
    id_habitacion              BIGINT         NOT NULL,
    id_tipo_habitacion         BIGINT         NOT NULL,
    periodo                    DATERANGE      NOT NULL,
    huespedes                  INTEGER        NOT NULL,
    subtotal                   DECIMAL(10,2)  NOT NULL,
    activa                     BOOLEAN        NOT NULL DEFAULT TRUE,
    creado_en                  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en             TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_reservacion_habitacion PRIMARY KEY (id_reservacion_habitacion),
    CONSTRAINT uq_reservacion_habitacion UNIQUE (id_reservacion, id_habitacion),
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
    CONSTRAINT ex_reservacion_habitacion_traslape EXCLUDE USING gist
        (id_habitacion WITH =, periodo WITH &&) WHERE (activa)
);

CREATE TRIGGER tr_reservacion_habitacion_actualizado_en
    BEFORE UPDATE ON reservacion_habitacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE TRIGGER tr_reservacion_habitacion_no_eliminar
    BEFORE DELETE ON reservacion_habitacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_no_eliminar();
CREATE OR REPLACE FUNCTION tg_reservacion_habitacion_proteger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (NEW.id_reservacion, NEW.id_hotel, NEW.id_tipo_habitacion, NEW.periodo, NEW.huespedes, NEW.subtotal)
       IS DISTINCT FROM
       (OLD.id_reservacion, OLD.id_hotel, OLD.id_tipo_habitacion, OLD.periodo, OLD.huespedes, OLD.subtotal) THEN
        RAISE EXCEPTION 'El tipo, las fechas y el precio de una habitación reservada no pueden modificarse'
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tr_reservacion_habitacion_proteger
    BEFORE UPDATE ON reservacion_habitacion
    FOR EACH ROW EXECUTE FUNCTION tg_reservacion_habitacion_proteger();

CREATE TABLE reservacion_noche (
    id_reservacion_noche       BIGINT GENERATED ALWAYS AS IDENTITY,
    id_reservacion_habitacion  BIGINT         NOT NULL,
    fecha                      DATE           NOT NULL,
    precio_noche               DECIMAL(10,2)  NOT NULL,
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

CREATE TRIGGER tr_reservacion_noche_inmutable
    BEFORE UPDATE OR DELETE ON reservacion_noche
    FOR EACH ROW EXECUTE FUNCTION tg_comun_bloquear_cambios();

CREATE TABLE reservacion_estado_historial (
    id_reservacion_estado_historial  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_reservacion                   BIGINT       NOT NULL,
    estado_anterior                  VARCHAR(20),
    estado_nuevo                     VARCHAR(20)  NOT NULL,
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

CREATE TRIGGER tr_reservacion_estado_historial_inmutable
    BEFORE UPDATE OR DELETE ON reservacion_estado_historial
    FOR EACH ROW EXECUTE FUNCTION tg_comun_bloquear_cambios();
CREATE TABLE cupon_uso (
    id_cupon_uso     BIGINT GENERATED ALWAYS AS IDENTITY,
    id_cupon         BIGINT         NOT NULL,
    id_cliente       BIGINT         NOT NULL,
    id_reservacion   BIGINT         NOT NULL,
    monto_descuento  DECIMAL(10,2)  NOT NULL,
    estado           VARCHAR(10)    NOT NULL DEFAULT 'aplicado',
    devuelto_en      TIMESTAMPTZ,
    creado_en        TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_cupon_uso PRIMARY KEY (id_cupon_uso),
    CONSTRAINT uq_cupon_uso_reservacion UNIQUE (id_reservacion),
    CONSTRAINT fk_cupon_uso_cupon FOREIGN KEY (id_cupon) REFERENCES cupon (id_cupon),
    CONSTRAINT fk_cupon_uso_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente),
    CONSTRAINT fk_cupon_uso_reservacion FOREIGN KEY (id_reservacion)
        REFERENCES reservacion (id_reservacion),
    CONSTRAINT ck_cupon_uso_monto CHECK (monto_descuento > 0),
    CONSTRAINT ck_cupon_uso_estado CHECK (
        (estado = 'aplicado' AND devuelto_en IS NULL) OR (estado = 'devuelto' AND devuelto_en IS NOT NULL))
);

CREATE TRIGGER tr_cupon_uso_actualizado_en
    BEFORE UPDATE ON cupon_uso
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE VIEW vw_cupones_conciliacion AS
SELECT c.id_cupon,
       c.codigo,
       c.usos_actuales,
       COALESCE(u.aplicados, 0) AS usos_aplicados,
       c.usos_actuales - COALESCE(u.aplicados, 0) AS diferencia
  FROM cupon c
  LEFT JOIN (SELECT cu.id_cupon, count(*) AS aplicados
               FROM cupon_uso cu
              WHERE cu.estado = 'aplicado'
              GROUP BY cu.id_cupon) u ON u.id_cupon = c.id_cupon;

INSERT INTO version_esquema (script) VALUES ('006_reservaciones.sql');