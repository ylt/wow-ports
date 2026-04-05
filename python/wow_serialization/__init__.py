from .lua_deflate import encode_for_print, decode_for_print
from .lua_deflate_native import encode_for_print as encode_for_print_native
from .lua_deflate_native import decode_for_print as decode_for_print_native

__all__ = [
    "encode_for_print",
    "decode_for_print",
    "encode_for_print_native",
    "decode_for_print_native",
]
