from fastapi import APIRouter

from ..controladores import empleados_controlador as c

rutas_empleados = APIRouter(tags=["Empleados, turnos y asistencia"])
r = rutas_empleados

r.add_api_route("/empleados", c.crear, methods=["POST"], status_code=201,
                summary="Crear empleado (y su usuario si se envía correo)")
r.add_api_route("/empleados", c.listar, methods=["GET"], summary="Listado con rol, hoteles y turnos vigentes")
r.add_api_route("/empleados/{id_empleado}", c.obtener, methods=["GET"], summary="Ficha del empleado con hoteles y turnos")
r.add_api_route("/empleados/{id_empleado}", c.actualizar, methods=["PUT"], summary="Editar empleado")
r.add_api_route("/empleados/{id_empleado}/hoteles", c.asignar_hoteles, methods=["PUT"],
                summary="Definir los hoteles del empleado")
r.add_api_route("/empleados/{id_empleado}/usuario", c.crear_usuario, methods=["POST"], status_code=201,
                summary="Dar acceso al sistema a un empleado")
r.add_api_route("/empleados/{id_empleado}/rol", c.cambiar_rol, methods=["PATCH"],
                summary="Cambiar rol (cierra sus sesiones)")
r.add_api_route("/empleados/{id_empleado}/baja", c.dar_baja, methods=["POST"],
                summary="Dar de baja (desactiva usuario y termina turnos)")