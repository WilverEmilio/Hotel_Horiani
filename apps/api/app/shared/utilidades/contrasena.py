import asyncio

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

_hasher = PasswordHasher()
_HASH_FICTICIO = _hasher.hash('contrasena-ficticia-para-igualar-tiempos')

def _verificar(hash_guardado: str | None, contrasena: str) -> bool:
    try: 
        return _hasher.verify(hash_guardado or _HASH_FICTICIO, contrasena) and hash_guardado is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False
    

async def hashear_contrasena(contrasena: str) -> str:
    return await asyncio.to_thread(_hasher.hash, contrasena)

async def verificar_contrasena(hash_guardado: str | None, contrasena: str) -> bool:
    return await asyncio.to_thread(_verificar, hash_guardado, contrasena)