from fastapi import APIRouter

from ..controladores import bitacora_controlador as c

rutas_bitacora = APIRouter(prefix="/bitacora", tags=["Bitácora"])
r = rutas_bitacora
r.add_api_route("", c.listar, methods=["GET"], summary="Bitácora con filtros y búsqueda en los valores")
r.add_api_route("/catalogo", c.catalogo, methods=["GET"], summary="Módulos y entidades existentes (para los filtros)")
r.add_api_route("/{entidad}/{id_registro}", c.historial_registro, methods=["GET"],
                summary="Todos los cambios de un registro")