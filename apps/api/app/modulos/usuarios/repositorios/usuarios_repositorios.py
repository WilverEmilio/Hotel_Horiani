from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar

async def listar_roles(id_actor: int) -> list[dict]:
    return await ejecutar.filas(
        'sp_seguridad_listar_roles',
        id_actor
    )
    
async def cambiar_estado(
    id_actor: int,
    id_usuario: int, 
    activo: bool
    ) -> None:
    await ejecutar.procedimiento(
        'sp_seguridad_cambiar_estado_usuario', 
        id_actor,
        id_usuario,
        activo
    )
    
async def generar_enlace_contrasena(
    id_actor: int,
    id_usuario: int,
    token_hash: str, 
    horas: int
) -> dict:
    return await ejecutar.fila(
        'sp_seguridad_generar_enlace_contrasena', 
        id_actor,
        id_usuario,
        token_hash,
        horas
    )