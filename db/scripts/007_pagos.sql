-- =============================================================================
-- 007_pagos.sql
-- Pagos y notificaciones de la pasarela (RN-04).
-- =============================================================================

-- Anticipo en línea, saldo en el hotel y reembolsos. Un pago no se corrige
-- editándolo: un reembolso es otra fila que apunta al pago original.
-- No se guarda ningún dato de tarjeta.
CREATE TABLE pago (
    id_pago              BIGINT GENERATED ALWAYS AS IDENTITY,
    id_reservacion       BIGINT         NOT NULL,
    tipo                 VARCHAR(10)    NOT NULL,
    metodo               VARCHAR(20)    NOT NULL,
    monto                DECIMAL(10,2)  NOT NULL,
    estado               VARCHAR(10)    NOT NULL DEFAULT 'pendiente',
    -- Repetir la petición con la misma llave (doble clic, reintento por mala
    -- conexión) devuelve el pago existente en vez de cobrar otra vez.
    llave_idempotencia   UUID           NOT NULL,
    -- Nombre de la pasarela ('bac', 'visanet', 'simulada') y su identificador.
    pasarela             VARCHAR(30),
    referencia_pasarela  VARCHAR(120),
    id_pago_origen       BIGINT,
    -- Empleado que registró el cobro en el hotel. NULL en pagos en línea.
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
    CONSTRAINT ck_pago_estado CHECK (estado IN ('pendiente', 'aprobado', 'rechazado')),
    CONSTRAINT ck_pago_pasarela CHECK (metodo <> 'pasarela' OR pasarela IS NOT NULL),
    CONSTRAINT ck_pago_en_hotel CHECK (metodo = 'pasarela' OR registrado_por IS NOT NULL),
    CONSTRAINT ck_pago_reembolso CHECK ((tipo = 'reembolso') = (id_pago_origen IS NOT NULL)),
    CONSTRAINT ck_pago_confirmado CHECK (estado <> 'aprobado' OR confirmado_en IS NOT NULL)
);

-- Una reservación solo puede tener un anticipo aprobado.
CREATE UNIQUE INDEX uq_pago_anticipo_aprobado
    ON pago (id_reservacion)
    WHERE tipo = 'anticipo' AND estado = 'aprobado';

CREATE TRIGGER tr_pago_actualizado_en
    BEFORE UPDATE ON pago
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Notificaciones recibidas de la pasarela. La restricción única evita procesar
-- dos veces la misma notificación.
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
