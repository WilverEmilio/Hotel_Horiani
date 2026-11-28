from datetime import date

from pydantic import Field

from ....shared.esquemas.comunes import ConsultaPaginada


class BitacoraConsulta(ConsultaPaginada):
    id_hotel: int | None = None
    modulo: str | None = None
    entidad: str | None = None
    id_registro: str | None = None
    id_usuario: int | None = None
    accion: str | None = None
    fecha_desde: date | None = None
    fecha_hasta: date | None = None
    busqueda: str | None = Field(None, max_length=100, description="Busca dentro de los valores anterior y nuevo")