from ....shared.errores.error_aplicacion import ErrorAplicacion
from ..esquemas.hoteles_esquemas import (
    ActualizarHotelEsquema,
    ConfiguracionHotelEsquema,
    CrearHotelEsquema,
    ImagenHotelEsquema,
    OrdenImagenesHotelEsquema,
)
from ..repositorios import hoteles_repositorio as repositorio

_NO_EXISTE = ('El hotel no existe', 'hotel_no_encontrado', 404)

async def listar_publico() -> list[dict]:
    return await repositorio.listar_publico()

async def obtener_publico(slug: str) -> dict:
    hotel = await repositorio.obtener_publico(slug)
    if not hotel:
        raise ErrorAplicacion('El hotel no existe', 'hotel_no_encontrado', 404)
    return hotel

async def crear(id_actor: int, d: CrearHotelEsquema) -> dict:
    id_hotel = await repositorio.crear(id_actor, d.nombre, d.slug, d.direccion, d.ciudad, d.telefono, d.correo)
    return {"id_hotel": id_hotel}


async def actualizar(id_actor: int, id_hotel: int, d: ActualizarHotelEsquema) -> dict:
    await repositorio.actualizar(id_actor, id_hotel, d.nombre, d.direccion, d.ciudad, d.telefono, d.correo, d.activo)
    return {"id_hotel": id_hotel}


async def obtener_configuracion(id_actor: int, id_hotel: int) -> dict:
    conf = await repositorio.obtener_configuracion(id_actor, id_hotel)
    if not conf:
        raise ErrorAplicacion(*_NO_EXISTE)
    return conf


async def actualizar_configuracion(id_actor: int, id_hotel: int, d: ConfiguracionHotelEsquema) -> dict:
    await repositorio.actualizar_configuracion(id_actor, id_hotel, d.hora_checkout, d.porcentaje_anticipo,
                                               d.minutos_bloqueo_pago, d.horas_limite_cancelacion,
                                               d.porcentaje_reembolso, d.no_presentacion_pierde_anticipo)
    return await obtener_configuracion(id_actor, id_hotel) 


async def agregar_imagen(id_actor: int, id_hotel: int, d: ImagenHotelEsquema) -> dict:
    id_imagen = await repositorio.agregar_imagen(id_actor, id_hotel, d.url, d.texto_alternativo, d.seccion)
    return {"id_hotel_imagen": id_imagen}


async def quitar_imagen(id_actor: int, id_hotel_imagen: int) -> dict:
    await repositorio.quitar_imagen(id_actor, id_hotel_imagen)
    return {"id_hotel_imagen": id_hotel_imagen}


async def ordenar_imagenes(id_actor: int, id_hotel: int, d: OrdenImagenesHotelEsquema) -> dict:
    await repositorio.ordenar_imagenes(id_actor, id_hotel, d.seccion, d.ids)
    return {"id_hotel": id_hotel, "seccion": d.seccion, "ids": d.ids}