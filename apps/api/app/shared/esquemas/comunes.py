from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints
from pydantic.alias_generators import to_camel


class EsquemaBase(BaseModel):
    model_config = ConfigDict(
        alias_generator = to_camel,
        populate_by_name = True,
        extra = 'forbid',
        str_strip_whitespace = True
    )

class EsquemaConsulta(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel, 
        populate_by_name=True, 
        extra="ignore",
        str_strip_whitespace=True
        )


class ConsultaPaginada(EsquemaConsulta):
    pagina: int = Field(1, ge=1, description="Página, desde 1")
    registros_por_pagina: int = Field(20, ge=1, le=100, description="Registros por página (máximo 100)")
    
class CambiarEstadoEsquema(EsquemaBase):
    activo: bool

class OrdenIdsEsquema(EsquemaBase):
    ids: list[int] = Field(min_length=1, description="Ids en el orden deseado")


Direccion = Literal["asc", "desc"]

Correo = Annotated[str, StringConstraints(strip_whitespace=True, max_length=254,
                                          pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")]
Texto = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
TextoCorto = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=300)]
TextoOpcional = Annotated[str | None, StringConstraints(strip_whitespace=True, max_length=300)]
Contrasena = Annotated[str, Field(min_length=8, max_length=128, description="Entre 8 y 128 caracteres")]
Monto = Annotated[Decimal, Field(gt=0, max_digits=10, decimal_places=2)]
MontoCero = Annotated[Decimal, Field(ge=0, max_digits=10, decimal_places=2)]
Cantidad = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=2)]
CantidadCero = Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)]
Porcentaje = Annotated[Decimal, Field(ge=0, le=100, max_digits=5, decimal_places=2)]

class MotivoEsquema(EsquemaBase):
    motivo: TextoCorto
    
class ObservacionEsquema(EsquemaBase):
    observacion: TextoOpcional = None