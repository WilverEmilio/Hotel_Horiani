from datetime import date
from decimal import Decimal

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def crear_categoria(id_actor: int, nombre: str) -> int:
    return await ejecutar.valor("sp_inventario_crear_categoria", id_actor, nombre)


async def listar_categorias(id_actor: int) -> list[dict]:
    return await ejecutar.filas("sp_inventario_listar_categorias", id_actor)


async def crear_articulo(id_actor: int, id_hotel: int, id_categoria: int, nombre: str, clase: str, unidad: str,
                         minima: Decimal) -> int:
    return await ejecutar.valor("sp_inventario_crear_articulo", id_actor, id_hotel, id_categoria, nombre, clase,
                                unidad, minima)


async def actualizar_articulo(id_actor: int, id_articulo: int, id_categoria: int, nombre: str, unidad: str,
                              minima: Decimal, activo: bool) -> None:
    await ejecutar.procedimiento("sp_inventario_actualizar_articulo", id_actor, id_articulo, id_categoria, nombre,
                                 unidad, minima, activo)


async def registrar_entrada(id_actor: int, id_articulo: int, cantidad: Decimal, motivo: str | None) -> dict:
    return await ejecutar.fila("sp_inventario_registrar_entrada", id_actor, id_articulo, cantidad, motivo)


async def registrar_conteo(id_actor: int, id_articulo: int, ubicacion: str, contada: Decimal, motivo: str) -> dict:
    return await ejecutar.fila("sp_inventario_registrar_conteo", id_actor, id_articulo, ubicacion, contada, motivo)


async def registrar_consumo(id_actor: int, id_articulo: int, cantidad: Decimal, id_habitacion: int | None,
                            motivo: str | None) -> dict:
    return await ejecutar.fila("sp_inventario_registrar_consumo", id_actor, id_articulo, cantidad, id_habitacion,
                               motivo)


async def colocar_blancos(id_actor: int, id_habitacion: int, items: list[dict]) -> int:
    return await ejecutar.valor("sp_inventario_colocar_blancos", id_actor, id_habitacion, ejecutar.json(items))


async def dar_baja(id_actor: int, id_articulo: int, ubicacion: str, cantidad: Decimal, motivo: str) -> int:
    return await ejecutar.valor("sp_inventario_dar_baja", id_actor, id_articulo, ubicacion, cantidad, motivo)


async def listar_existencias(id_actor: int, id_hotel: int, clase: str | None, busqueda: str | None,
                             solo_bajo_minimo: bool, incluir_inactivos: bool, pagina: int, tamano: int, orden: str,
                             direccion: str) -> list[dict]:
    return await ejecutar.filas("sp_inventario_listar_existencias", id_actor, id_hotel, clase, busqueda,
                                solo_bajo_minimo, incluir_inactivos, pagina, tamano, orden, direccion)


async def listar_movimientos(id_actor: int, id_hotel: int, id_articulo: int | None, tipo: str | None,
                             desde: date | None, hasta: date | None, pagina: int, tamano: int) -> list[dict]:
    return await ejecutar.filas("sp_inventario_listar_movimientos", id_actor, id_hotel, id_articulo, tipo, desde,
                                hasta, pagina, tamano)


async def alertas(id_actor: int, id_hotel: int) -> list[dict]:
    return await ejecutar.filas("sp_inventario_alertas", id_actor, id_hotel)