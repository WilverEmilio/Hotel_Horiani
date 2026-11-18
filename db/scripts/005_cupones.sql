-- =============================================================================
-- 005_cupones.sql
-- Cupones (RN-05). No existe módulo de promociones.
-- =============================================================================

CREATE TABLE cupon (
    id_cupon             BIGINT GENERATED ALWAYS AS IDENTITY,
    codigo               CITEXT         NOT NULL,
    descripcion          VARCHAR(200),
    tipo                 VARCHAR(15)    NOT NULL,
    valor                DECIMAL(10,2)  NOT NULL,
    vigencia             DATERANGE      NOT NULL,
    monto_minimo         DECIMAL(10,2)  NOT NULL DEFAULT 0,
    limite_usos_total    INTEGER,
    limite_usos_cliente  INTEGER,
    usos_actuales        INTEGER        NOT NULL DEFAULT 0,
    id_hotel             BIGINT,
    id_tipo_habitacion   BIGINT,
    creado_por           BIGINT         NOT NULL,
    activo               BOOLEAN        NOT NULL DEFAULT TRUE,
    creado_en            TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_cupon PRIMARY KEY (id_cupon),
    CONSTRAINT uq_cupon_codigo UNIQUE (codigo),
    CONSTRAINT fk_cupon_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT fk_cupon_tipo_habitacion FOREIGN KEY (id_tipo_habitacion)
        REFERENCES tipo_habitacion (id_tipo_habitacion),
    CONSTRAINT fk_cupon_usuario FOREIGN KEY (creado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_cupon_codigo CHECK (codigo ~ '^[A-Za-z0-9_-]{3,30}$'),
    CONSTRAINT ck_cupon_tipo CHECK (tipo IN ('porcentaje', 'monto_fijo')),
    CONSTRAINT ck_cupon_valor CHECK (valor > 0),
    CONSTRAINT ck_cupon_porcentaje CHECK (tipo <> 'porcentaje' OR valor <= 100),
    CONSTRAINT ck_cupon_vigencia CHECK (
        NOT isempty(vigencia) AND NOT lower_inf(vigencia) AND NOT upper_inf(vigencia)),
    CONSTRAINT ck_cupon_monto_minimo CHECK (monto_minimo >= 0),
    CONSTRAINT ck_cupon_limite_total CHECK (limite_usos_total IS NULL OR limite_usos_total > 0),
    CONSTRAINT ck_cupon_limite_cliente CHECK (limite_usos_cliente IS NULL OR limite_usos_cliente > 0),
    CONSTRAINT ck_cupon_usos CHECK (
        usos_actuales >= 0 AND (limite_usos_total IS NULL OR usos_actuales <= limite_usos_total))
);

CREATE TRIGGER tr_cupon_actualizado_en
    BEFORE UPDATE ON cupon
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

INSERT INTO version_esquema (script) VALUES ('005_cupones.sql');