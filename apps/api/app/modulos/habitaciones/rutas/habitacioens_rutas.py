from fastapi import APIRouter

from ..controladores import habitaciones_controlador as c

rutas_habitaciones = APIRouter(
    prefix= '/habitaciones',
    tags=['Habitaciones']
)

r = rutas_habitaciones
r.add_api_route("", c.listar, methods=["GET"], summary="Listado paginado de habitaciones del hotel")
r.add_api_route("", c.crear, methods=["POST"], status_code=201, summary="Crear habitación")
r.add_api_route("/{id_habitacion}", c.actualizar, methods=["PUT"], summary="Editar habitación")
r.add_api_route("/{id_habitacion}/estado", c.cambiar_estado, methods=["PATCH"], summary="Cambiar estado operativo")
r.add_api_route("/{id_habitacion}/activo", c.cambiar_activo, methods=["PATCH"], summary="Activar o desactivar habitación")