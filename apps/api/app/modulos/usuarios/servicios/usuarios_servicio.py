from ....config.entorno import obtener_configuracion
from ....shared.utilidades.tokens import hash_token, nuevo_token_opaco
from ..repositorios import usuarios_repositorios as repositorio

async def listar_roles(id_actor: int) -> list [dict]:
    return await repositorio.listar_roles(id_actor)

async def cambiar_estado(
    id_actor: int,
    id_usuario: int,
    activo: bool
) -> dict:
    await repositorio.cambiar_estado(
        id_actor, 
        id_usuario, 
        activo
    )
    return {
        'id_usuario': id_usuario,
        'activo': activo
    }
    
async def generar_enlace_contrasena(
    id_actor: int, 
    id_usuario: int
) -> dict:
    conf = obtener_configuracion()
    token = nuevo_token_opaco()
    fila = await repositorio.generar_enlace_contrasena(
        id_actor,
        id_usuario,
        hash_token(token),
        conf.enlace_contrasena_horas
    )
    return {
        'url': f"{conf.url_web.rstrip('/')}/definir-contrasena?token={token}",
        'correo': fila['correo'],
        'expira_en': fila['expira_en']
    }