from fastapi import APIRouter

from ..controladores import clientes_controlador as c

rutas_clientes = APIRouter(prefix="/clientes", tags=["Clientes"])
r = rutas_clientes
r.add_api_route("", c.registrar, methods=["POST"], status_code=201,
                summary="Registrar cliente en recepción (con o sin cuenta)")
r.add_api_route("", c.listar, methods=["GET"], summary="Listado con búsqueda y estadísticas")
r.add_api_route("/mi-perfil", c.actualizar_mi_perfil, methods=["PUT"],
                summary="El cliente edita sus datos (no el documento)")
r.add_api_route("/{id_cliente}", c.obtener, methods=["GET"], summary="Datos y estadísticas del cliente")
r.add_api_route("/{id_cliente}", c.actualizar, methods=["PUT"], summary="Editar cliente (personal)")
r.add_api_route("/{id_cliente}/cuenta", c.crear_cuenta, methods=["POST"], status_code=201,
                summary="Crear cuenta (sin contraseña) a un cliente que no tenía")
r.add_api_route("/{id_cliente}/activo", c.cambiar_activo, methods=["PATCH"], summary="Activar o desactivar cliente")