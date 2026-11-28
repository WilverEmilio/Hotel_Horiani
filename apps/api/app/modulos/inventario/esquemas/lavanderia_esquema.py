from datetime import date
from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import (
    CantidadCero,
    ConsultaPaginada,
    EsquemaBase,
    TextoOpcional,
)
from .inventario_esquema import ItemEsquema


class ItemDevueltoEsquema(EsquemaBase):
    id_articulo: int
    cantidad: CantidadCero      


class RecibirLoteEsquema(EsquemaBase):
    id_hotel: int
    items: list[ItemEsquema] = Field(min_length=1)
    observacion: TextoOpcional = None


class DevolverLoteEsquema(EsquemaBase):
    items: list[ItemDevueltoEsquema] = Field(
        min_length=1, description="Cantidad devuelta por artículo; lo que falte queda como faltante")
    observacion: TextoOpcional = None


class LotesConsulta(ConsultaPaginada):
    id_hotel: int
    estado: Literal["recibido", "devuelto"] | None = None
    fecha_desde: date | None = None
    fecha_hasta: date | None = None