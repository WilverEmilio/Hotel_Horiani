from datetime import UTC, datetime, timedelta
from uuid import uuid4

from ....config.entorno import obtener_configuracion
from ....shared.errores.error_aplicacion import ErrorAplicacion
from ....shared.utilidades.contrasena import hashear_contrasena, verificar_contrasena
from ....shared.utilidades.tokens import (
    crear_token_acceso,
    hash_token,
    nuevo_token_opaco,
)
from ..esquemas.autenticacion_esquema import InicioSesionEsquema, RegistroClienteEsquema
from ..repositorios import autenticacion_repositorio as repositorio
from ..tipos.autenticacion_tipo import SesionEmitida

_CREDENCIALES_INVALIDAS = ("Correo o contraseña incorrectos", "credenciales_invalidas", 401)


def _vence_refresh() -> datetime:
    return datetime.now(UTC) + timedelta(days=obtener_configuracion().refresh_dias)


def _error_bloqueo(bloqueado_hasta: datetime) -> ErrorAplicacion:
    return ErrorAplicacion("Demasiados intentos fallidos. Intente de nuevo en unos minutos", "cuenta_bloqueada",
                           423, [{"campo": "bloqueadoHasta", "mensaje": bloqueado_hasta.isoformat()}])


async def _abrir_sesion(id_usuario: int, rol: str, ip: str | None, agente: str | None) -> SesionEmitida:
    refresh = nuevo_token_opaco()
    await repositorio.crear_token_refresco(id_usuario, hash_token(refresh), uuid4(), _vence_refresh(), ip, agente)
    acceso, segundos = crear_token_acceso(id_usuario, rol)
    return SesionEmitida(acceso, segundos, refresh, await repositorio.obtener_perfil(id_usuario))


async def registrar_cliente(datos: RegistroClienteEsquema, ip: str | None, agente: str | None) -> SesionEmitida:
    hash_ = await hashear_contrasena(datos.contrasena)
    fila = await repositorio.registrar_cliente(datos.correo, hash_, datos.nombres, datos.apellidos, datos.telefono,
                                               datos.tipo_documento, datos.numero_documento, datos.pais)
    return await _abrir_sesion(fila["id_usuario"], "cliente", ip, agente)


async def iniciar_sesion(datos: InicioSesionEsquema, ip: str | None, agente: str | None) -> SesionEmitida:
    cred = await repositorio.obtener_credenciales(datos.correo)

    if cred and cred["bloqueado_hasta"] and cred["bloqueado_hasta"] > datetime.now(UTC):
        raise _error_bloqueo(cred["bloqueado_hasta"])

    valida = await verificar_contrasena(cred["contrasena_hash"] if cred else None, datos.contrasena)
    if not cred:
        raise ErrorAplicacion(*_CREDENCIALES_INVALIDAS)
    if not valida:
        intento = await repositorio.registrar_intento_login(cred["id_usuario"], False)
        if intento and intento["bloqueado_hasta"]:   # este fue el 5.º intento fallido
            raise _error_bloqueo(intento["bloqueado_hasta"])
        raise ErrorAplicacion(*_CREDENCIALES_INVALIDAS)

    if not cred["activo"]:
        raise ErrorAplicacion("La cuenta está desactivada. Comuníquese con el hotel", "cuenta_inactiva", 401)

    await repositorio.registrar_intento_login(cred["id_usuario"], True)  
    return await _abrir_sesion(cred["id_usuario"], cred["rol"], ip, agente)


async def obtener_perfil(id_usuario: int) -> dict:
    perfil = await repositorio.obtener_perfil(id_usuario)
    if not perfil:
        raise ErrorAplicacion("El usuario no existe", "usuario_no_encontrado", 404)
    return perfil