from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import (
    ConsultaPaginada,
    Correo,
    Direccion,
    EsquemaBase,
    Texto,
)

TipoDocumento = Literal["dpi", "pasaporte"]


class RegistrarClienteEsquema(EsquemaBase):
    nombres: Texto
    apellidos: Texto
    telefono: Texto
    tipo_documento: TipoDocumento
    numero_documento: Texto
    pais: str = "Guatemala"
    correo: Correo | None = Field(None, description="Si se envía, se crea su cuenta sin contraseña")


class ActualizarClienteEsquema(EsquemaBase):
    nombres: Texto
    apellidos: Texto
    telefono: Texto
    tipo_documento: TipoDocumento
    numero_documento: Texto
    pais: str = "Guatemala"


class MiPerfilEsquema(EsquemaBase):
    nombres: Texto
    apellidos: Texto
    telefono: Texto
    pais: str = "Guatemala"


class CuentaEsquema(EsquemaBase):
    correo: Correo


class ClientesConsulta(ConsultaPaginada):
    busqueda: str | None = Field(None, max_length=100, description="Nombre, documento, teléfono o correo")
    activo: bool | None = None
    ordenar_por: Literal["nombre", "creadoEn", "estancias", "totalPagado"] = "nombre"
    direccion: Direccion = "asc"