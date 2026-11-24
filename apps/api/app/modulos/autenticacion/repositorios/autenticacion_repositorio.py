from datetime import datetime
from uuid import UUID

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def registrar_cliente(correo: str, contrasena_hash: str, nombres: str, apellidos: str, telefono: str,
                            tipo_documento: str, numero_documento: str, pais: str) -> dict:
    return await ejecutar.fila("sp_seguridad_registrar_cliente", correo, contrasena_hash, nombres, apellidos,
                               telefono, tipo_documento, numero_documento, pais)


async def obtener_credenciales(correo: str) -> dict | None:
    return await ejecutar.fila("sp_seguridad_obtener_credenciales", correo)


async def registrar_intento_login(id_usuario: int, exitoso: bool) -> dict | None:
    return await ejecutar.fila("sp_seguridad_registrar_intento_login", id_usuario, exitoso)


async def crear_token_refresco(id_usuario: int, token_hash: str, id_familia: UUID, expira_en: datetime,
                               direccion_ip: str | None, agente_usuario: str | None) -> None:
    await ejecutar.procedimiento("sp_seguridad_crear_token_refresco", id_usuario, token_hash, id_familia,
                                 expira_en, direccion_ip, agente_usuario)


async def obtener_perfil(id_usuario: int) -> dict | None:
    return await ejecutar.fila("sp_seguridad_obtener_perfil", id_usuario)


async def establecer_contrasena_inicial(correo: str, contrasena_hash: str) -> bool:
    return bool(await ejecutar.valor("sp_seguridad_establecer_contrasena_inicial", correo, contrasena_hash))

async def rotar_token_refresco(hash_actual: str, hash_nuevo: str, expira_en: datetime,
                               direccion_ip: str | None, agente_usuario: str | None) -> dict | None:
    return await ejecutar.fila("sp_seguridad_rotar_token_refresco", hash_actual, hash_nuevo, expira_en,
                               direccion_ip, agente_usuario)


async def cerrar_sesion(token_hash: str) -> None:
    await ejecutar.procedimiento("sp_seguridad_cerrar_sesion", token_hash)


async def cerrar_todas_sesiones(id_usuario: int) -> None:
    await ejecutar.procedimiento("sp_seguridad_cerrar_todas_sesiones", id_usuario)


async def cambiar_contrasena(id_usuario: int, contrasena_hash: str) -> None:
    await ejecutar.procedimiento("sp_seguridad_cambiar_contrasena", id_usuario, contrasena_hash)


async def validar_enlace_contrasena(token_hash: str) -> dict | None:
    return await ejecutar.fila("sp_seguridad_validar_enlace_contrasena", token_hash)


async def usar_enlace_contrasena(token_hash: str, contrasena_hash: str) -> int:
    return await ejecutar.valor("sp_seguridad_usar_enlace_contrasena", token_hash, contrasena_hash)