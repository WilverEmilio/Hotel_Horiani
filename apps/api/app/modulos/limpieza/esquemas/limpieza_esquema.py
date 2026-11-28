from typing import Literal

from ....shared.esquemas.comunes import ConsultaPaginada, EsquemaBase, TextoOpcional


class CrearTareaEsquema(EsquemaBase):
    id_habitacion: int
    observacion: TextoOpcional = None


class AsignarTareaEsquema(EsquemaBase):
    id_empleado: int


class TareasConsulta(ConsultaPaginada):
    id_hotel: int
    estado: Literal["pendiente", "en_proceso", "completada"] | None = None
    solo_mias: bool = False