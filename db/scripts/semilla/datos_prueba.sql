-- =============================================================================
-- semilla/datos_prueba.sql
-- DATOS DE PRUEBA. No usar en producción (090_semilla.sh solo lo carga con
-- CARGAR_DATOS_PRUEBA=true).
--
-- Tomado de la página web actual: tipos de habitación, descripciones,
-- servicios, imágenes y valores del hotel.
-- Inventado para pruebas (reemplazar con datos reales del cliente):
-- nombres y direcciones de las sedes 2 a 4, precios, personal, clientes,
-- inventario y todo el historial de reservaciones.
--
-- Contenido:
--   * 4 hoteles: el principal (Quetzaltenango) con 22 habitaciones y 3 sedes
--     con 8 cada una.
--   * Turnos A (08-13), B (13-15), C (15-18), D (18-08) en cada hotel.
--   * Usuarios de prueba, uno por rol (contraseña: la pone el backend).
--   * ~400 clientes y reservaciones desde hace 180 días hasta dentro de 60,
--     con pagos, cancelaciones, no presentaciones, vencidas y cupones.
--   * Asistencia de los últimos 30 días, inventario, lavandería, limpieza,
--     mantenimiento y contenido web.
-- Los catálogos se crean con los stored procedures (quedan en bitácora). El
-- historial se inserta directo, porque los SP no permiten fechas pasadas,
-- respetando todas las restricciones del modelo.
-- Fechas relativas al día de la carga. Aleatorio con semilla fija: dos
-- cargas el mismo día dan los mismos datos.
-- =============================================================================
SET client_min_messages = warning;
SELECT setseed(0.2026);

INSERT INTO usuario (correo, contrasena_hash, id_rol)
SELECT u.correo, NULL, r.id_rol
  FROM (VALUES ('admin@horiani.test', 'administrador'),
               ('oficinista@horiani.test', 'oficinista'),
               ('recepcion@horiani.test', 'operador'),
               ('recepcion2@horiani.test', 'operador'),
               ('limpieza@horiani.test', 'limpieza'),
               ('lavanderia@horiani.test', 'lavanderia'),
               ('recepcion.sede2@horiani.test', 'operador'),
               ('recepcion.sede3@horiani.test', 'operador'),
               ('recepcion.sede4@horiani.test', 'operador'),
               ('cliente@horiani.test', 'cliente')) AS u (correo, rol)
  JOIN rol r ON r.nombre = u.rol;

DO $$
DECLARE
    v_admin  BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@horiani.test');
    v_hotel  BIGINT;
    v_tipo   BIGINT;
    v_wifi   BIGINT; v_banio BIGINT; v_tv BIGINT; v_sala BIGINT;
    v_n      INTEGER;
    r        RECORD;
BEGIN
    v_wifi  := sp_servicios_crear(v_admin, 'WiFi', 'ti-wifi');
    v_banio := sp_servicios_crear(v_admin, 'Baño privado', 'ti-bath');
    v_tv    := sp_servicios_crear(v_admin, 'TV por cable', 'ti-device-tv');
    v_sala  := sp_servicios_crear(v_admin, 'Sala de estar', 'ti-sofa');

    FOR r IN
        SELECT * FROM (VALUES
            (1, 'Hotel Horiani', 'horiani-quetzaltenango', 'Zona 1, Quetzaltenango', 'Quetzaltenango', 10, 8, 4),
            (2, 'Hotel Horiani Sede 2', 'horiani-sede-2', 'Dirección por definir', 'Por definir', 4, 3, 1),
            (3, 'Hotel Horiani Sede 3', 'horiani-sede-3', 'Dirección por definir', 'Por definir', 4, 3, 1),
            (4, 'Hotel Horiani Sede 4', 'horiani-sede-4', 'Dirección por definir', 'Por definir', 4, 3, 1)
        ) AS h (orden, nombre, slug, direccion, ciudad, n_ind, n_dob, n_sui)
        ORDER BY orden
    LOOP
        v_hotel := sp_hoteles_crear(v_admin, r.nombre, r.slug, r.direccion, r.ciudad, '7700-000' || r.orden,
                                    'reservas' || r.orden || '@horiani.test');

        v_tipo := sp_habitaciones_crear_tipo(v_admin, v_hotel, 'Individual',
            'Perfecta para viajeros solos. Cama individual, baño privado y WiFi gratuito incluido.', 1, 85.00);
        PERFORM sp_habitaciones_asignar_servicios(v_admin, v_tipo, ARRAY[v_wifi, v_banio, v_tv]);
        FOR v_n IN 1 .. r.n_ind LOOP
            PERFORM sp_habitaciones_crear(v_admin, v_hotel, v_tipo, (100 + v_n)::text, 1);
        END LOOP;
        IF r.orden = 1 THEN
            PERFORM sp_habitaciones_agregar_imagen(v_admin, v_tipo, '/images/Gallery/pasillo1.jpeg', 'Habitación individual');
            PERFORM sp_habitaciones_agregar_imagen(v_admin, v_tipo, '/images/Gallery/pasillo4.jpeg', 'Pasillo del hotel');
        END IF;

        v_tipo := sp_habitaciones_crear_tipo(v_admin, v_hotel, 'Doble',
            'Ideal para parejas o compañeros de viaje. Dos camas, baño privado y vista a la ciudad.', 2, 150.00);
        PERFORM sp_habitaciones_asignar_servicios(v_admin, v_tipo, ARRAY[v_wifi, v_banio, v_tv]);
        FOR v_n IN 1 .. r.n_dob LOOP
            PERFORM sp_habitaciones_crear(v_admin, v_hotel, v_tipo, (200 + v_n)::text, 2);
        END LOOP;
        IF r.orden = 1 THEN
            PERFORM sp_habitaciones_agregar_imagen(v_admin, v_tipo, '/images/Gallery/pasillo2.jpeg', 'Habitación doble');

            PERFORM sp_habitaciones_crear_tarifa_especial(v_admin, v_tipo, 'Fin de año',
                make_date(extract(year FROM interno.sp_comun_hoy())::int, 12, 24),
                make_date(extract(year FROM interno.sp_comun_hoy())::int, 12, 31), 200.00);
        END IF;

        v_tipo := sp_habitaciones_crear_tipo(v_admin, v_hotel, 'Suite Ejecutiva',
            'Nuestra habitación más espaciosa. Sala de estar, escritorio y vista panorámica a Quetzaltenango.', 3, 300.00);
        PERFORM sp_habitaciones_asignar_servicios(v_admin, v_tipo, ARRAY[v_wifi, v_banio, v_tv, v_sala]);
        FOR v_n IN 1 .. r.n_sui LOOP
            PERFORM sp_habitaciones_crear(v_admin, v_hotel, v_tipo, (300 + v_n)::text, 3);
        END LOOP;
        IF r.orden = 1 THEN
            PERFORM sp_habitaciones_agregar_imagen(v_admin, v_tipo, '/images/Gallery/pasillo4.jpeg', 'Suite ejecutiva');
        END IF;

        PERFORM sp_turnos_crear(v_admin, v_hotel, 'Turno A', '08:00', '13:00');
        PERFORM sp_turnos_crear(v_admin, v_hotel, 'Turno B', '13:00', '15:00');
        PERFORM sp_turnos_crear(v_admin, v_hotel, 'Turno C', '15:00', '18:00');
        PERFORM sp_turnos_crear(v_admin, v_hotel, 'Turno D', '18:00', '08:00');
    END LOOP;

    PERFORM sp_cupones_crear(v_admin, 'BIENVENIDA10', '10 % para clientes nuevos', 'porcentaje', 10,
        interno.sp_comun_hoy() - 200, interno.sp_comun_hoy() + 90, 0, NULL, 1, NULL, NULL);
    PERFORM sp_cupones_crear(v_admin, 'XELA50', 'Q50 de descuento en el hotel principal', 'monto_fijo', 50,
        interno.sp_comun_hoy(), interno.sp_comun_hoy() + 60, 200, 100, 2, 1, NULL);
    PERFORM sp_cupones_crear(v_admin, 'NAVIDAD15', '15 % en diciembre', 'porcentaje', 15,
        make_date(extract(year FROM interno.sp_comun_hoy())::int, 12, 1),
        make_date(extract(year FROM interno.sp_comun_hoy())::int, 12, 31), 0, 50, 1, NULL, NULL);
END;
$$;

INSERT INTO empleado (id_usuario, nombres, apellidos, dpi, telefono, puesto, fecha_ingreso)
SELECT (SELECT id_usuario FROM usuario WHERE correo = e.correo), e.nombres, e.apellidos, e.dpi, e.telefono, e.puesto,
       interno.sp_comun_hoy() - 365
  FROM (VALUES
        ('admin@horiani.test',           'Gerardo',  'Ixcot',    '1000000000001', '5500-0001', 'Gerente general'),
        ('oficinista@horiani.test',      'Marta',    'Gómez',    '1000000000002', '5500-0002', 'Oficinista'),
        ('recepcion@horiani.test',       'Rosa',     'Tzoc',     '1000000000003', '5500-0003', 'Recepcionista'),
        ('recepcion2@horiani.test',      'Julio',    'Cifuentes','1000000000004', '5500-0004', 'Recepcionista'),
        ('limpieza@horiani.test',        'Luis',     'Paz',      '1000000000005', '5500-0005', 'Limpieza'),
        ('lavanderia@horiani.test',      'Lucía',    'Tum',      '1000000000006', '5500-0006', 'Lavandería'),
        ('recepcion.sede2@horiani.test', 'Ana',      'Chávez',   '1000000000007', '5500-0007', 'Recepcionista'),
        ('recepcion.sede3@horiani.test', 'Pedro',    'Sic',      '1000000000008', '5500-0008', 'Recepcionista'),
        ('recepcion.sede4@horiani.test', 'Carmen',   'Xol',      '1000000000009', '5500-0009', 'Recepcionista'),
        (NULL,                           'Mario',    'Coyoy',    '1000000000010', '5500-0010', 'Limpieza'),
        (NULL,                           'Elena',    'Batz',     '1000000000011', '5500-0011', 'Limpieza'),
        (NULL,                           'Tomás',    'Yax',      '1000000000012', '5500-0012', 'Mantenimiento')
       ) AS e (correo, nombres, apellidos, dpi, telefono, puesto);

INSERT INTO empleado_hotel (id_empleado, id_hotel)
SELECT e.id_empleado, h.id_hotel
  FROM empleado e
  JOIN hotel h ON CASE
        WHEN e.dpi = '1000000000001' THEN TRUE
        WHEN e.dpi = '1000000000007' THEN h.slug = 'horiani-sede-2'
        WHEN e.dpi = '1000000000008' THEN h.slug = 'horiani-sede-3'
        WHEN e.dpi = '1000000000009' THEN h.slug = 'horiani-sede-4'
        ELSE h.slug = 'horiani-quetzaltenango' END;

DO $$
DECLARE
    v_admin  BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@horiani.test');
    r        RECORD;
BEGIN
    FOR r IN
        SELECT e.id_empleado, t.id_turno
          FROM (VALUES ('1000000000002', 'Turno B'), ('1000000000002', 'Turno C'),
                       ('1000000000003', 'Turno A'), ('1000000000003', 'Turno B'),
                       ('1000000000004', 'Turno C'), ('1000000000004', 'Turno D'),
                       ('1000000000005', 'Turno A'), ('1000000000006', 'Turno A'),
                       ('1000000000010', 'Turno A'), ('1000000000011', 'Turno A'),
                       ('1000000000012', 'Turno A'),
                       ('1000000000007', 'Turno A'), ('1000000000008', 'Turno A'), ('1000000000009', 'Turno A')
               ) AS a (dpi, turno)
          JOIN empleado e ON e.dpi = a.dpi
          JOIN empleado_hotel eh ON eh.id_empleado = e.id_empleado
          JOIN turno t ON t.id_hotel = eh.id_hotel AND t.nombre = a.turno
    LOOP
        PERFORM sp_empleados_asignar_turno(v_admin, r.id_empleado, r.id_turno, interno.sp_comun_hoy() - 60);
    END LOOP;
END;
$$;

INSERT INTO asistencia (id_empleado, id_hotel, id_turno, fecha, estado, observacion, registrado_por)
SELECT et.id_empleado, et.id_hotel, et.id_turno, d.dia::date,
       CASE WHEN x.r < 0.86 THEN 'asistio' WHEN x.r < 0.94 THEN 'llegada_tarde' WHEN x.r < 0.97 THEN 'falto' ELSE 'permiso' END,
       CASE WHEN x.r >= 0.86 AND x.r < 0.94 THEN 'Llegó tarde' END,
       (SELECT id_usuario FROM usuario WHERE correo = 'oficinista@horiani.test')
  FROM empleado_turno et
  JOIN hotel h ON h.id_hotel = et.id_hotel AND h.slug = 'horiani-quetzaltenango'
 CROSS JOIN generate_series((interno.sp_comun_hoy() - 30)::timestamp, (interno.sp_comun_hoy() - 1)::timestamp, interval '1 day') d(dia)
 CROSS JOIN LATERAL (SELECT random() + 0 * et.id_empleado_turno + 0 * extract(day FROM d.dia) AS r) x;

INSERT INTO cliente (id_usuario, nombres, apellidos, telefono, tipo_documento, numero_documento, pais)
VALUES ((SELECT id_usuario FROM usuario WHERE correo = 'cliente@horiani.test'),
        'Cliente', 'De Prueba', '5555-0000', 'dpi', '2999999999999', 'Guatemala');

INSERT INTO usuario (correo, contrasena_hash, id_rol)
SELECT 'cliente' || g || '@correo.test', NULL, (SELECT id_rol FROM rol WHERE nombre = 'cliente')
  FROM generate_series(1, 80) g;

INSERT INTO cliente (id_usuario, nombres, apellidos, telefono, tipo_documento, numero_documento, pais)
SELECT CASE WHEN g <= 80 THEN (SELECT id_usuario FROM usuario WHERE correo = 'cliente' || g || '@correo.test') END,
       (ARRAY['José','María','Juan','Ana','Carlos','Lucía','Luis','Sofía','Miguel','Valeria','Pedro','Gabriela',
              'Jorge','Andrea','Diego','Fernanda','Ricardo','Paola','Fernando','Isabel'])[1 + (g * 7) % 20],
       (ARRAY['López','García','Pérez','Martínez','Hernández','González','Rodríguez','Ramírez','Morales','Castillo',
              'Ixcot','Tzul','Batz','Cifuentes','Chávez','Xicará','Coyoy','Sic','Rivera','Méndez'])[1 + (g * 13) % 20]
       || ' ' ||
       (ARRAY['Juárez','Barrios','Orozco','Reyes','Díaz','Velásquez','Monzón','Aguilar','Ortiz','Fuentes'])[1 + (g * 3) % 10],
       '5' || lpad((1000000 + g * 7919 % 9000000)::text, 7, '0'),
       CASE WHEN g % 9 = 0 THEN 'pasaporte' ELSE 'dpi' END,
       CASE WHEN g % 9 = 0 THEN 'P' || lpad(g::text, 7, '0') ELSE (3000000000000 + g)::text END,
       CASE WHEN g % 9 = 0 THEN (ARRAY['México','El Salvador','Estados Unidos','España','Honduras'])[1 + g % 5]
            ELSE 'Guatemala' END
  FROM generate_series(1, 400) g;

DO $$
DECLARE
    c_gt        CONSTANT TEXT := 'America/Guatemala';
    v_hoy       DATE := interno.sp_comun_hoy();
    v_inicio    DATE := interno.sp_comun_hoy() - 180;
    v_fin       DATE := interno.sp_comun_hoy() + 60;
    v_admin     BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@horiani.test');
    v_cupon     cupon%ROWTYPE;
    v_clientes  BIGINT[];
    v_hab       RECORD;
    v_recep     BIGINT;
    v_entrada   DATE;
    v_salida    DATE;
    v_estado    TEXT;
    v_r         DOUBLE PRECISION;
    v_creado    TIMESTAMPTZ;
    v_cancel    TIMESTAMPTZ;
    v_cliente   BIGINT;
    v_sub       NUMERIC;
    v_desc      NUMERIC;
    v_total     NUMERIC;
    v_base      NUMERIC;
    v_ant       NUMERIC;
    v_usa_cupon BOOLEAN;
    v_id        BIGINT;
    v_rh        BIGINT;
    v_pago      BIGINT;
    v_metodo    TEXT;
    v_paga_ant  BOOLEAN;
    v_huespedes INTEGER;
    v_gap_max   INTEGER;
BEGIN
    SELECT c.* INTO v_cupon FROM cupon c WHERE c.codigo = 'BIENVENIDA10';
    v_clientes := ARRAY(SELECT id_cliente FROM cliente ORDER BY id_cliente);

    FOR v_hab IN
        SELECT h.id_habitacion, h.id_hotel, h.id_tipo_habitacion, th.capacidad_maxima, ho.slug
          FROM habitacion h
          JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
          JOIN hotel ho ON ho.id_hotel = h.id_hotel
         ORDER BY h.id_habitacion
    LOOP
        v_gap_max := CASE WHEN v_hab.slug = 'horiani-quetzaltenango' THEN 3 ELSE 6 END;
        SELECT u.id_usuario INTO v_recep
          FROM empleado e JOIN empleado_hotel eh ON eh.id_empleado = e.id_empleado
          JOIN usuario u ON u.id_usuario = e.id_usuario JOIN rol ro ON ro.id_rol = u.id_rol
         WHERE eh.id_hotel = v_hab.id_hotel AND ro.nombre = 'operador'
         ORDER BY e.id_empleado LIMIT 1;

        v_entrada := v_inicio + floor(random() * 4)::int;
        WHILE v_entrada < v_fin LOOP
            v_salida := v_entrada + 1 + floor(random() * 4)::int;
            v_r := random();
            IF v_salida < v_hoy THEN
                v_estado := CASE WHEN v_r < 0.85 THEN 'finalizada' WHEN v_r < 0.93 THEN 'cancelada'
                                 WHEN v_r < 0.97 THEN 'no_presentado' ELSE 'expirada' END;
            ELSIF v_entrada <= v_hoy THEN
                v_estado := 'en_curso';
            ELSE
                v_estado := CASE WHEN v_r < 0.90 THEN 'confirmada' ELSE 'cancelada' END;
            END IF;

            v_creado := ((v_entrada - (1 + floor(random() * 30))::int)::timestamp + interval '8 hours'
                         + random() * interval '12 hours') AT TIME ZONE c_gt;
            IF v_creado > now() - interval '1 hour' THEN
                v_creado := now() - interval '1 hour' - random() * interval '5 hours';
            END IF;
            v_cliente := v_clientes[1 + floor(random() * array_length(v_clientes, 1))::int];
            v_huespedes := 1 + floor(random() * v_hab.capacidad_maxima)::int;

            SELECT sum(n.precio_noche) INTO v_sub
              FROM interno.sp_reservaciones_calcular_noches(v_hab.id_tipo_habitacion, v_entrada, v_salida) n;
            v_usa_cupon := random() < 0.06 AND v_estado <> 'expirada';
            v_desc  := CASE WHEN v_usa_cupon THEN round(v_sub * v_cupon.valor / 100, 2) ELSE 0 END;
            v_total := v_sub - v_desc;
            v_base  := round(v_total / 1.12, 2);
            v_ant   := ceil(v_total * 50) / 100;
            v_cancel := CASE WHEN v_estado = 'cancelada'
                             THEN least(v_creado + random() * ((v_entrada::timestamp AT TIME ZONE c_gt) - v_creado),
                                        now() - interval '10 minutes') END;

            v_id := nextval(pg_get_serial_sequence('reservacion', 'id_reservacion'));
            INSERT INTO reservacion (id_reservacion, codigo, id_hotel, id_cliente, fecha_entrada, fecha_salida, estado,
                                     origen, creado_por, subtotal, descuento, total, base_imponible, iva, monto_anticipo,
                                     id_cupon, codigo_cupon, expira_en, llave_idempotencia, checkin_en, checkout_en,
                                     cancelada_en, motivo_cancelacion, creado_en)
            OVERRIDING SYSTEM VALUE
            VALUES (v_id, 'HOR-' || to_char(v_creado AT TIME ZONE c_gt, 'YYYY') || '-' || lpad(v_id::text, 6, '0'),
                    v_hab.id_hotel, v_cliente, v_entrada, v_salida, v_estado,
                    (ARRAY['web', 'web', 'movil', 'recepcion'])[1 + floor(random() * 4)::int], v_admin,
                    v_sub, v_desc, v_total, v_base, v_total - v_base, v_ant,
                    CASE WHEN v_usa_cupon THEN v_cupon.id_cupon END, CASE WHEN v_usa_cupon THEN v_cupon.codigo END,
                    CASE WHEN v_estado = 'expirada' THEN v_creado + interval '15 minutes' END,
                    gen_random_uuid(),
                    CASE WHEN v_estado IN ('en_curso', 'finalizada')
                         THEN least((v_entrada::timestamp + interval '14 hours' + random() * interval '6 hours') AT TIME ZONE c_gt,
                                    now() - interval '30 minutes') END,
                    CASE WHEN v_estado = 'finalizada'
                         THEN (v_salida::timestamp + interval '9 hours' + random() * interval '2 hours') AT TIME ZONE c_gt END,
                    v_cancel,
                    CASE WHEN v_estado = 'cancelada'
                         THEN (ARRAY['Cambio de planes', 'Viaje cancelado', 'Encontró otra opción', 'Motivos de salud'])[1 + floor(random() * 4)::int] END,
                    v_creado);

            INSERT INTO reservacion_habitacion (id_reservacion, id_hotel, id_habitacion, id_tipo_habitacion, periodo,
                                                huespedes, subtotal, activa, creado_en)
            VALUES (v_id, v_hab.id_hotel, v_hab.id_habitacion, v_hab.id_tipo_habitacion,
                    daterange(v_entrada, v_salida, '[)'), v_huespedes, v_sub,
                    v_estado IN ('confirmada', 'en_curso'), v_creado)
            RETURNING id_reservacion_habitacion INTO v_rh;

            INSERT INTO reservacion_noche (id_reservacion_habitacion, fecha, precio_noche, id_tarifa_especial)
            SELECT v_rh, n.fecha, n.precio_noche, n.id_tarifa_especial
              FROM interno.sp_reservaciones_calcular_noches(v_hab.id_tipo_habitacion, v_entrada, v_salida) n;

            IF v_usa_cupon THEN
                INSERT INTO cupon_uso (id_cupon, id_cliente, id_reservacion, monto_descuento, estado, devuelto_en, creado_en)
                VALUES (v_cupon.id_cupon, v_cliente, v_id, v_desc,
                        CASE WHEN v_estado = 'cancelada' THEN 'devuelto' ELSE 'aplicado' END, v_cancel, v_creado);
            END IF;

            INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo, creado_en)
            VALUES (v_id, NULL, 'pendiente_pago', v_admin, 'Reservación creada', v_creado);
            v_paga_ant := v_estado IN ('confirmada', 'en_curso', 'finalizada', 'no_presentado')
                          OR (v_estado = 'cancelada' AND random() < 0.6);
            IF v_estado = 'expirada' THEN
                INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo, creado_en)
                VALUES (v_id, 'pendiente_pago', 'expirada', NULL, 'Venció el tiempo para pagar el anticipo', v_creado + interval '15 minutes');
            ELSIF v_paga_ant THEN
                INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo, creado_en)
                VALUES (v_id, 'pendiente_pago', 'confirmada', NULL, 'Anticipo aprobado', v_creado + interval '3 minutes');
            END IF;
            IF v_estado IN ('en_curso', 'finalizada') THEN
                INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo, creado_en)
                SELECT v_id, 'confirmada', 'en_curso', v_recep, 'Check-in', r.checkin_en FROM reservacion r WHERE r.id_reservacion = v_id;
            END IF;
            IF v_estado = 'finalizada' THEN
                INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo, creado_en)
                SELECT v_id, 'en_curso', 'finalizada', v_recep, 'Check-out', r.checkout_en FROM reservacion r WHERE r.id_reservacion = v_id;
            ELSIF v_estado = 'cancelada' THEN
                INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo, creado_en)
                SELECT v_id, CASE WHEN v_paga_ant THEN 'confirmada' ELSE 'pendiente_pago' END, 'cancelada',
                       COALESCE((SELECT c.id_usuario FROM cliente c WHERE c.id_cliente = v_cliente), v_recep),
                       r.motivo_cancelacion, v_cancel
                  FROM reservacion r WHERE r.id_reservacion = v_id;
            ELSIF v_estado = 'no_presentado' THEN
                INSERT INTO reservacion_estado_historial (id_reservacion, estado_anterior, estado_nuevo, id_usuario, motivo, creado_en)
                VALUES (v_id, 'confirmada', 'no_presentado', v_recep, 'El cliente no se presentó',
                        ((v_entrada + 1)::timestamp + interval '9 hours') AT TIME ZONE c_gt);
            END IF;

            IF v_paga_ant AND v_ant > 0 THEN
                v_metodo := CASE WHEN random() < 0.7 THEN 'pasarela' ELSE 'efectivo' END;
                INSERT INTO pago (id_reservacion, tipo, metodo, monto, estado, llave_idempotencia, pasarela,
                                  referencia_pasarela, registrado_por, confirmado_en, creado_en)
                VALUES (v_id, 'anticipo', v_metodo, v_ant, 'aprobado', gen_random_uuid(),
                        CASE WHEN v_metodo = 'pasarela' THEN 'simulada' END,
                        CASE WHEN v_metodo = 'pasarela' THEN 'SIM-' || v_id END,
                        CASE WHEN v_metodo <> 'pasarela' THEN v_recep END,
                        v_creado + interval '3 minutes', v_creado)
                RETURNING id_pago INTO v_pago;

                IF v_estado = 'finalizada' AND v_total - v_ant > 0 THEN
                    INSERT INTO pago (id_reservacion, tipo, metodo, monto, estado, llave_idempotencia, registrado_por,
                                      confirmado_en, creado_en)
                    SELECT v_id, 'saldo', CASE WHEN random() < 0.5 THEN 'efectivo' ELSE 'tarjeta_en_hotel' END,
                           v_total - v_ant, 'aprobado', gen_random_uuid(), v_recep,
                           r.checkout_en - interval '5 minutes', r.checkout_en - interval '5 minutes'
                      FROM reservacion r WHERE r.id_reservacion = v_id;
                ELSIF v_estado = 'cancelada' THEN
                    INSERT INTO pago (id_reservacion, tipo, metodo, monto, estado, llave_idempotencia, pasarela,
                                      id_pago_origen, registrado_por, confirmado_en, creado_en)
                    VALUES (v_id, 'reembolso', v_metodo, v_ant, 'aprobado', gen_random_uuid(),
                            CASE WHEN v_metodo = 'pasarela' THEN 'simulada' END, v_pago, v_admin,
                            least(v_cancel + interval '1 day', now() - interval '5 minutes'),
                            least(v_cancel + interval '1 day', now() - interval '5 minutes'));
                END IF;
            END IF;

            v_entrada := v_salida + floor(random() * v_gap_max)::int;
        END LOOP;
    END LOOP;

    UPDATE cupon c SET usos_actuales = (SELECT count(*) FROM cupon_uso cu WHERE cu.id_cupon = c.id_cupon AND cu.estado = 'aplicado');

    UPDATE habitacion h SET estado = 'ocupada'
     WHERE EXISTS (SELECT 1 FROM reservacion_habitacion rh JOIN reservacion r ON r.id_reservacion = rh.id_reservacion
                    WHERE rh.id_habitacion = h.id_habitacion AND r.estado = 'en_curso');
END;
$$;

DO $$
DECLARE
    v_admin    BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@horiani.test');
    v_limp     BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'limpieza@horiani.test');
    v_lav      BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'lavanderia@horiani.test');
    v_hotel    BIGINT := (SELECT id_hotel FROM hotel WHERE slug = 'horiani-quetzaltenango');
    v_hab      BIGINT := (SELECT h.id_habitacion FROM habitacion h WHERE h.id_hotel = (SELECT id_hotel FROM hotel WHERE slug = 'horiani-quetzaltenango') AND h.numero = '101');
    v_lim      BIGINT; v_ame BIGINT; v_bla BIGINT;
    v_lote     BIGINT;
    r          RECORD;
BEGIN
    v_lim := sp_inventario_crear_categoria(v_admin, 'Limpieza');
    v_ame := sp_inventario_crear_categoria(v_admin, 'Amenidades');
    v_bla := sp_inventario_crear_categoria(v_admin, 'Blancos');

    FOR r IN SELECT * FROM (VALUES
            (v_lim, 'Cloro',              'insumo', 'galón',  5,  24),
            (v_lim, 'Desinfectante',      'insumo', 'galón',  4,  18),
            (v_lim, 'Detergente en polvo','insumo', 'bolsa',  6,  20),
            (v_ame, 'Jabón de tocador',   'insumo', 'unidad', 60, 200),
            (v_ame, 'Shampoo',            'insumo', 'unidad', 60, 150),
            (v_ame, 'Papel higiénico',    'insumo', 'rollo',  80, 300),
            (v_bla, 'Toalla de baño',     'blanco', 'pieza',  40, 90),
            (v_bla, 'Toalla de mano',     'blanco', 'pieza',  40, 90),
            (v_bla, 'Sábana individual',  'blanco', 'pieza',  20, 50),
            (v_bla, 'Sábana matrimonial', 'blanco', 'pieza',  20, 40),
            (v_bla, 'Funda de almohada',  'blanco', 'pieza',  40, 100)
        ) AS a (cat, nombre, clase, unidad, minimo, compra)
    LOOP
        PERFORM sp_inventario_registrar_entrada(v_admin,
            sp_inventario_crear_articulo(v_admin, v_hotel, r.cat, r.nombre, r.clase, r.unidad, r.minimo),
            r.compra, 'Compra inicial (datos de prueba)');
    END LOOP;

    PERFORM sp_inventario_registrar_consumo(v_limp, a.id_articulo, x.cantidad, v_hab, 'Limpieza de habitaciones')
       FROM articulo a JOIN (VALUES ('Cloro', 6), ('Desinfectante', 4), ('Jabón de tocador', 70),
                                    ('Shampoo', 95), ('Papel higiénico', 120)) AS x (nombre, cantidad)
         ON x.nombre = a.nombre
      WHERE a.id_hotel = v_hotel;

    PERFORM sp_inventario_registrar_conteo(v_admin, a.id_articulo, 'bodega', 178, 'Conteo mensual')
       FROM articulo a WHERE a.id_hotel = v_hotel AND a.nombre = 'Papel higiénico';

    PERFORM sp_inventario_colocar_blancos(v_limp, v_hab, jsonb_agg(jsonb_build_object('id_articulo', a.id_articulo, 'cantidad', 20)))
       FROM articulo a WHERE a.id_hotel = v_hotel AND a.clase = 'blanco';
    v_lote := (SELECT sp_lavanderia_recibir_lote(v_lav, v_hotel,
                  jsonb_agg(jsonb_build_object('id_articulo', a.id_articulo, 'cantidad', 12)), 'Lote de la mañana')
                 FROM articulo a WHERE a.id_hotel = v_hotel AND a.clase = 'blanco');
    PERFORM sp_lavanderia_devolver_lote(v_lav, v_lote,
                jsonb_agg(jsonb_build_object('id_articulo', a.id_articulo,
                                             'cantidad', CASE WHEN a.nombre = 'Toalla de baño' THEN 11 ELSE 12 END)),
                'Una toalla de baño no regresó')
       FROM articulo a WHERE a.id_hotel = v_hotel AND a.clase = 'blanco';
    PERFORM sp_lavanderia_recibir_lote(v_lav, v_hotel,
                jsonb_agg(jsonb_build_object('id_articulo', a.id_articulo, 'cantidad', 5)), 'Lote de la tarde')
       FROM articulo a WHERE a.id_hotel = v_hotel AND a.clase = 'blanco';
    PERFORM sp_inventario_dar_baja(v_lav, a.id_articulo, 'bodega', 2, 'Manchadas, no se recuperan')
       FROM articulo a WHERE a.id_hotel = v_hotel AND a.nombre = 'Funda de almohada';
END;
$$;

DO $$
DECLARE
    v_admin  BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@horiani.test');
    v_recep  BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'recepcion@horiani.test');
    v_limp   BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'limpieza@horiani.test');
    v_hotel  BIGINT := (SELECT id_hotel FROM hotel WHERE slug = 'horiani-quetzaltenango');
    v_rep    BIGINT;
    r        RECORD;
BEGIN
    FOR r IN SELECT h.id_habitacion, row_number() OVER (ORDER BY h.numero) AS n
               FROM habitacion h WHERE h.id_hotel = v_hotel AND h.estado = 'disponible'
              ORDER BY h.numero LIMIT 2
    LOOP
        PERFORM sp_limpieza_crear_tarea(v_recep, r.id_habitacion, 'Revisión antes de la llegada');
        IF r.n = 1 THEN
            PERFORM sp_limpieza_tomar_tarea(v_limp, (SELECT max(id_tarea_limpieza) FROM tarea_limpieza));
        END IF;
    END LOOP;
    v_rep := sp_mantenimiento_reportar(v_limp, v_hotel,
        (SELECT id_habitacion FROM habitacion WHERE id_hotel = v_hotel AND numero = '104'), 'Foco del baño fundido');
    PERFORM sp_mantenimiento_cambiar_estado(v_admin, v_rep, 'resuelto', 'Se cambió el foco');
    v_rep := sp_mantenimiento_reportar(v_limp, v_hotel,
        (SELECT id_habitacion FROM habitacion WHERE id_hotel = v_hotel AND numero = '302'), 'Humedad en la pared de la sala');
    PERFORM sp_mantenimiento_cambiar_estado(v_admin, v_rep, 'en_proceso', NULL);
    PERFORM sp_mantenimiento_bloquear_habitacion(v_admin,
        (SELECT id_habitacion FROM habitacion WHERE id_hotel = v_hotel AND numero = '302'),
        interno.sp_comun_hoy() + 65, interno.sp_comun_hoy() + 67, 'Reparar humedad y pintar', v_rep);
END;
$$;

DO $$
DECLARE
    v_admin  BIGINT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@horiani.test');
    v_hotel  BIGINT := (SELECT id_hotel FROM hotel WHERE slug = 'horiani-quetzaltenango');
BEGIN
    PERFORM sp_contenido_guardar(v_admin, NULL, 'inicio', 'hero', 'titulo', 'texto', '"Hotel Horiani"', 0, TRUE);
    PERFORM sp_contenido_guardar(v_admin, NULL, 'inicio', 'hero', 'subtitulo', 'texto',
        '"Descanso y buen servicio en el corazón de Quetzaltenango"', 1, TRUE);
    PERFORM sp_contenido_guardar(v_admin, NULL, 'nosotros', 'valores', 'lista', 'lista', $j$[
        {"icono": "ti-mood-smile", "titulo": "Amabilidad", "descripcion": "Nos esforzamos por tratar a todos con amabilidad y cortesía, creando una experiencia que combine confort y servicio excepcional."},
        {"icono": "ti-eye-check", "titulo": "Honestidad", "descripcion": "Garantizar confianza, seguridad e integridad en las relaciones interpersonales, ofreciendo conductas éticas en todo momento."},
        {"icono": "ti-medal", "titulo": "Honradez", "descripcion": "Actuamos con rectitud en todo lo que hacemos, valoramos la verdad ya que es fundamental en la vida social."},
        {"icono": "ti-heart", "titulo": "Pasión", "descripcion": "Nos apasiona lo que hacemos, nos esforzamos por brindar un servicio excepcional y superar las expectativas de nuestros clientes."},
        {"icono": "ti-users", "titulo": "Respeto", "descripcion": "Tratamos a todos con dignidad y consideración, fomentando un ambiente inclusivo y acogedor para nuestros huéspedes."},
        {"icono": "ti-shield-check", "titulo": "Responsabilidad", "descripcion": "Cumplir con las obligaciones que acordamos con nuestros clientes, actuamos de manera correcta y comprometidos con el servicio."}
    ]$j$::jsonb, 0, TRUE);
    PERFORM sp_hoteles_agregar_imagen(v_admin, v_hotel, '/images/Gallery/pasillo1.jpeg', 'Pasillo del hotel', 'carrusel');
    PERFORM sp_hoteles_agregar_imagen(v_admin, v_hotel, '/images/Gallery/pasillo2.jpeg', 'Habitaciones', 'carrusel');
    PERFORM sp_hoteles_agregar_imagen(v_admin, v_hotel, '/images/Gallery/pasillo4.jpeg', 'Áreas comunes', 'galeria');
END;
$$;

INSERT INTO version_esquema (script) VALUES ('090_semilla.sh (datos de prueba)');