import hashlib
import secrets
from datetime import UTC, datetime, timedelta

import jwt

from ...config.entorno import obtener_configuracion

_ALGORITMO = 'HS256'
_EMISOR = 'horiani-api'

def crear_token_acceso(id_usuario: int, rol: str) -> tuple[str, int]:
    conf = obtener_configuracion()
    ahora = datetime.now(UTC)
    segundos = conf.jwt_minutos_acceso * 60
    carga = {
        'sub': str(id_usuario),
        'rol': rol,
        'iss': _EMISOR,
        'iat': ahora,
        'exp': ahora + timedelta(seconds=segundos),
        'typ': 'acceso'
    }
    return jwt.encode(
        carga,
        conf.jwt_secreto.get_secret_value(),
        algorithm = _ALGORITMO,
        
    ), segundos
    
def leer_token_acceso(token: str) -> dict | None:
    conf = obtener_configuracion()
    try:
        carga = jwt.decode(
            token, 
            conf.jwt_secreto.get_secret_value(),
            algorithms = [_ALGORITMO],
            issuer = _EMISOR,
            options = {
                'require': [
                    'exp', 
                    'sub',
                    'iss'
                ]
            }
        )
    except jwt.PyJWTError:
        return None
    if carga.get('typ') != 'acceso' or not str(
        carga.get('sub', '')
    ).isdigit():
        return None
    return carga

def nuevo_token_opaco() -> str:
    return secrets.token_urlsafe(32)

def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode('utf-8')).hexdigest()