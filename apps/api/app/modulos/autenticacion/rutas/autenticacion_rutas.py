from fastapi import APIRouter

from ..controladores import autenticacion_controlador as c

rutas_autenticacion = APIRouter(prefix="/auth", tags=["Autenticación"])
r = rutas_autenticacion

r.add_api_route("/registro", c.registrar, methods=["POST"], status_code=201,
                summary="Crear cuenta de cliente e iniciar sesión")
r.add_api_route("/iniciar-sesion", c.iniciar_sesion, methods=["POST"], summary="Iniciar sesión (personal y clientes)")
r.add_api_route("/perfil", c.perfil, methods=["GET"], summary="Datos, hoteles y permisos del usuario")
r.add_api_route("/renovar", c.renovar, methods=["POST"], summary="Renovar el access token (rotación del refresh token)")
r.add_api_route("/cerrar-sesion", c.cerrar_sesion, methods=["POST"], summary="Cerrar la sesión de este dispositivo")
r.add_api_route("/cerrar-todas", c.cerrar_todas, methods=["POST"], summary="Cerrar todas las sesiones del usuario")
r.add_api_route("/contrasena", c.cambiar_contrasena, methods=["PUT"],
                summary="Cambiar la contraseña (cierra todas las sesiones)")
r.add_api_route("/enlace-contrasena/{token}", c.validar_enlace, methods=["GET"],
                summary="Validar un enlace para definir contraseña")
r.add_api_route("/enlace-contrasena", c.usar_enlace, methods=["POST"],
                summary="Definir la contraseña con un enlace de un solo uso")