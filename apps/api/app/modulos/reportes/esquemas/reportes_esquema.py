from datetime import date
from typing import Literal

from pydantic import Field, model_validator

from ....shared.esquemas.comunes import ConsultaPaginada, EsquemaConsulta


class DashboardConsulta(EsquemaConsulta):
    id_hotel: int   # el resumen del día siempre es de un hotel


class PeriodoConsulta(EsquemaConsulta):
    id_hotel: int | None = Field(None, description="Vacío = los 4 hoteles (solo administrador)")
    fecha_desde: date
    fecha_hasta: date

    @model_validator(mode="after")
    def _rango(self):
        if self.fecha_hasta < self.fecha_desde:
            raise ValueError("La fecha final no puede ser anterior a la inicial")
        return self


class IngresosConsulta(PeriodoConsulta):
    agrupacion: Literal["dia", "semana", "mes"] = "dia"


class ClientesFrecuentesConsulta(PeriodoConsulta):
    limite: int = Field(10, ge=1, le=100)


class CancelacionesConsulta(ConsultaPaginada):
    id_hotel: int | None = Field(None, description="Vacío = los 4 hoteles (solo administrador)")
    fecha_desde: date
    fecha_hasta: date
    tipo: Literal["cancelada", "no_presentado", "expirada"] | None = None


class InventarioReporteConsulta(EsquemaConsulta):
    id_hotel: int          # el inventario es por hotel: no hay consolidado
    fecha_desde: date
    fecha_hasta: date
    clase: Literal["insumo", "blanco"] | None = None