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