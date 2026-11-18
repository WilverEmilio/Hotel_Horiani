-- =============================================================================
-- 010_bitacora_contenido.sql
-- Bitácora (RN-11) y contenido editable de la página web (RN-12).
-- =============================================================================

CREATE TABLE bitacora (
    id_bitacora     BIGINT GENERATED ALWAYS AS IDENTITY,
    id_usuario      BIGINT,
    id_hotel        BIGINT,
    modulo          VARCHAR(40)  NOT NULL,
    entidad         VARCHAR(60)  NOT NULL,
    id_registro     VARCHAR(60)  NOT NULL,
    accion          VARCHAR(15)  NOT NULL,
    valor_anterior  JSONB,
    valor_nuevo     JSONB,
    direccion_ip    INET,
    creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_bitacora PRIMARY KEY (id_bitacora),
    CONSTRAINT fk_bitacora_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario),
    CONSTRAINT fk_bitacora_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT ck_bitacora_accion CHECK (accion IN ('crear', 'modificar', 'desactivar', 'cambio_estado')),
    CONSTRAINT ck_bitacora_valores CHECK (
        (accion = 'crear' AND valor_anterior IS NULL AND valor_nuevo IS NOT NULL)
        OR (accion IN ('modificar', 'desactivar', 'cambio_estado') AND valor_anterior IS NOT NULL))
);

CREATE TRIGGER tr_bitacora_inmutable
    BEFORE UPDATE OR DELETE ON bitacora
    FOR EACH ROW EXECUTE FUNCTION tg_comun_bloquear_cambios();

CREATE TRIGGER tr_bitacora_sin_truncate
    BEFORE TRUNCATE ON bitacora
    FOR EACH STATEMENT EXECUTE FUNCTION tg_comun_bloquear_cambios();


CREATE TABLE contenido_web (
    id_contenido_web  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_hotel          BIGINT,
    pagina            VARCHAR(60)  NOT NULL,
    seccion           VARCHAR(60)  NOT NULL,
    clave             VARCHAR(60)  NOT NULL,
    tipo              VARCHAR(15)  NOT NULL,
    valor             JSONB        NOT NULL,
    orden             INTEGER      NOT NULL DEFAULT 0,
    publicado         BOOLEAN      NOT NULL DEFAULT TRUE,
    actualizado_por   BIGINT       NOT NULL,
    creado_en         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_contenido_web PRIMARY KEY (id_contenido_web),
    CONSTRAINT uq_contenido_web UNIQUE NULLS NOT DISTINCT (id_hotel, pagina, seccion, clave),
    CONSTRAINT fk_contenido_web_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT fk_contenido_web_usuario FOREIGN KEY (actualizado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_contenido_web_tipo CHECK (tipo IN ('texto', 'texto_largo', 'imagen', 'lista')),
    CONSTRAINT ck_contenido_web_orden CHECK (orden >= 0)
);

CREATE TRIGGER tr_contenido_web_actualizado_en
    BEFORE UPDATE ON contenido_web
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE TABLE hotel_imagen (
    id_hotel_imagen    BIGINT GENERATED ALWAYS AS IDENTITY,
    id_hotel           BIGINT        NOT NULL,
    url                VARCHAR(500)  NOT NULL,
    texto_alternativo  VARCHAR(200),
    seccion            VARCHAR(30)   NOT NULL DEFAULT 'galeria',
    orden              INTEGER       NOT NULL DEFAULT 0,
    activo             BOOLEAN       NOT NULL DEFAULT TRUE,
    creado_en          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT pk_hotel_imagen PRIMARY KEY (id_hotel_imagen),
    CONSTRAINT fk_hotel_imagen_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT ck_hotel_imagen_seccion CHECK (seccion IN ('carrusel', 'galeria')),
    CONSTRAINT ck_hotel_imagen_orden CHECK (orden >= 0)
);

INSERT INTO version_esquema (script) VALUES ('010_bitacora_contenido.sql');