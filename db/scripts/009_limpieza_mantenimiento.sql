-- =============================================================================
-- 009_limpieza_mantenimiento.sql
-- Tareas de limpieza, reportes de mantenimiento y bloqueos (RN-09).
-- =============================================================================

CREATE TABLE tarea_limpieza (
    id_tarea_limpieza     BIGINT GENERATED ALWAYS AS IDENTITY,
    id_habitacion         BIGINT       NOT NULL,
    id_reservacion        BIGINT,
    id_empleado_asignado  BIGINT,
    estado                VARCHAR(12)  NOT NULL DEFAULT 'pendiente',
    observacion           VARCHAR(300),
    completada_por        BIGINT,
    completada_en         TIMESTAMPTZ,
    creado_por            BIGINT,
    creado_en             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_tarea_limpieza PRIMARY KEY (id_tarea_limpieza),
    CONSTRAINT fk_tarea_limpieza_habitacion FOREIGN KEY (id_habitacion) REFERENCES habitacion (id_habitacion),
    CONSTRAINT fk_tarea_limpieza_reservacion FOREIGN KEY (id_reservacion)
        REFERENCES reservacion (id_reservacion),
    CONSTRAINT fk_tarea_limpieza_empleado FOREIGN KEY (id_empleado_asignado)
        REFERENCES empleado (id_empleado),
    CONSTRAINT fk_tarea_limpieza_completada_por FOREIGN KEY (completada_por) REFERENCES usuario (id_usuario),
    CONSTRAINT fk_tarea_limpieza_creado_por FOREIGN KEY (creado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_tarea_limpieza_estado CHECK (estado IN ('pendiente', 'en_proceso', 'completada')),
    CONSTRAINT ck_tarea_limpieza_completada CHECK (
        (estado = 'completada') = (completada_en IS NOT NULL AND completada_por IS NOT NULL))
);
CREATE UNIQUE INDEX uq_tarea_limpieza_abierta
    ON tarea_limpieza (id_habitacion)
    WHERE estado <> 'completada';

CREATE TRIGGER tr_tarea_limpieza_actualizado_en
    BEFORE UPDATE ON tarea_limpieza
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

CREATE TABLE reporte_mantenimiento (
    id_reporte_mantenimiento  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_hotel                  BIGINT       NOT NULL,
    id_habitacion             BIGINT,
    descripcion               TEXT         NOT NULL,
    estado                    VARCHAR(12)  NOT NULL DEFAULT 'reportado',
    reportado_por             BIGINT       NOT NULL,
    solucion                  TEXT,
    resuelto_por              BIGINT,
    resuelto_en               TIMESTAMPTZ,
    creado_en                 TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_reporte_mantenimiento PRIMARY KEY (id_reporte_mantenimiento),
    CONSTRAINT fk_reporte_mantenimiento_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT fk_reporte_mantenimiento_habitacion FOREIGN KEY (id_habitacion, id_hotel)
        REFERENCES habitacion (id_habitacion, id_hotel),
    CONSTRAINT fk_reporte_mantenimiento_reportado FOREIGN KEY (reportado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT fk_reporte_mantenimiento_resuelto FOREIGN KEY (resuelto_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_reporte_mantenimiento_estado CHECK (estado IN ('reportado', 'en_proceso', 'resuelto')),
    CONSTRAINT ck_reporte_mantenimiento_descripcion CHECK (length(btrim(descripcion)) > 0),
    CONSTRAINT ck_reporte_mantenimiento_resuelto CHECK (
        (estado = 'resuelto') = (resuelto_en IS NOT NULL AND resuelto_por IS NOT NULL))
);

CREATE TRIGGER tr_reporte_mantenimiento_actualizado_en
    BEFORE UPDATE ON reporte_mantenimiento
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();
CREATE TABLE bloqueo_habitacion (
    id_bloqueo_habitacion     BIGINT GENERATED ALWAYS AS IDENTITY,
    id_habitacion             BIGINT       NOT NULL,
    periodo                   DATERANGE    NOT NULL,
    motivo                    VARCHAR(300) NOT NULL,
    id_reporte_mantenimiento  BIGINT,
    creado_por                BIGINT       NOT NULL,
    activo                    BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en                 TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_bloqueo_habitacion PRIMARY KEY (id_bloqueo_habitacion),
    CONSTRAINT fk_bloqueo_habitacion_habitacion FOREIGN KEY (id_habitacion) REFERENCES habitacion (id_habitacion),
    CONSTRAINT fk_bloqueo_habitacion_reporte FOREIGN KEY (id_reporte_mantenimiento)
        REFERENCES reporte_mantenimiento (id_reporte_mantenimiento),
    CONSTRAINT fk_bloqueo_habitacion_usuario FOREIGN KEY (creado_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_bloqueo_habitacion_periodo CHECK (NOT isempty(periodo) AND NOT lower_inf(periodo)),
    CONSTRAINT ex_bloqueo_habitacion_traslape EXCLUDE USING gist
        (id_habitacion WITH =, periodo WITH &&) WHERE (activo)
);

CREATE TRIGGER tr_bloqueo_habitacion_actualizado_en
    BEFORE UPDATE ON bloqueo_habitacion
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

INSERT INTO version_esquema (script) VALUES ('009_limpieza_mantenimiento.sql');