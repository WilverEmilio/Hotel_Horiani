from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def listar_publico() -> list[dict]:
    return await ejecutar.filas('sp_hoteles_listar_publico')

async def obtener_publico(slug: str) -> dict | None:
    return await ejecutar.fila('sp_hoteles_obtener_publico', slug)