-- =============================================================================
-- 008_inventario_lavanderia.sql
-- Insumos consumibles, blancos reutilizables y lavandería (RN-08).
-- Cada hotel tiene su propio inventario; no hay traslados entre hoteles.
-- =============================================================================

CREATE TABLE categoria_articulo (
    id_categoria_articulo  BIGINT GENERATED ALWAYS AS IDENTITY,
    nombre                 VARCHAR(80)  NOT NULL,
    activo                 BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_categoria_articulo PRIMARY KEY (id_categoria_articulo),
    CONSTRAINT uq_categoria_articulo_nombre UNIQUE (nombre)
);

-- clase 'insumo': se consume (jabón, papel, cloro, desinfectante).
-- clase 'blanco': se reutiliza y circula (toallas, sábanas, fundas).
CREATE TABLE articulo (
    id_articulo            BIGINT GENERATED ALWAYS AS IDENTITY,
    id_hotel               BIGINT         NOT NULL,
    id_categoria_articulo  BIGINT         NOT NULL,
    nombre                 VARCHAR(120)   NOT NULL,
    clase                  VARCHAR(10)    NOT NULL,
    unidad_medida          VARCHAR(20)    NOT NULL,
    existencia_minima      DECIMAL(12,2)  NOT NULL DEFAULT 0,
    activo                 BOOLEAN        NOT NULL DEFAULT TRUE,
    creado_en              TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en         TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_articulo PRIMARY KEY (id_articulo),
    CONSTRAINT uq_articulo_hotel_nombre UNIQUE (id_hotel, nombre),
    CONSTRAINT uq_articulo_id_hotel UNIQUE (id_articulo, id_hotel),
    CONSTRAINT fk_articulo_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT fk_articulo_categoria FOREIGN KEY (id_categoria_articulo)
        REFERENCES categoria_articulo (id_categoria_articulo),
    CONSTRAINT ck_articulo_clase CHECK (clase IN ('insumo', 'blanco')),
    CONSTRAINT ck_articulo_minima CHECK (existencia_minima >= 0)
);

CREATE TRIGGER tr_articulo_actualizado_en
    BEFORE UPDATE ON articulo
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Cantidad actual por ubicación. Los insumos solo usan 'bodega'; los blancos
-- circulan entre bodega, habitaciones y lavandería. Solo cambia a través de
-- movimiento_inventario (lo hace el stored procedure en la misma transacción).
CREATE TABLE existencia (
    id_articulo     BIGINT         NOT NULL,
    ubicacion       VARCHAR(15)    NOT NULL,
    cantidad        DECIMAL(12,2)  NOT NULL DEFAULT 0,
    actualizado_en  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_existencia PRIMARY KEY (id_articulo, ubicacion),
    CONSTRAINT fk_existencia_articulo FOREIGN KEY (id_articulo) REFERENCES articulo (id_articulo),
    CONSTRAINT ck_existencia_ubicacion CHECK (ubicacion IN ('bodega', 'habitaciones', 'lavanderia')),
    -- La existencia nunca queda negativa.
    CONSTRAINT ck_existencia_cantidad CHECK (cantidad >= 0)
);

CREATE TRIGGER tr_existencia_actualizado_en
    BEFORE UPDATE ON existencia
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Lote de blancos que lavandería recibe y luego devuelve.
CREATE TABLE lote_lavanderia (
    id_lote_lavanderia  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_hotel            BIGINT       NOT NULL,
    estado              VARCHAR(10)  NOT NULL DEFAULT 'recibido',
    recibido_por        BIGINT       NOT NULL,
    recibido_en         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    devuelto_por        BIGINT,
    devuelto_en         TIMESTAMPTZ,
    observacion         VARCHAR(300),
    creado_en           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_lote_lavanderia PRIMARY KEY (id_lote_lavanderia),
    CONSTRAINT uq_lote_lavanderia_id_hotel UNIQUE (id_lote_lavanderia, id_hotel),
    CONSTRAINT fk_lote_lavanderia_hotel FOREIGN KEY (id_hotel) REFERENCES hotel (id_hotel),
    CONSTRAINT fk_lote_lavanderia_recibido FOREIGN KEY (recibido_por) REFERENCES usuario (id_usuario),
    CONSTRAINT fk_lote_lavanderia_devuelto FOREIGN KEY (devuelto_por) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_lote_lavanderia_estado CHECK (estado IN ('recibido', 'devuelto')),
    CONSTRAINT ck_lote_lavanderia_devolucion CHECK (
        (estado = 'devuelto') = (devuelto_en IS NOT NULL AND devuelto_por IS NOT NULL))
);

CREATE TRIGGER tr_lote_lavanderia_actualizado_en
    BEFORE UPDATE ON lote_lavanderia
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Faltante = cantidad_recibida - cantidad_devuelta. Al cerrar el lote, el
-- faltante genera un movimiento de baja con su responsable.
CREATE TABLE lote_lavanderia_detalle (
    id_lote_lavanderia_detalle  BIGINT GENERATED ALWAYS AS IDENTITY,
    id_lote_lavanderia          BIGINT         NOT NULL,
    id_hotel                    BIGINT         NOT NULL,
    id_articulo                 BIGINT         NOT NULL,
    cantidad_recibida           DECIMAL(12,2)  NOT NULL,
    cantidad_devuelta           DECIMAL(12,2),
    creado_en                   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en              TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_lote_lavanderia_detalle PRIMARY KEY (id_lote_lavanderia_detalle),
    CONSTRAINT uq_lote_lavanderia_detalle UNIQUE (id_lote_lavanderia, id_articulo),
    -- Llaves compuestas: el artículo debe ser del mismo hotel que el lote.
    CONSTRAINT fk_lote_lavanderia_detalle_lote FOREIGN KEY (id_lote_lavanderia, id_hotel)
        REFERENCES lote_lavanderia (id_lote_lavanderia, id_hotel),
    CONSTRAINT fk_lote_lavanderia_detalle_articulo FOREIGN KEY (id_articulo, id_hotel)
        REFERENCES articulo (id_articulo, id_hotel),
    CONSTRAINT ck_lote_lavanderia_detalle_recibida CHECK (cantidad_recibida > 0),
    CONSTRAINT ck_lote_lavanderia_detalle_devuelta CHECK (
        cantidad_devuelta IS NULL OR (cantidad_devuelta >= 0 AND cantidad_devuelta <= cantidad_recibida))
);

CREATE TRIGGER tr_lote_lavanderia_detalle_actualizado_en
    BEFORE UPDATE ON lote_lavanderia_detalle
    FOR EACH ROW EXECUTE FUNCTION tg_comun_actualizado_en();

-- Única vía para cambiar una existencia. Tabla de solo inserción: un error se
-- corrige con otro movimiento, nunca editando o borrando.
--   entrada / ajuste_positivo ........ solo destino
--   salida / ajuste_negativo / baja .. solo origen
--   traslado ......................... origen y destino distintos
CREATE TABLE movimiento_inventario (
    id_movimiento_inventario     BIGINT GENERATED ALWAYS AS IDENTITY,
    id_articulo                  BIGINT         NOT NULL,
    tipo                         VARCHAR(20)    NOT NULL,
    ubicacion_origen             VARCHAR(15),
    ubicacion_destino            VARCHAR(15),
    cantidad                     DECIMAL(12,2)  NOT NULL,
    -- Existencia que quedó en cada ubicación después del movimiento.
    existencia_resultante_origen   DECIMAL(12,2),
    existencia_resultante_destino  DECIMAL(12,2),
    motivo                       VARCHAR(300),
    id_habitacion                BIGINT,
    id_lote_lavanderia           BIGINT,
    id_usuario                   BIGINT         NOT NULL,
    creado_en                    TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT pk_movimiento_inventario PRIMARY KEY (id_movimiento_inventario),
    CONSTRAINT fk_movimiento_inventario_articulo FOREIGN KEY (id_articulo) REFERENCES articulo (id_articulo),
    CONSTRAINT fk_movimiento_inventario_habitacion FOREIGN KEY (id_habitacion)
        REFERENCES habitacion (id_habitacion),
    CONSTRAINT fk_movimiento_inventario_lote FOREIGN KEY (id_lote_lavanderia)
        REFERENCES lote_lavanderia (id_lote_lavanderia),
    CONSTRAINT fk_movimiento_inventario_usuario FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario),
    CONSTRAINT ck_movimiento_inventario_tipo CHECK (tipo IN
        ('entrada', 'salida', 'ajuste_positivo', 'ajuste_negativo', 'traslado', 'baja')),
    CONSTRAINT ck_movimiento_inventario_origen CHECK (ubicacion_origen IS NULL
        OR ubicacion_origen IN ('bodega', 'habitaciones', 'lavanderia')),
    CONSTRAINT ck_movimiento_inventario_destino CHECK (ubicacion_destino IS NULL
        OR ubicacion_destino IN ('bodega', 'habitaciones', 'lavanderia')),
    CONSTRAINT ck_movimiento_inventario_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_movimiento_inventario_ubicaciones CHECK (
        (tipo IN ('entrada', 'ajuste_positivo')
            AND ubicacion_origen IS NULL AND ubicacion_destino IS NOT NULL)
        OR (tipo IN ('salida', 'ajuste_negativo', 'baja')
            AND ubicacion_origen IS NOT NULL AND ubicacion_destino IS NULL)
        OR (tipo = 'traslado'
            AND ubicacion_origen IS NOT NULL AND ubicacion_destino IS NOT NULL
            AND ubicacion_origen <> ubicacion_destino)),
    CONSTRAINT ck_movimiento_inventario_resultantes CHECK (
        (ubicacion_origen IS NULL) = (existencia_resultante_origen IS NULL)
        AND (ubicacion_destino IS NULL) = (existencia_resultante_destino IS NULL)
        AND COALESCE(existencia_resultante_origen, 0) >= 0
        AND COALESCE(existencia_resultante_destino, 0) >= 0),
    -- Ajustes y bajas exigen motivo escrito.
    CONSTRAINT ck_movimiento_inventario_motivo CHECK (
        tipo NOT IN ('ajuste_positivo', 'ajuste_negativo', 'baja')
        OR length(btrim(COALESCE(motivo, ''))) > 0)
);

CREATE TRIGGER tr_movimiento_inventario_inmutable
    BEFORE UPDATE OR DELETE ON movimiento_inventario
    FOR EACH ROW EXECUTE FUNCTION tg_comun_bloquear_cambios();

CREATE TRIGGER tr_movimiento_inventario_sin_truncate
    BEFORE TRUNCATE ON movimiento_inventario
    FOR EACH STATEMENT EXECUTE FUNCTION tg_comun_bloquear_cambios();
