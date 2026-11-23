from fastapi import APIRouter

from ..controladores import autenticacion_controlador as c

rutas_autenticacion = APIRouter(prefix="/auth", tags=["Autenticación"])
r = rutas_autenticacion

r.add_api_route("/registro", c.registrar, methods=["POST"], status_code=201,
                summary="Crear cuenta de cliente e iniciar sesión")
r.add_api_route("/iniciar-sesion", c.iniciar_sesion, methods=["POST"], summary="Iniciar sesión (personal y clientes)")
r.add_api_route("/perfil", c.perfil, methods=["GET"], summary="Datos, hoteles y permisos del usuario")