-- =============================================================================
-- 011_indices.sql
-- Índices para llaves foráneas y para los listados y reportes principales.
-- Las llaves primarias, UNIQUE y EXCLUDE ya crean su propio índice.
-- =============================================================================

CREATE INDEX ix_usuario_rol ON usuario (id_rol);
CREATE INDEX ix_token_refresco_usuario ON token_refresco (id_usuario);
CREATE INDEX ix_token_refresco_familia ON token_refresco (id_familia);

CREATE INDEX ix_habitacion_tipo ON habitacion (id_tipo_habitacion);
CREATE INDEX ix_habitacion_hotel_estado ON habitacion (id_hotel, estado) WHERE activo;
CREATE INDEX ix_tipo_habitacion_imagen_tipo ON tipo_habitacion_imagen (id_tipo_habitacion, orden);
CREATE INDEX ix_tipo_habitacion_servicio_servicio ON tipo_habitacion_servicio (id_servicio);

CREATE INDEX ix_cliente_nombre ON cliente (apellidos, nombres);
CREATE INDEX ix_cliente_telefono ON cliente (telefono);
CREATE INDEX ix_empleado_hotel_hotel ON empleado_hotel (id_hotel);
CREATE INDEX ix_empleado_turno_turno ON empleado_turno (id_turno);
CREATE INDEX ix_asistencia_hotel_fecha ON asistencia (id_hotel, fecha);

CREATE INDEX ix_cupon_uso_cupon_cliente ON cupon_uso (id_cupon, id_cliente) WHERE estado = 'aplicado';
CREATE INDEX ix_cupon_uso_cliente ON cupon_uso (id_cliente);

CREATE INDEX ix_reservacion_cliente ON reservacion (id_cliente, creado_en DESC);
CREATE INDEX ix_reservacion_hotel_estado ON reservacion (id_hotel, estado, fecha_entrada);
CREATE INDEX ix_reservacion_hotel_fechas ON reservacion (id_hotel, fecha_entrada, fecha_salida);
CREATE INDEX ix_reservacion_cupon ON reservacion (id_cupon) WHERE id_cupon IS NOT NULL;
CREATE INDEX ix_reservacion_por_expirar ON reservacion (expira_en) WHERE estado = 'pendiente_pago';
CREATE INDEX ix_reservacion_habitacion_habitacion ON reservacion_habitacion (id_habitacion);
CREATE INDEX ix_reservacion_habitacion_tipo ON reservacion_habitacion (id_tipo_habitacion);
CREATE INDEX ix_reservacion_noche_fecha ON reservacion_noche (fecha, id_reservacion_habitacion);
CREATE INDEX ix_reservacion_hotel_creado ON reservacion (id_hotel, creado_en);
CREATE INDEX ix_reservacion_cancelada ON reservacion (id_hotel, cancelada_en) WHERE cancelada_en IS NOT NULL;
CREATE INDEX ix_reservacion_estado_historial_reservacion
    ON reservacion_estado_historial (id_reservacion, creado_en);

CREATE INDEX ix_pago_reservacion ON pago (id_reservacion);
CREATE INDEX ix_pago_confirmado ON pago (confirmado_en) WHERE estado = 'aprobado';
CREATE INDEX ix_pago_origen ON pago (id_pago_origen) WHERE id_pago_origen IS NOT NULL;

CREATE INDEX ix_articulo_hotel_clase ON articulo (id_hotel, clase) WHERE activo;
CREATE INDEX ix_articulo_categoria ON articulo (id_categoria_articulo);
CREATE INDEX ix_movimiento_inventario_articulo ON movimiento_inventario (id_articulo, creado_en DESC);
CREATE INDEX ix_movimiento_inventario_fecha ON movimiento_inventario (creado_en, id_articulo);
CREATE INDEX ix_movimiento_inventario_lote ON movimiento_inventario (id_lote_lavanderia)
    WHERE id_lote_lavanderia IS NOT NULL;
CREATE INDEX ix_lote_lavanderia_hotel_estado ON lote_lavanderia (id_hotel, estado);
CREATE INDEX ix_lote_lavanderia_detalle_articulo ON lote_lavanderia_detalle (id_articulo);

CREATE INDEX ix_tarea_limpieza_empleado ON tarea_limpieza (id_empleado_asignado, estado);
CREATE INDEX ix_reporte_mantenimiento_hotel_estado ON reporte_mantenimiento (id_hotel, estado);
CREATE INDEX ix_reporte_mantenimiento_habitacion ON reporte_mantenimiento (id_habitacion);

CREATE INDEX ix_bitacora_modulo ON bitacora (modulo, creado_en DESC);
CREATE INDEX ix_bitacora_usuario ON bitacora (id_usuario, creado_en DESC);
CREATE INDEX ix_bitacora_entidad ON bitacora (entidad, id_registro);
CREATE INDEX ix_bitacora_fecha ON bitacora (creado_en DESC);
CREATE INDEX ix_bitacora_hotel ON bitacora (id_hotel, creado_en DESC) WHERE id_hotel IS NOT NULL;
CREATE INDEX ix_hotel_imagen_hotel ON hotel_imagen (id_hotel, seccion, orden) WHERE activo;

INSERT INTO version_esquema (script) VALUES ('011_indices.sql');