from fastapi import APIRouter

from ..controladores import usuarios_controlador as c

rutas_usuarios = APIRouter(tags=["Usuarios"])
r = rutas_usuarios

r.add_api_route("/roles", c.listar_roles, methods=["GET"], summary="Roles con sus permisos")
r.add_api_route("/usuarios/{id_usuario}/estado", c.cambiar_estado, methods=["PATCH"],
                summary="Activar o desactivar un usuario (desactivar cierra sus sesiones)")
r.add_api_route("/usuarios/{id_usuario}/enlace-contrasena", c.generar_enlace_contrasena, methods=["POST"],
                status_code=201, summary="Generar enlace de un solo uso para definir contraseña")