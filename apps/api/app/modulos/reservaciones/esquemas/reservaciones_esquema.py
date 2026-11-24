from datetime import date
from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import (
    ConsultaPaginada,
    Direccion,
    EsquemaBase,
    EsquemaConsulta,
    TextoCorto,
)

EstadoReservacion = Literal["pendiente_pago", "confirmada", "en_curso", "finalizada", "cancelada", "expirada",
                            "no_presentado"]


class HabitacionPedidaEsquema(EsquemaBase):
    id_tipo_habitacion: int
    huespedes: int = Field(ge=1, le=20)
    id_habitacion: int | None = Field(None, description="Si el cliente escoge el número; si no, el sistema asigna")


class CrearReservacionEsquema(EsquemaBase):
    id_hotel: int
    fecha_entrada: date
    fecha_salida: date
    habitaciones: list[HabitacionPedidaEsquema] = Field(min_length=1, max_length=20)
    codigo_cupon: str | None = Field(None, max_length=30)
    id_cliente: int | None = Field(None, description="Obligatorio cuando reserva el personal; el cliente lo omite")


class ReasignarHabitacionEsquema(EsquemaBase):
    id_habitacion_nueva: int
    motivo: TextoCorto


class DisponibilidadConsulta(EsquemaConsulta):
    fecha_entrada: date
    fecha_salida: date
    huespedes: int = Field(1, ge=1, le=20)


class FechasConsulta(EsquemaConsulta):
    fecha_entrada: date
    fecha_salida: date


class ReservacionesConsulta(ConsultaPaginada):
    id_hotel: int
    estado: EstadoReservacion | None = None
    id_cliente: int | None = None
    fecha_desde: date | None = None
    fecha_hasta: date | None = None
    busqueda: str | None = Field(None, max_length=100, description="Código, nombre, documento o correo")
    ordenar_por: Literal["fechaEntrada", "creadoEn", "total", "codigo"] = "fechaEntrada"
    direccion: Direccion = "desc"


def habitaciones_para_bd(habitaciones: list[HabitacionPedidaEsquema]) -> list[dict]:
    """El stored procedure espera las claves en snake_case."""
    return [h.model_dump(exclude_none=True) for h in habitaciones]