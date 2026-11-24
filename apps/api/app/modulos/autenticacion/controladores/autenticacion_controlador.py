from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse

from ....config.entorno import obtener_configuracion
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.encabezado import ClienteDep, TipoCliente
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.autenticacion_esquema import (
    CambioContrasenaEsquema,
    DefinirContrasenaEsquema,
    InicioSesionEsquema,
    RegistroClienteEsquema,
    TokenRefrescoEsquema,
)
from ..servicios import autenticacion_servicio as servicio
from ..tipos.autenticacion_tipo import SesionEmitida

RUTA_COOKIE = "/api/v1/auth"  


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _agente(request: Request) -> str | None:
    ua = request.headers.get("user-agent")
    return ua[:300] if ua else None


def _poner_cookie(resp: JSONResponse, token: str) -> None:
    conf = obtener_configuracion()
    resp.set_cookie(conf.cookie_nombre, token, max_age=conf.refresh_dias * 86400, httponly=True,
                    secure=conf.cookie_segura, samesite=conf.cookie_samesite, domain=conf.cookie_dominio,
                    path=RUTA_COOKIE)
    
def _borrar_cookie(resp: JSONResponse) -> None:
    conf = obtener_configuracion()
    resp.delete_cookie(conf.cookie_nombre, domain=conf.cookie_dominio, path=RUTA_COOKIE,
                       secure=conf.cookie_segura, httponly=True, samesite=conf.cookie_samesite)


def _refresh_recibido(request: Request, cuerpo: TokenRefrescoEsquema | None) -> str | None:
    """Móvil: viene en el cuerpo. Web: viene en la cookie."""
    if cuerpo and cuerpo.refresh_token:
        return cuerpo.refresh_token
    return request.cookies.get(obtener_configuracion().cookie_nombre)


def _respuesta_sesion(mensaje: str, sesion: SesionEmitida, cliente: TipoCliente, estado: int = 200) -> JSONResponse:
    datos = {"access_token": sesion.access_token, "token_type": "bearer", "expira_en": sesion.expira_en}
    if cliente == "movil":
        datos["refresh_token"] = sesion.refresh_token
    if sesion.usuario is not None:
        datos["usuario"] = sesion.usuario
    resp = JSONResponse(status_code=estado, content=jsonable_encoder(respuesta(mensaje, datos)))
    if cliente == "web":
        _poner_cookie(resp, sesion.refresh_token)
    return resp


async def registrar(datos: RegistroClienteEsquema, request: Request, cliente: ClienteDep):
    sesion = await servicio.registrar_cliente(datos, _ip(request), _agente(request))
    return _respuesta_sesion("Cuenta creada correctamente", sesion, cliente, 201)


async def iniciar_sesion(datos: InicioSesionEsquema, request: Request, cliente: ClienteDep):
    sesion = await servicio.iniciar_sesion(datos, _ip(request), _agente(request))
    return _respuesta_sesion("Sesión iniciada correctamente", sesion, cliente)


async def perfil(actor: ActorDep):
    return respuesta("Perfil obtenido correctamente", await servicio.obtener_perfil(actor.id_usuario))

async def renovar(request: Request, cliente: ClienteDep, cuerpo: TokenRefrescoEsquema | None = None):
    resultado = await servicio.renovar(_refresh_recibido(request, cuerpo), _ip(request), _agente(request))
    if isinstance(resultado, str):
        resp = JSONResponse(status_code=401, content={
            "codigo": resultado, "mensaje": "La sesión no es válida o expiró. Inicie sesión de nuevo"})
        _borrar_cookie(resp)
        return resp
    return _respuesta_sesion("Sesión renovada correctamente", resultado, cliente)


async def cerrar_sesion(request: Request, cuerpo: TokenRefrescoEsquema | None = None):
    await servicio.cerrar_sesion(_refresh_recibido(request, cuerpo))
    resp = JSONResponse(status_code=200, content=respuesta("Sesión cerrada correctamente"))
    _borrar_cookie(resp)
    return resp


async def cerrar_todas(actor: ActorDep):
    await servicio.cerrar_todas_sesiones(actor.id_usuario)
    resp = JSONResponse(status_code=200, content=respuesta("Se cerraron todas las sesiones"))
    _borrar_cookie(resp)
    return resp


async def cambiar_contrasena(datos: CambioContrasenaEsquema, actor: ActorDep):
    await servicio.cambiar_contrasena(actor.id_usuario, datos)
    resp = JSONResponse(status_code=200, content=respuesta("Contraseña cambiada correctamente. Inicie sesión de nuevo"))
    _borrar_cookie(resp)
    return resp


async def validar_enlace(token: str):
    return respuesta("Enlace válido", await servicio.validar_enlace(token))


async def usar_enlace(datos: DefinirContrasenaEsquema):
    await servicio.usar_enlace(datos)
    return respuesta("Contraseña definida correctamente")