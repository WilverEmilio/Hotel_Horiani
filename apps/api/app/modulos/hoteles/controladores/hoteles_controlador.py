from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.hoteles_esquemas import (
    ActualizarHotelEsquema,
    ConfiguracionHotelEsquema,
    CrearHotelEsquema,
    ImagenHotelEsquema,
    OrdenImagenesHotelEsquema,
)
from ..servicios import hoteles_servicio as servicio


async def listar_publico():
    return respuesta('Hoteles obtenidos correctamente', 
                     await servicio.listar_publico()
                     )
    
async def obtener_publico(slug: str):
    return respuesta('Hotel obtenido correctamente',
                     await servicio.obtener_publico(slug)
                     )
    
async def crear(datos: CrearHotelEsquema, actor: ActorDep):
    return respuesta("Hotel creado correctamente", 
                     await servicio.crear(actor.id_usuario, datos)
                     )


async def actualizar(id_hotel: int, datos: ActualizarHotelEsquema, actor: ActorDep):
    return respuesta("Hotel actualizado correctamente", 
                     await servicio.actualizar(actor.id_usuario, id_hotel, datos)
                     )


async def obtener_configuracion(id_hotel: int, actor: ActorDep):
    return respuesta("Configuración obtenida correctamente",
                     await servicio.obtener_configuracion(actor.id_usuario, id_hotel)
                     )


async def actualizar_configuracion(id_hotel: int, datos: ConfiguracionHotelEsquema, actor: ActorDep):
    return respuesta("Configuración actualizada correctamente",
                     await servicio.actualizar_configuracion(actor.id_usuario, id_hotel, datos)
                     )


async def agregar_imagen(id_hotel: int, datos: ImagenHotelEsquema, actor: ActorDep):
    return respuesta("Imagen agregada correctamente", 
                     await servicio.agregar_imagen(actor.id_usuario, id_hotel, datos)
                     )


async def quitar_imagen(id_hotel_imagen: int, actor: ActorDep):
    return respuesta("Imagen quitada correctamente", 
                     await servicio.quitar_imagen(actor.id_usuario, id_hotel_imagen)
                     )


async def ordenar_imagenes(id_hotel: int, datos: OrdenImagenesHotelEsquema, actor: ActorDep):
    return respuesta("Imágenes ordenadas correctamente",
                     await servicio.ordenar_imagenes(actor.id_usuario, id_hotel, datos)
                     )