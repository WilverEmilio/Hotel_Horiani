from datetime import date
from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import (
    ConsultaPaginada,
    Direccion,
    EsquemaBase,
    Monto,
    TextoCorto,
)


class PagoEnHotelEsquema(EsquemaBase):
    tipo: Literal["anticipo", "saldo"]
    metodo: Literal["efectivo", "tarjeta_en_hotel"]
    monto: Monto


class ReembolsoEsquema(EsquemaBase):
    monto: Monto
    motivo: TextoCorto
    referencia_pasarela: str | None = Field(None, max_length=100, description="Número de la devolución en el banco")


class PagosConsulta(ConsultaPaginada):
    id_hotel: int
    tipo: Literal["anticipo", "saldo", "reembolso"] | None = None
    metodo: Literal["pasarela", "efectivo", "tarjeta_en_hotel"] | None = None
    estado: Literal["pendiente", "aprobado", "rechazado", "expirado", "anulado"] | None = None
    fecha_desde: date | None = None
    fecha_hasta: date | None = None
    ordenar_por: Literal["confirmadoEn", "monto", "creadoEn"] = "creadoEn"
    direccion: Direccion = "desc"