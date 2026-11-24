from datetime import date
from decimal import Decimal

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def listar_servicios_publico() -> list[dict]:
    return await ejecutar.filas("sp_servicios_listar_publico")


async def crear_servicio(id_actor: int, nombre: str, icono: str | None) -> int:
    return await ejecutar.valor("sp_servicios_crear", id_actor, nombre, icono)


async def listar_tipos_publico(id_hotel: int) -> list[dict]:
    return await ejecutar.filas("sp_habitaciones_listar_tipos_publico", id_hotel)


async def crear_tipo(id_actor: int, id_hotel: int, nombre: str, descripcion: str | None, capacidad_maxima: int,
                     precio_base: Decimal) -> int:
    return await ejecutar.valor("sp_habitaciones_crear_tipo", id_actor, id_hotel, nombre, descripcion,
                                capacidad_maxima, precio_base)


async def actualizar_tipo(id_actor: int, id_tipo: int, nombre: str, descripcion: str | None, capacidad_maxima: int,
                          activo: bool) -> None:
    await ejecutar.procedimiento("sp_habitaciones_actualizar_tipo", id_actor, id_tipo, nombre, descripcion,
                                 capacidad_maxima, activo)


async def cambiar_precio_base(id_actor: int, id_tipo: int, precio_base: Decimal) -> None:
    await ejecutar.procedimiento("sp_habitaciones_cambiar_precio_base", id_actor, id_tipo, precio_base)


async def asignar_servicios(id_actor: int, id_tipo: int, ids_servicio: list[int]) -> None:
    await ejecutar.procedimiento("sp_habitaciones_asignar_servicios", id_actor, id_tipo, ids_servicio)


async def crear_tarifa(id_actor: int, id_tipo: int, nombre: str, fecha_inicio: date, fecha_fin: date,
                       precio_noche: Decimal) -> int:
    return await ejecutar.valor("sp_habitaciones_crear_tarifa_especial", id_actor, id_tipo, nombre, fecha_inicio,
                                fecha_fin, precio_noche)


async def desactivar_tarifa(id_actor: int, id_tarifa: int) -> None:
    await ejecutar.procedimiento("sp_habitaciones_desactivar_tarifa_especial", id_actor, id_tarifa)


async def listar_tarifas(id_actor: int, id_tipo: int, incluir_inactivas: bool) -> list[dict]:
    return await ejecutar.filas("sp_habitaciones_listar_tarifas_especiales", id_actor, id_tipo, incluir_inactivas)


async def agregar_imagen(id_actor: int, id_tipo: int, url: str, texto_alternativo: str) -> int:
    return await ejecutar.valor("sp_habitaciones_agregar_imagen", id_actor, id_tipo, url, texto_alternativo)


async def quitar_imagen(id_actor: int, id_imagen: int) -> None:
    await ejecutar.procedimiento("sp_habitaciones_quitar_imagen", id_actor, id_imagen)


async def ordenar_imagenes(id_actor: int, id_tipo: int, ids: list[int]) -> None:
    await ejecutar.procedimiento("sp_habitaciones_ordenar_imagenes", id_actor, id_tipo, ids)