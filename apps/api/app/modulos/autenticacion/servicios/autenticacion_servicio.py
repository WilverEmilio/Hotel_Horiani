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
from ..esquemas.autenticacion_esquema import (
    CambioContrasenaEsquema,
    DefinirContrasenaEsquema,
    InicioSesionEsquema,
    RegistroClienteEsquema,
)
from ..repositorios import autenticacion_repositorio as repositorio
from ..tipos.autenticacion_tipo import SesionEmitida

_CREDENCIALES_INVALIDAS = ("Correo o contraseña incorrectos", "credenciales_invalidas", 401)
_ENLACE_INVALIDO = ('El enlace no es válido o ya venció. Solicite uno nuevo',
                    'enlace_invalido',
                    422)


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
        if intento and intento["bloqueado_hasta"]:  
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

async def renovar(refresh_actual: str | None, ip: str | None, agente: str | None) -> SesionEmitida | str:
    """Devuelve la sesión nueva, o el código de error ('sesion_invalida' / 'sesion_reutilizada')."""
    if not refresh_actual:
        return "sesion_invalida"
    nuevo = nuevo_token_opaco()
    fila = await repositorio.rotar_token_refresco(hash_token(refresh_actual), hash_token(nuevo),
                                                  _vence_refresh(), ip, agente)
    if not fila or fila["resultado"] != "valido":
        return "sesion_reutilizada" if fila and fila["resultado"] == "reutilizado" else "sesion_invalida"
    acceso, segundos = crear_token_acceso(fila["id_usuario"], fila["rol"])
    return SesionEmitida(acceso, segundos, nuevo)


async def cerrar_sesion(refresh_actual: str | None) -> None:
    if refresh_actual:
        await repositorio.cerrar_sesion(hash_token(refresh_actual))


async def cerrar_todas_sesiones(id_usuario: int) -> None:
    await repositorio.cerrar_todas_sesiones(id_usuario)


async def cambiar_contrasena(id_usuario: int, datos: CambioContrasenaEsquema) -> None:
    perfil = await obtener_perfil(id_usuario)
    cred = await repositorio.obtener_credenciales(perfil["correo"])
    if not await verificar_contrasena(cred["contrasena_hash"] if cred else None, datos.contrasena_actual):
        raise ErrorAplicacion("La contraseña actual no es correcta", "contrasena_actual_incorrecta", 422)
    if datos.contrasena_actual == datos.contrasena_nueva:
        raise ErrorAplicacion("La nueva contraseña debe ser distinta de la actual", "contrasena_igual", 422)
    await repositorio.cambiar_contrasena(id_usuario, await hashear_contrasena(datos.contrasena_nueva))


async def validar_enlace(token: str) -> dict:
    fila = await repositorio.validar_enlace_contrasena(hash_token(token))
    if not fila:
        raise ErrorAplicacion(*_ENLACE_INVALIDO)
    return fila


async def usar_enlace(datos: DefinirContrasenaEsquema) -> None:
    await repositorio.usar_enlace_contrasena(hash_token(datos.token), await hashear_contrasena(datos.contrasena))