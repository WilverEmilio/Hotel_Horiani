from datetime import date, time

from ....shared.base_de_datos import ejecutar_procedimiento as ejecutar


async def crear(
    id_actor: int,
    id_hotel: int,
    nombre: str,
    hora_inicio: time,
    hora_fin: time
) -> int:
    return await ejecutar.valor(
        'sp_turnos_crear',
        id_actor,
        id_hotel,
        nombre,
        hora_inicio,
        hora_fin
    )

async def actualizar(
    id_actor: int, 
    id_turno: int, 
    nombre: str, 
    hora_inicio: time, 
    hora_fin: time,
    activo: bool
) -> None:
    await ejecutar.procedimiento(
        "sp_turnos_actualizar", 
        id_actor, 
        id_turno, 
        nombre, 
        hora_inicio, 
        hora_fin, 
        activo
    )


async def listar(
    id_actor: int, 
    id_hotel: int, 
    incluir_inactivos: bool
) -> list[dict]:
    return await ejecutar.filas(
        "sp_turnos_listar", 
        id_actor, 
        id_hotel, 
        incluir_inactivos
    )

async def asignar(
    id_actor: int, 
    id_empleado: int, 
    id_turno: int, 
    fecha_desde: date
) -> int:
    return await ejecutar.valor(
        "sp_empleados_asignar_turno", 
        id_actor, 
        id_empleado, 
        id_turno, 
        fecha_desde
    )


async def finalizar(
    id_actor: int, 
    id_empleado_turno: int, 
    fecha_hasta: date
) -> None:
    await ejecutar.procedimiento(
        "sp_empleados_finalizar_turno", 
        id_actor, 
        id_empleado_turno, 
        fecha_hasta
    )