from datetime import date
from typing import Literal

from pydantic import Field, model_validator

from ....shared.esquemas.comunes import (
    ConsultaPaginada,
    Contrasena,
    Correo,
    Direccion,
    EsquemaBase,
    Texto,
)

RolPersonal = Literal["administrador", "operador", "oficinista", "limpieza", "lavanderia"]


class CrearEmpleadoEsquema(EsquemaBase):
    nombres: Texto
    apellidos: Texto
    dpi: str = Field(pattern=r"^[0-9]{13}$", description="13 dígitos, sin espacios ni guiones")
    telefono: str | None = None
    puesto: Texto
    fecha_ingreso: date
    ids_hotel: list[int] = Field(min_length=1)
    correo: Correo | None = Field(None, description="Si se envía, se crea su usuario con el rol indicado")
    rol: RolPersonal | None = None
    contrasena: Contrasena | None = Field(None, description="Contraseña temporal; obligatoria si se crea el usuario")

    @model_validator(mode="after")
    def _usuario_completo(self):
        if not ((self.correo is None) == (self.rol is None) == (self.contrasena is None)):
            raise ValueError("Para crear el usuario se necesitan correo, rol y contraseña temporal")
        return self


class ActualizarEmpleadoEsquema(EsquemaBase):
    nombres: Texto
    apellidos: Texto
    telefono: str | None = None
    puesto: Texto


class HotelesEmpleadoEsquema(EsquemaBase):
    ids_hotel: list[int] = Field(min_length=1)


class UsuarioEmpleadoEsquema(EsquemaBase):
    correo: Correo
    rol: RolPersonal
    contrasena: Contrasena = Field(description="Contraseña temporal; el empleado la cambia desde su perfil")


class RolEmpleadoEsquema(EsquemaBase):
    rol: RolPersonal


class BajaEmpleadoEsquema(EsquemaBase):
    fecha_baja: date


class EmpleadosConsulta(ConsultaPaginada):
    id_hotel: int | None = Field(None, description="Obligatorio si no es administrador")
    busqueda: str | None = Field(None, max_length=100)
    activo: bool | None = True
    ordenar_por: Literal["nombre", "fechaIngreso", "puesto"] = "nombre"
    direccion: Direccion = "asc"