from datetime import date

from ....shared.errores.error_aplicacion import ErrorAplicacion
from ....shared.utilidades.contrasena import hashear_contrasena
from ....shared.utilidades.mapeo import a_snake
from ....shared.utilidades.respuesta import paginar
from ..esquemas.empleado_esquema import (
    ActualizarEmpleadoEsquema,
    CrearEmpleadoEsquema,
    EmpleadosConsulta,
    UsuarioEmpleadoEsquema,
)
from ..repositorios import empleados_repositorio as repositorio


async def crear(id_actor: int, d: CrearEmpleadoEsquema) -> dict:
    contrasena_hash = await hashear_contrasena(d.contrasena) if d.contrasena else None
    return await repositorio.crear(id_actor, d.nombres, d.apellidos, d.dpi, d.telefono, d.puesto, d.fecha_ingreso,
                                   d.ids_hotel, d.correo, d.rol, contrasena_hash)


async def actualizar(id_actor: int, id_empleado: int, d: ActualizarEmpleadoEsquema) -> dict:
    await repositorio.actualizar(id_actor, id_empleado, d.nombres, d.apellidos, d.telefono, d.puesto)
    return {"id_empleado": id_empleado}


async def asignar_hoteles(id_actor: int, id_empleado: int, ids_hotel: list[int]) -> dict:
    await repositorio.asignar_hoteles(id_actor, id_empleado, ids_hotel)
    return {"id_empleado": id_empleado, "ids_hotel": ids_hotel}


async def crear_usuario(id_actor: int, id_empleado: int, d: UsuarioEmpleadoEsquema) -> dict:
    contrasena_hash = await hashear_contrasena(d.contrasena)
    id_usuario = await repositorio.crear_usuario(id_actor, id_empleado, d.correo, d.rol, contrasena_hash)
    return {"id_empleado": id_empleado, "id_usuario": id_usuario}


async def cambiar_rol(id_actor: int, id_empleado: int, rol: str) -> dict:
    await repositorio.cambiar_rol(id_actor, id_empleado, rol)
    return {"id_empleado": id_empleado, "rol": rol}


async def dar_baja(id_actor: int, id_empleado: int, fecha_baja: date) -> dict:
    await repositorio.dar_baja(id_actor, id_empleado, fecha_baja)
    return {"id_empleado": id_empleado, "fecha_baja": fecha_baja}


async def obtener(id_actor: int, id_empleado: int) -> dict:
    fila = await repositorio.obtener(id_actor, id_empleado)
    if not fila:
        raise ErrorAplicacion("El empleado no existe", "empleado_no_encontrado", 404)
    return fila


async def listar(id_actor: int, q: EmpleadosConsulta) -> dict:
    filas = await repositorio.listar(id_actor, q.id_hotel, q.busqueda, q.activo, q.pagina, q.registros_por_pagina,
                                     a_snake(q.ordenar_por), q.direccion)
    return paginar(filas, q.pagina, q.registros_por_pagina)