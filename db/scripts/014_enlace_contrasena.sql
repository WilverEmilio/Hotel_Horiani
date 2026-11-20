CREATE TABLE enlace_contrasena (
    id_enlace_contrasena  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_usuario            BIGINT       NOT NULL,
    token_hash            VARCHAR(128) NOT NULL,
    tipo                  VARCHAR(20)  NOT NULL,
    expira_en             TIMESTAMPTZ  NOT NULL,
    usado_en              TIMESTAMPTZ,
    revocado_en           TIMESTAMPTZ,
    creado_por            BIGINT,
    creado_en             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_enlace_contrasena PRIMARY KEY (id_enlace_contrasena),
    CONSTRAINT uq_enlace_contrasena_hash UNIQUE (token_hash),
    CONSTRAINT fk_enlace_contrasena_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario),
    CONSTRAINT fk_enlace_contrasena_creado_por FOREIGN KEY (creado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_enlace_contrasena_tipo CHECK (tipo IN ('definir', 'recuperar')),
    CONSTRAINT ck_enlace_contrasena_expira CHECK (expira_en > creado_en),
    CONSTRAINT ck_enlace_contrasena_uso CHECK (usado_en IS NULL OR revocado_en IS NULL)
);

CREATE INDEX ix_enlace_contrasena_usuario ON enlace_contrasena (id_usuario) WHERE usado_en IS NULL AND revocado_en IS NULL;
CREATE INDEX ix_enlace_contrasena_creado_por ON enlace_contrasena (creado_por);

INSERT INTO version_esquema (script) VALUES ('014_enlace_contrasena.sql');