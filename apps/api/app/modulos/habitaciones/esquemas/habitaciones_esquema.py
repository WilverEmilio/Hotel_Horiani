from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import ConsultaPaginada, Direccion, EsquemaBase, Texto

EstadoHabitacion = Literal["disponible", "ocupada", "en_limpieza", "en_mantenimiento", "fuera_de_servicio"]


class CrearHabitacionEsquema(EsquemaBase):
    id_hotel: int
    id_tipo_habitacion: int
    numero: Texto
    piso: int | None = None


class ActualizarHabitacionEsquema(EsquemaBase):
    id_tipo_habitacion: int
    numero: Texto
    piso: int | None = None


class EstadoHabitacionEsquema(EsquemaBase):
    estado: EstadoHabitacion


class HabitacionesConsulta(ConsultaPaginada):
    id_hotel: int
    estado: EstadoHabitacion | None = None
    id_tipo_habitacion: int | None = None
    busqueda: str | None = Field(None, max_length=100)
    incluir_inactivas: bool = False
    ordenar_por: Literal["numero", "piso", "estado", "tipo"] = "numero"
    direccion: Direccion = "asc"