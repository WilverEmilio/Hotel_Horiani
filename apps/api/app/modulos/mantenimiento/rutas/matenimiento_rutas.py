from fastapi import APIRouter

from ..controladores import mantenimiento_controlador as c

rutas_mantenimiento = APIRouter(prefix="/mantenimiento", tags=["Mantenimiento"])
r = rutas_mantenimiento
r.add_api_route("/reportes", c.reportar, methods=["POST"], status_code=201, summary="Reportar un daño")
r.add_api_route("/reportes", c.listar_reportes, methods=["GET"], summary="Reportes de mantenimiento")
r.add_api_route("/reportes/{id_reporte}/estado", c.cambiar_estado, methods=["PATCH"],
                summary="Avanzar el reporte (resolver libera sus bloqueos)")
r.add_api_route("/bloqueos", c.bloquear_habitacion, methods=["POST"], status_code=201,
                summary="Sacar una habitación de la venta por fechas")
r.add_api_route("/bloqueos/{id_bloqueo}", c.liberar_bloqueo, methods=["DELETE"], summary="Liberar bloqueo")
r.add_api_route("/bloqueos", c.listar_bloqueos, methods=["GET"], summary="Bloqueos del hotel en un rango")