from fastapi import APIRouter

from ..controladores import reportes_controlador as c

rutas_reportes = APIRouter(prefix="/reportes", tags=["Reportes"])
r = rutas_reportes
r.add_api_route("/dashboard", c.dashboard, methods=["GET"], summary="Tarjetas del día")
r.add_api_route("/ingresos", c.ingresos, methods=["GET"], summary="Ingresos por día, semana o mes")
r.add_api_route("/ocupacion", c.ocupacion, methods=["GET"], summary="Ocupación por tipo con fila TOTAL")
r.add_api_route("/ocupacion-diaria", c.ocupacion_diaria, methods=["GET"],
                summary="Ocupación día por día (máximo un año)")
r.add_api_route("/clientes-frecuentes", c.clientes_frecuentes, methods=["GET"], summary="Clientes con más estancias")
r.add_api_route("/cancelaciones", c.cancelaciones, methods=["GET"], summary="Canceladas, no presentadas y vencidas")
r.add_api_route("/cancelaciones/resumen", c.cancelaciones_resumen, methods=["GET"],
                summary="Conteo, valor y anticipación promedio por tipo de pérdida")
r.add_api_route("/cupones", c.cupones, methods=["GET"], summary="Usos, devueltos, descuento y ventas por cupón")
r.add_api_route("/inventario", c.inventario, methods=["GET"],
                summary="Compras, consumo, faltantes, bajas y existencia por artículo")