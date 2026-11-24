from datetime import date
from uuid import UUID

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def consultar_disponibilidad(id_hotel: int, entrada: date, salida: date, huespedes: int) -> list[dict]:
    return await ejecutar.filas("sp_reservaciones_consultar_disponibilidad", id_hotel, entrada, salida, huespedes)


async def listar_habitaciones_libres(id_hotel: int, id_tipo: int, entrada: date, salida: date) -> list[dict]:
    return await ejecutar.filas("sp_reservaciones_listar_habitaciones_libres", id_hotel, id_tipo, entrada, salida)


async def crear(id_actor: int, id_hotel: int, entrada: date, salida: date, habitaciones: list[dict],
                codigo_cupon: str | None, origen: str, llave: UUID, id_cliente: int | None) -> dict:
    return await ejecutar.fila("sp_reservaciones_crear", id_actor, id_hotel, entrada, salida,
                               ejecutar.json(habitaciones), codigo_cupon, origen, llave, id_cliente)


async def obtener(id_actor: int, id_reservacion: int) -> dict | None:
    return await ejecutar.fila("sp_reservaciones_obtener", id_actor, id_reservacion)


async def listar_mias(id_actor: int, pagina: int, tamano: int) -> list[dict]:
    return await ejecutar.filas("sp_reservaciones_listar_mias", id_actor, pagina, tamano)


async def listar(id_actor: int, id_hotel: int, estado: str | None, id_cliente: int | None, desde: date | None,
                 hasta: date | None, busqueda: str | None, pagina: int, tamano: int, orden: str,
                 direccion: str) -> list[dict]:
    return await ejecutar.filas("sp_reservaciones_listar", id_actor, id_hotel, estado, id_cliente, desde, hasta,
                                busqueda, pagina, tamano, orden, direccion)


async def cancelar(id_actor: int, id_reservacion: int, motivo: str) -> dict:
    return await ejecutar.fila("sp_reservaciones_cancelar", id_actor, id_reservacion, motivo)


async def reasignar_habitacion(id_actor: int, id_reservacion_habitacion: int, id_habitacion_nueva: int,
                               motivo: str) -> None:
    await ejecutar.procedimiento("sp_reservaciones_reasignar_habitacion", id_actor, id_reservacion_habitacion,
                                 id_habitacion_nueva, motivo)


async def expirar_pendientes() -> int:
    return await ejecutar.valor("sp_reservaciones_expirar_pendientes")