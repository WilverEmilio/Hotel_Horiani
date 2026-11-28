from datetime import date
from typing import Literal

from pydantic import Field, model_validator

from ....shared.esquemas.comunes import ConsultaPaginada, EsquemaBase, Monto, MontoCero
from ...reservaciones.esquemas.reservaciones_esquema import HabitacionPedidaEsquema


class _CamposCupon(EsquemaBase):
    descripcion: str | None = Field(None, max_length=200)
    tipo: Literal["porcentaje", "monto_fijo"]
    valor: Monto = Field(description="Porcentaje (hasta 100) o monto en quetzales")
    fecha_inicio: date
    fecha_fin: date
    monto_minimo: MontoCero = 0
    limite_usos_total: int | None = Field(None, gt=0)
    limite_usos_cliente: int | None = Field(None, gt=0)
    id_hotel: int | None = Field(None, description="Vacío = toda la cadena (solo administrador)")
    id_tipo_habitacion: int | None = None

    @model_validator(mode="after")
    def _reglas(self):
        if self.fecha_fin < self.fecha_inicio:
            raise ValueError("La fecha final no puede ser anterior a la inicial")
        if self.tipo == "porcentaje" and self.valor > 100:
            raise ValueError("El porcentaje no puede superar 100")
        return self


class CrearCuponEsquema(_CamposCupon):
    codigo: str = Field(pattern=r"^[A-Za-z0-9_-]{3,30}$", description="Letras, números, guion y guion bajo")


class ActualizarCuponEsquema(CrearCuponEsquema):
    activo: bool = True


class VistaPreviaEsquema(EsquemaBase):
    codigo: str = Field(min_length=1, max_length=30)
    id_hotel: int
    fecha_entrada: date
    fecha_salida: date
    habitaciones: list[HabitacionPedidaEsquema] = Field(min_length=1, max_length=20)
    id_cliente: int | None = Field(None, description="Solo el personal, para revisar el límite por cliente")


class CuponesConsulta(ConsultaPaginada):
    id_hotel: int | None = None
    busqueda: str | None = Field(None, max_length=100)
    estado: Literal["vigente", "programado", "vencido", "agotado", "inactivo"] | None = None