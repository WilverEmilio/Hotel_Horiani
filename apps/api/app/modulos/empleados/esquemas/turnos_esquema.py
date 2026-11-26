from datetime import date, time

from pydantic import Field

from ....shared.esquemas.comunes import EsquemaBase, EsquemaConsulta, Texto


class CrearTurnoEsquema(EsquemaBase):
    id_hotel: int
    nombre: Texto
    hora_inicio: time
    hora_fin: time

class ActualizarTurnoEsquema(EsquemaBase):
    nombre: Texto
    hora_inicio: time
    hora_fin: time
    activo: bool = True
    
class AsignarTurnoEsquema(EsquemaBase):
    id_turno: int
    fecha_desde: date
    
class FinalizarTurnoEsquema(EsquemaBase):
    fecha_hasta: date = Field(
        description = 'Último dia con el turno (incluido)'
    )

class TurnosConsulta(EsquemaConsulta):
    id_hotel: int
    incluir_inactivos: bool = True
    
