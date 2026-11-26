from typing import Annotated

from fastapi import Query

from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.empleado_esquema import (
    ActualizarEmpleadoEsquema,
    BajaEmpleadoEsquema,
    CrearEmpleadoEsquema,
    EmpleadosConsulta,
    HotelesEmpleadoEsquema,
    RolEmpleadoEsquema,
    UsuarioEmpleadoEsquema,
)
from ..servicios import empleados_servicio as servicio


async def crear(datos: CrearEmpleadoEsquema, actor: ActorDep):
    return respuesta("Empleado creado correctamente", await servicio.crear(actor.id_usuario, datos))


async def listar(q: Annotated[EmpleadosConsulta, Query()], actor: ActorDep):
    return respuesta("Empleados obtenidos correctamente", await servicio.listar(actor.id_usuario, q))


async def obtener(id_empleado: int, actor: ActorDep):
    return respuesta("Empleado obtenido correctamente", await servicio.obtener(actor.id_usuario, id_empleado))


async def actualizar(id_empleado: int, datos: ActualizarEmpleadoEsquema, actor: ActorDep):
    return respuesta("Empleado actualizado correctamente",
                     await servicio.actualizar(actor.id_usuario, id_empleado, datos))


async def asignar_hoteles(id_empleado: int, datos: HotelesEmpleadoEsquema, actor: ActorDep):
    return respuesta("Hoteles asignados correctamente",
                     await servicio.asignar_hoteles(actor.id_usuario, id_empleado, datos.ids_hotel))


async def crear_usuario(id_empleado: int, datos: UsuarioEmpleadoEsquema, actor: ActorDep):
    return respuesta("Usuario creado correctamente",
                     await servicio.crear_usuario(actor.id_usuario, id_empleado, datos))


async def cambiar_rol(id_empleado: int, datos: RolEmpleadoEsquema, actor: ActorDep):
    return respuesta("Rol actualizado correctamente. Se cerraron las sesiones del empleado",
                     await servicio.cambiar_rol(actor.id_usuario, id_empleado, datos.rol))


async def dar_baja(id_empleado: int, datos: BajaEmpleadoEsquema, actor: ActorDep):
    return respuesta("Empleado dado de baja correctamente",
                     await servicio.dar_baja(actor.id_usuario, id_empleado, datos.fecha_baja))