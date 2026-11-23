from dataclasses import dataclass
from typing import Annotated
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from ..errores.error_aplicacion import ErrorAplicacion
from ..utilidades.tokens import leer_token_acceso

_bearer = HTTPBearer(
    auto_error = False,
    description = "Access token de /auth/iniciar-sesion"
)

@dataclass (frozen=True)
class Actor: 
    id_usuario: int
    rol: str
    
def _no_autenticado(mensaje: str) -> ErrorAplicacion:
    return ErrorAplicacion(
        mensaje,
        'No_Autenticado',
        401,
        encabezados={"WWW-Authenticate": "Bearer"}
    )
    
async def autenticar(
    credenciales: Annotated[
        HTTPAuthorizationCredentials | None, 
        Depends(_bearer)
    ]) -> Actor:
    
    if credenciales is None or credenciales.scheme.lower() != 'bearer':
        raise _no_autenticado("Debes iniciar sesión para acceder a este recurso")
    carga = leer_token_acceso(credenciales.credentials)
    if carga is None: 
        raise _no_autenticado('La sesión no es válida o expiro')
    return Actor(
        id_usuario = int (
            carga[
                'sub'
            ]
        ),
        rol = carga[
            'rol'
        ]
    )
    
ActorDep = Annotated[Actor, Depends(autenticar)]