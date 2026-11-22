from ....shared.utilidades.respuesta import respuesta
from ..servicios import hoteles_servicio as servicio


async def listar_publico():
    return respuesta('Hoteles obtenidos correctamente', 
                     await servicio.listar_publico()
                     )
    
async def obtener_publico(slug: str):
    return respuesta('Hotel obtenido correctamente',
                     await servicio.obtener_publico(slug)
                     )