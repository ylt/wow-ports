"""
LuaDeflateNative — stdlib base64 variant of LuaDeflate encode/decode.

Uses Python's base64 module with byte/char group swapping to handle the
endianness difference between WoW (little-endian) and standard base64
(big-endian). Produces identical output to lua_deflate.py.

Algorithm ported from ruby/lua_deflate_native.rb and js/lib/LuaDeflateNative.js.

Encode:
  1. Pad input to multiple of 3 bytes with \\x00
  2. Reverse each 3-byte group (LE → BE)
  3. base64.b64encode
  4. Reverse each 4-char group
  5. Translate standard base64 alphabet → WoW alphabet
  6. Trim to ceil(n * 4 / 3) chars

Decode:
  1. Strip whitespace; reject length <= 1
  2. Translate WoW alphabet → standard base64 alphabet
  3. Pad to multiple of 4 with 'A' fill
  4. Reverse each 4-char group
  5. base64.b64decode
  6. Reverse each 3-byte group (BE → LE)
  7. Trim to correct byte count
"""

import base64
import math
from typing import Any

_STD_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
_WOW_ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"

_TO_WOW = str.maketrans(_STD_ALPHA, _WOW_ALPHA)
_FROM_WOW = str.maketrans(_WOW_ALPHA, _STD_ALPHA)


def encode_for_print(data: bytes) -> str:
    """Encode bytes using WoW's custom base64 alphabet (stdlib base64 variant)."""
    if not isinstance(data, (bytes, bytearray)):
        raise TypeError(f"Expected bytes, got {type(data).__name__}")

    original_length = len(data)
    if original_length == 0:
        return ""

    # Step 1: Pad to multiple of 3
    remainder = original_length % 3
    padded = data if remainder == 0 else data + b"\x00" * (3 - remainder)

    # Step 2: Reverse each 3-byte group (little-endian → big-endian)
    buf = bytearray(padded)
    for i in range(0, len(buf), 3):
        buf[i], buf[i + 2] = buf[i + 2], buf[i]

    # Step 3: Standard base64 encode (includes trailing '=' padding)
    b64 = base64.b64encode(bytes(buf)).decode("ascii")

    # Step 4: Reverse each 4-char group
    b64_list = list(b64)
    for i in range(0, len(b64_list), 4):
        b64_list[i], b64_list[i + 3] = b64_list[i + 3], b64_list[i]
        b64_list[i + 1], b64_list[i + 2] = b64_list[i + 2], b64_list[i + 1]

    # Step 5: Translate alphabet
    translated = "".join(b64_list).translate(_TO_WOW)

    # Step 6: Trim to correct output length
    output_length = math.ceil(original_length * 4 / 3)
    return translated[:output_length]


def decode_for_print(encoded: Any) -> bytes | None:
    """Decode a WoW custom base64 string (stdlib base64 variant)."""
    if isinstance(encoded, (bytes, bytearray)):
        encoded = encoded.decode("latin-1")
    if not isinstance(encoded, str):
        return None

    encoded = encoded.strip()
    if len(encoded) == 0:
        return b""
    if len(encoded) == 1:
        return None

    # Validate all chars are in the WoW alphabet
    import re
    if not re.fullmatch(r'[a-zA-Z0-9()]+', encoded):
        return None

    pre_padding_length = len(encoded)

    # Step 2: Translate WoW → standard base64 alphabet
    b64 = encoded.translate(_FROM_WOW)

    # Step 3: Pad to multiple of 4 with 'A' fill so groups align
    remainder = pre_padding_length % 4
    fill = (4 - remainder) % 4
    b64_padded = b64 + "A" * fill
    # Already a multiple of 4 — no '=' padding needed

    # Step 4: Reverse each 4-char group
    b64_list = list(b64_padded)
    for i in range(0, len(b64_list), 4):
        b64_list[i], b64_list[i + 3] = b64_list[i + 3], b64_list[i]
        b64_list[i + 1], b64_list[i + 2] = b64_list[i + 2], b64_list[i + 1]
    b64_for_decode = "".join(b64_list)

    # Step 5: Decode standard base64
    try:
        decoded = bytearray(base64.b64decode(b64_for_decode))
    except Exception as exc:
        raise ValueError(f"Invalid encoded data: {exc}") from exc

    # Step 6: Reverse each 3-byte group (big-endian → little-endian)
    for i in range(0, len(decoded) - 2, 3):
        decoded[i], decoded[i + 2] = decoded[i + 2], decoded[i]

    # Step 7: Trim to correct byte count; 'A' filler decodes to zeros, discarded here
    full_groups, leftover = divmod(pre_padding_length, 4)
    byte_count = full_groups * 3 + (0 if leftover == 0 else leftover - 1)
    return bytes(decoded[:byte_count])
