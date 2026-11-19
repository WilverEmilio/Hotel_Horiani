-- =============================================================================
-- 007_pagos.sql
-- Pagos y notificaciones de la pasarela (RN-04).
-- =============================================================================

CREATE TABLE pago (
    id_pago              BIGINT GENERATED ALWAYS AS IDENTITY,
    id_reservacion       BIGINT         NOT NULL,
    tipo                 VARCHAR(10)    NOT NULL,
    metodo               VARCHAR(20)    NOT NULL,
    monto                DECIMAL(10,2)  NOT NULL,
    estado               VARCHAR(10)    NOT NULL DEFAULT 'pendiente',
    llave_idempotencia   UUID           NOT NULL,
    pasarela             VARCHAR(30),
    referencia_pasarela  VARCHAR(120),
    id_pago_origen       BIGINT,
    registrado_por       BIGINT,
    confirmado_en        TIMESTAMPTZ,
    creado_en            TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_pago PRIMARY KEY (id_pago),
    CONSTRAINT uq_pago_idempotencia UNIQUE (llave_idempotencia),
    CONSTRAINT uq_pago_referencia UNIQUE (pasarela, referencia_pasarela),
    CONSTRAINT fk_pago_reservacion FOREIGN KEY (id_reservacion) REFERENCES reservacion (id_reservacion),
    CONSTRAINT fk_pago_origen FOREIGN KEY (id_pago_origen) REFERENCES pago (id_pago),
    CONSTRAINT fk_pago_usuario FOREIGN KEY (registrado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_pago_tipo CHECK (tipo IN ('anticipo', 'saldo', 'reembolso')),
    CONSTRAINT ck_pago_metodo CHECK (metodo IN ('pasarela', 'efectivo', 'tarjeta_en_hotel')),
    CONSTRAINT ck_pago_monto CHECK (monto > 0),
    CONSTRAINT ck_pago_estado CHECK (estado IN ('pendiente', 'aprobado', 'rechazado', 'expirado', 'anulado')),
    CONSTRAINT ck_pago_pasarela CHECK (metodo <> 'pasarela' OR pasarela IS NOT NULL),
    CONSTRAINT ck_pago_en_hotel CHECK (metodo = 'pasarela' OR registrado_por IS NOT NULL),
    CONSTRAINT ck_pago_reembolso CHECK ((tipo = 'reembolso') = (id_pago_origen IS NOT NULL)),
    CONSTRAINT ck_pago_confirmado CHECK (estado <> 'aprobado' OR confirmado_en IS NOT NULL)
);

CREATE UNIQUE INDEX uq_pago_anticipo_aprobado
    ON pago (id_reservacion)
    WHERE tipo = 'anticipo' AND estado = 'aprobado';

CREATE TRIGGER tr_pago_actualizado_en
    BEFORE UPDATE ON pago
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE TRIGGER tr_pago_no_eliminar
    BEFORE DELETE ON pago
    FOR EACH ROW EXECUTE FUNCTION tg_comun_no_eliminar();
CREATE OR REPLACE FUNCTION tg_pago_proteger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF (NEW.id_reservacion, NEW.tipo, NEW.metodo, NEW.monto, NEW.llave_idempotencia, NEW.id_pago_origen,
        NEW.registrado_por)
       IS DISTINCT FROM
       (OLD.id_reservacion, OLD.tipo, OLD.metodo, OLD.monto, OLD.llave_idempotencia, OLD.id_pago_origen,
        OLD.registrado_por) THEN
        RAISE EXCEPTION 'El monto y los datos de un pago no pueden modificarse'
            USING ERRCODE = 'restrict_violation';
    END IF;

    IF NEW.estado IS DISTINCT FROM OLD.estado
       AND NOT (OLD.estado = 'pendiente'
                OR (OLD.estado = 'expirado' AND NEW.estado IN ('anulado', 'rechazado'))
                OR (OLD.estado = 'aprobado' AND NEW.estado = 'anulado')) THEN
        RAISE EXCEPTION 'Un pago en estado % no puede pasar a %', OLD.estado, NEW.estado
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tr_pago_proteger
    BEFORE UPDATE ON pago
    FOR EACH ROW EXECUTE FUNCTION tg_pago_proteger();

CREATE TABLE evento_pasarela (
    id_evento_pasarela  BIGINT GENERATED ALWAYS AS IDENTITY,
    pasarela            VARCHAR(30)   NOT NULL,
    id_evento_externo   VARCHAR(120)  NOT NULL,
    tipo                VARCHAR(80)   NOT NULL,
    contenido           JSONB         NOT NULL,
    id_pago             BIGINT,
    procesado_en        TIMESTAMPTZ,
    creado_en           TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT pk_evento_pasarela PRIMARY KEY (id_evento_pasarela),
    CONSTRAINT uq_evento_pasarela UNIQUE (pasarela, id_evento_externo),
    CONSTRAINT fk_evento_pasarela_pago FOREIGN KEY (id_pago) REFERENCES pago (id_pago)
);

INSERT INTO version_esquema (script) VALUES ('007_pagos.sql'); 