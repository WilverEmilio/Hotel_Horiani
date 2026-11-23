from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse

from ....config.entorno import obtener_configuracion
from ....shared.middleware.autenticacion import ActorDep
from ....shared.utilidades.encabezado import ClienteDep, TipoCliente
from ....shared.utilidades.respuesta import respuesta
from ..esquemas.autenticacion_esquema import InicioSesionEsquema, RegistroClienteEsquema
from ..servicios import autenticacion_servicio as servicio
from ..tipos.autenticacion_tipo import SesionEmitida

RUTA_COOKIE = "/api/v1/auth"   # la cookie solo viaja a las rutas de autenticación


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