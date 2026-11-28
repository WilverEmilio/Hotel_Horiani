from fastapi import APIRouter

from ..controladores import cupones_controlador as c

rutas_cupones = APIRouter(prefix="/cupones", tags=["Cupones"])
r = rutas_cupones
r.add_api_route("", c.crear, methods=["POST"], status_code=201, summary="Crear cupón")
r.add_api_route("", c.listar, methods=["GET"], summary="Cupones con estado calculado")
r.add_api_route("/vista-previa", c.vista_previa, methods=["POST"],
                summary="Calcular el descuento antes de reservar (no consume el cupón)")
r.add_api_route("/{id_cupon}", c.obtener, methods=["GET"], summary="Detalle con los últimos usos")
r.add_api_route("/{id_cupon}", c.actualizar, methods=["PUT"],
                summary="Editar cupón (si ya se usó, solo descripción, fecha final, límites y activo)")