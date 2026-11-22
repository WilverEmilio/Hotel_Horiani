from typing import Any

from pydantic.alias_generators import to_camel, to_snake


def a_camel(valor: Any,
            conservar: frozenset[str] = frozenset()) -> Any:
    if isinstance(valor, dict):
        return {
            (to_camel(k) if isinstance(k, str) else k): (v if k in conservar else a_camel(v, conservar))
            for k, v in valor.items()
        }
    if isinstance(valor, list):
        return [a_camel(v, conservar) for v in valor]
    return valor

def a_snake(texto: str) -> str:
    return to_snake(texto)