from datetime import date
from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import (
    ConsultaPaginada,
    EsquemaBase,
    EsquemaConsulta,
    Texto,
    TextoCorto,
)


class ReportarEsquema(EsquemaBase):
    id_hotel: int
    id_habitacion: int | None = Field(None, description="Vacío = área común")
    descripcion: Texto = Field(max_length=1000)


class EstadoReporteEsquema(EsquemaBase):
    estado: Literal["en_proceso", "resuelto"]
    solucion: str | None = Field(None, max_length=1000, description="Obligatoria al resolver")


class BloquearEsquema(EsquemaBase):
    id_habitacion: int
    fecha_inicio: date
    fecha_fin: date = Field(description="Último día bloqueado (incluido)")
    motivo: TextoCorto
    id_reporte: int | None = None


class ReportesConsulta(ConsultaPaginada):
    id_hotel: int
    estado: Literal["reportado", "en_proceso", "resuelto"] | None = None
    id_habitacion: int | None = None


class BloqueosConsulta(EsquemaConsulta):
    id_hotel: int
    fecha_desde: date
    fecha_hasta: date
    incluir_inactivos: bool = False