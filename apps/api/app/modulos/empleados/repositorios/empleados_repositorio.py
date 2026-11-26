"""Stored procedures de empleados (script 027)."""
from datetime import date

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def crear(id_actor: int, nombres: str, apellidos: str, dpi: str, telefono: str | None, puesto: str,
                fecha_ingreso: date, ids_hotel: list[int], correo: str | None, rol: str | None,
                contrasena_hash: str | None) -> dict:
    return await ejecutar.fila("sp_empleados_crear", id_actor, nombres, apellidos, dpi, telefono, puesto,
                               fecha_ingreso, ids_hotel, correo, rol, contrasena_hash)


async def actualizar(id_actor: int, id_empleado: int, nombres: str, apellidos: str, telefono: str | None,
                     puesto: str) -> None:
    await ejecutar.procedimiento("sp_empleados_actualizar", id_actor, id_empleado, nombres, apellidos, telefono, puesto)


async def asignar_hoteles(id_actor: int, id_empleado: int, ids_hotel: list[int]) -> None:
    await ejecutar.procedimiento("sp_empleados_asignar_hoteles", id_actor, id_empleado, ids_hotel)


async def crear_usuario(id_actor: int, id_empleado: int, correo: str, rol: str, contrasena_hash: str) -> int:
    return await ejecutar.valor("sp_empleados_crear_usuario", id_actor, id_empleado, correo, rol, contrasena_hash)


async def cambiar_rol(id_actor: int, id_empleado: int, rol: str) -> None:
    await ejecutar.procedimiento("sp_empleados_cambiar_rol", id_actor, id_empleado, rol)


async def dar_baja(id_actor: int, id_empleado: int, fecha_baja: date) -> None:
    await ejecutar.procedimiento("sp_empleados_dar_baja", id_actor, id_empleado, fecha_baja)


async def obtener(id_actor: int, id_empleado: int) -> dict | None:
    return await ejecutar.fila("sp_empleados_obtener", id_actor, id_empleado)


async def listar(id_actor: int, id_hotel: int | None, busqueda: str | None, activo: bool | None, pagina: int,
                 tamano: int, orden: str, direccion: str) -> list[dict]:
    return await ejecutar.filas("sp_empleados_listar", id_actor, id_hotel, busqueda, activo, pagina, tamano, orden,
                                direccion)