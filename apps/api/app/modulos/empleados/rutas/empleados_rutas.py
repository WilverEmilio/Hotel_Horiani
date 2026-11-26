from fastapi import APIRouter

from ..controladores import asistencia_controlador as asistencia
from ..controladores import empleados_controlador as c
from ..controladores import turnos_controlador as turnos

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

r.add_api_route("/turnos", turnos.listar, methods=["GET"], summary="Turnos del hotel")
r.add_api_route("/turnos", turnos.crear, methods=["POST"], status_code=201,
                summary="Crear turno (puede cruzar medianoche)")
r.add_api_route("/turnos/{id_turno}", turnos.actualizar, methods=["PUT"], summary="Editar o desactivar turno")
r.add_api_route("/empleados/{id_empleado}/turnos", turnos.asignar, methods=["POST"], status_code=201,
                summary="Asignar turno fijo desde una fecha")
r.add_api_route("/empleados/turnos/{id_empleado_turno}/finalizar", turnos.finalizar, methods=["POST"],
                summary="Terminar una asignación de turno")

r.add_api_route("/asistencia", asistencia.registrar, methods=["POST"], status_code=201,
                summary="Registrar o corregir la asistencia de un día")
r.add_api_route("/asistencia/rango", asistencia.registrar_rango, methods=["POST"], status_code=201,
                summary="Vacaciones, permiso, descanso o suspensión por varios días (máximo 60)")
r.add_api_route("/asistencia/hoja-del-dia", asistencia.hoja_del_dia, methods=["GET"],
                summary="Empleados con sus turnos del día y lo registrado")
r.add_api_route("/asistencia", asistencia.listar, methods=["GET"], summary="Registros de asistencia")
r.add_api_route("/asistencia/resumen", asistencia.resumen, methods=["GET"],
                summary="Conteo por estado de cada empleado en un periodo")