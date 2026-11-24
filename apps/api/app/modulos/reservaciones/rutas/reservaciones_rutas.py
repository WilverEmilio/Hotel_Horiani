from fastapi import APIRouter

from ..controladores import estancia_controlador as estancia
from ..controladores import reservaciones_controlador as c

rutas_disponibilidad_publico = APIRouter(prefix="/publico/hoteles/{id_hotel}", tags=["Público"])
p = rutas_disponibilidad_publico
p.add_api_route("/disponibilidad", c.consultar_disponibilidad, methods=["GET"],
                summary="Disponibilidad y precio por tipo para unas fechas")
p.add_api_route("/tipos-habitacion/{id_tipo_habitacion}/habitaciones-libres", c.listar_habitaciones_libres,
                methods=["GET"], summary="Números de habitación libres de un tipo")

rutas_reservaciones = APIRouter(prefix="/reservaciones", tags=["Reservaciones"])
r = rutas_reservaciones
r.add_api_route("", c.crear, methods=["POST"], status_code=201,
                summary="Crear reservación (queda pendiente de pago, salvo total en cero)")
r.add_api_route("/mias", c.listar_mias, methods=["GET"], summary="Historial del cliente en los 4 hoteles")
r.add_api_route("", c.listar, methods=["GET"], summary="Listado del panel con filtros")
r.add_api_route("/{id_reservacion}", c.obtener, methods=["GET"], summary="Detalle con habitaciones, noches e historial")
r.add_api_route("/{id_reservacion}/cancelar", c.cancelar, methods=["POST"],
                summary="Cancelar (devuelve anticipo pagado y reembolso sugerido)")
r.add_api_route("/habitaciones/{id_reservacion_habitacion}", c.reasignar_habitacion, methods=["PUT"],
                summary="Reasignar a otra habitación libre del mismo tipo")
r.add_api_route("/{id_reservacion}/checkin", estancia.hacer_checkin, methods=["POST"], summary="Check-in")
r.add_api_route("/{id_reservacion}/checkout", estancia.hacer_checkout, methods=["POST"],
                summary="Check-out (requiere saldo en cero; crea tareas de limpieza)")
r.add_api_route("/{id_reservacion}/no-presentado", estancia.marcar_no_presentado, methods=["POST"],
                summary="Marcar no presentado (desde el día siguiente a la entrada)")