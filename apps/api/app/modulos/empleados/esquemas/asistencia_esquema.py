from datetime import date
from typing import Literal

from pydantic import Field

from ....shared.esquemas.comunes import (
    ConsultaPaginada,
    EsquemaBase,
    EsquemaConsulta,
    TextoOpcional,
)

EstadoAsistencia = Literal[
    'asistio',
    'llegada_tarde',
    'falto',
    'permiso',
    'descanso',
    'vacaciones',
    'suspension'
]

class RegistrearAsistenciaEsquema(EsquemaBase):
    id_empleado: int
    id_hotel: int
    fecha: date
    id_turno: int | None = Field(None, 
                                 description= 'Obligatorio para asistió, llegada tarde y faltó')
    estado: EstadoAsistencia
    observacion: TextoOpcional = None
    
class RegistrarRangoEsquema(EsquemaBase):
    id_empleado: int
    id_hotel: int
    fecha_desde: date
    fecha_hasta: date
    estado: Literal[
        'permiso',
        'descanso',
        'vacaciones',
        'suspension'
    ]
    observacion: TextoOpcional = None

class HojaDelDiaConsulta(EsquemaConsulta):
    id_hotel: int
    fecha: date 

class AsistenciaConsulta(ConsultaPaginada):
    id_hotel: int
    fecha_desde: date
    fecha_hasta: date
    id_empleado: int | None = None
    estado: EstadoAsistencia | None = None
    
class ResumenAsistenciaConsulta(EsquemaConsulta):
    id_hotel: int
    fecha_desde: date
    fecha_hasta: date
    