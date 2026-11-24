from decimal import Decimal

from ..esquemas.tipos_habitacion_esquema import (
    ActualizarTipoEsquema,
    CrearServicioEsquema,
    CrearTarifaEsquema,
    CrearTipoEsquema,
    ImagenTipoEsquema,
)
from ..repositorio import tipos_habitacion_repositorio as repositorio


async def listar_servicios_publico() -> list[dict]:
    return await repositorio.listar_servicios_publico()


async def crear_servicio(id_actor: int, d: CrearServicioEsquema) -> dict:
    return {"id_servicio": await repositorio.crear_servicio(id_actor, d.nombre, d.icono)}


async def listar_tipos_publico(id_hotel: int) -> list[dict]:
    return await repositorio.listar_tipos_publico(id_hotel)


async def crear_tipo(id_actor: int, d: CrearTipoEsquema) -> dict:
    id_tipo = await repositorio.crear_tipo(id_actor, d.id_hotel, d.nombre, d.descripcion, d.capacidad_maxima,
                                           d.precio_base)
    return {"id_tipo_habitacion": id_tipo}


async def actualizar_tipo(id_actor: int, id_tipo: int, d: ActualizarTipoEsquema) -> dict:
    await repositorio.actualizar_tipo(id_actor, id_tipo, d.nombre, d.descripcion, d.capacidad_maxima, d.activo)
    return {"id_tipo_habitacion": id_tipo}


async def cambiar_precio_base(id_actor: int, id_tipo: int, precio_base: Decimal) -> dict:
    await repositorio.cambiar_precio_base(id_actor, id_tipo, precio_base)
    return {"id_tipo_habitacion": id_tipo, "precio_base": precio_base}


async def asignar_servicios(id_actor: int, id_tipo: int, ids_servicio: list[int]) -> dict:
    await repositorio.asignar_servicios(id_actor, id_tipo, ids_servicio)
    return {"id_tipo_habitacion": id_tipo, "ids_servicio": ids_servicio}


async def crear_tarifa(id_actor: int, id_tipo: int, d: CrearTarifaEsquema) -> dict:
    id_tarifa = await repositorio.crear_tarifa(id_actor, id_tipo, d.nombre, d.fecha_inicio, d.fecha_fin,
                                               d.precio_noche)
    return {"id_tarifa_especial": id_tarifa}


async def desactivar_tarifa(id_actor: int, id_tarifa: int) -> dict:
    await repositorio.desactivar_tarifa(id_actor, id_tarifa)
    return {"id_tarifa_especial": id_tarifa}


async def listar_tarifas(id_actor: int, id_tipo: int, incluir_inactivas: bool) -> list[dict]:
    return await repositorio.listar_tarifas(id_actor, id_tipo, incluir_inactivas)


async def agregar_imagen(id_actor: int, id_tipo: int, d: ImagenTipoEsquema) -> dict:
    id_imagen = await repositorio.agregar_imagen(id_actor, id_tipo, d.url, d.texto_alternativo)
    return {"id_tipo_habitacion_imagen": id_imagen}


async def quitar_imagen(id_actor: int, id_imagen: int) -> dict:
    await repositorio.quitar_imagen(id_actor, id_imagen)
    return {"id_tipo_habitacion_imagen": id_imagen}


async def ordenar_imagenes(id_actor: int, id_tipo: int, ids: list[int]) -> dict:
    await repositorio.ordenar_imagenes(id_actor, id_tipo, ids)
    return {"id_tipo_habitacion": id_tipo, "ids": ids}