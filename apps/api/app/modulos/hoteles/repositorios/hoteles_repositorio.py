from datetime import time
from decimal import Decimal

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def listar_publico() -> list[dict]:
    return await ejecutar.filas('sp_hoteles_listar_publico')

async def obtener_publico(slug: str) -> dict | None:
    return await ejecutar.fila('sp_hoteles_obtener_publico', slug)

async def crear(id_actor: int, nombre: str, slug: str, direccion: str, ciudad: str, telefono: str | None,
                correo: str | None) -> int:
    return await ejecutar.valor("sp_hoteles_crear", id_actor, nombre, slug, direccion, ciudad, telefono, correo)


async def actualizar(id_actor: int, id_hotel: int, nombre: str, direccion: str, ciudad: str, telefono: str | None,
                     correo: str | None, activo: bool) -> None:
    await ejecutar.procedimiento("sp_hoteles_actualizar", id_actor, id_hotel, nombre, direccion, ciudad, telefono,
                                 correo, activo)


async def obtener_configuracion(id_actor: int, id_hotel: int) -> dict | None:
    return await ejecutar.fila("sp_hoteles_obtener_configuracion", id_actor, id_hotel)


async def actualizar_configuracion(id_actor: int, id_hotel: int, hora_checkout: time, porcentaje_anticipo: Decimal,
                                   minutos_bloqueo_pago: int, horas_limite_cancelacion: int | None,
                                   porcentaje_reembolso: Decimal | None,
                                   no_presentacion_pierde_anticipo: bool | None) -> None:
    await ejecutar.procedimiento("sp_hoteles_actualizar_configuracion", id_actor, id_hotel, hora_checkout,
                                 porcentaje_anticipo, minutos_bloqueo_pago, horas_limite_cancelacion,
                                 porcentaje_reembolso, no_presentacion_pierde_anticipo)


async def agregar_imagen(id_actor: int, id_hotel: int, url: str, texto_alternativo: str, seccion: str) -> int:
    return await ejecutar.valor("sp_hoteles_agregar_imagen", id_actor, id_hotel, url, texto_alternativo, seccion)


async def quitar_imagen(id_actor: int, id_hotel_imagen: int) -> None:
    await ejecutar.procedimiento("sp_hoteles_quitar_imagen", id_actor, id_hotel_imagen)


async def ordenar_imagenes(id_actor: int, id_hotel: int, seccion: str, ids: list[int]) -> None:
    await ejecutar.procedimiento("sp_hoteles_ordenar_imagenes", id_actor, id_hotel, seccion, ids)