from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import Contrasena, Correo, EsquemaBase, Texto


class RegistroClienteEsquema(EsquemaBase):
    correo: Correo
    contrasena: Contrasena
    nombres: Texto = Field(max_length=100)
    apellidos: Texto = Field(max_length=100)
    telefono: Texto = Field(max_length=20)
    tipo_documento: Literal["dpi", "pasaporte"]
    numero_documento: Texto = Field(max_length=30)
    pais: str = Field("Guatemala", max_length=60)


class InicioSesionEsquema(EsquemaBase):
    correo: Correo
    contrasena: str = Field(min_length=1, max_length=128)
    
    
class TokenRefrescoEsquema(EsquemaBase):
    refresh_token: str | None = Field(None, description="Solo la app móvil; la web usa la cookie")


class CambioContrasenaEsquema(EsquemaBase):
    contrasena_actual: str = Field(min_length=1, max_length=128)
    contrasena_nueva: Contrasena


class DefinirContrasenaEsquema(EsquemaBase):
    token: str = Field(min_length=20, max_length=200)
    contrasena: Contrasena