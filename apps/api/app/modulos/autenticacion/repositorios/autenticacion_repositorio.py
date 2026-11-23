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