from ....shared.errores.error_aplicacion import ErrorAplicacion
from ..repositorios import hoteles_repositorio as repositorio


async def listar_publico() -> list[dict]:
    return await repositorio.listar_publico()

async def obtener_publico(slug: str) -> dict:
    hotel = await repositorio.obtener_publico(slug)
    if not hotel:
        raise ErrorAplicacion('El hotel no existe', 'hotel_no_encontrado', 404)
    return hotel