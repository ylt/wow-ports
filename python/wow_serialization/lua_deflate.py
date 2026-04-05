"""
LuaDeflate — WoW custom base64 encode/decode (reference implementation).

Character set: abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()
Encoding: 3-byte groups → 4 chars, little-endian.  Final group: N bytes → N+1 chars.
Decoding: 4-char groups → 3 bytes, little-endian.  Final group: N chars → N-1 bytes.

Ported from js/lib/LuaDeflate.js and ruby/lua_deflate.rb.
See lua_deflate_native.py for the stdlib base64 variant.
"""

CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
_BYTE_TO_BIT = list(CHARSET)
_BIT_TO_BYTE = {ch: i for i, ch in enumerate(_BYTE_TO_BIT)}


def encode_for_print(data: bytes) -> str:
    """Encode bytes using WoW's custom base64 alphabet."""
    if not isinstance(data, (bytes, bytearray)):
        raise TypeError(f"Expected bytes, got {type(data).__name__}")

    out = []
    for i in range(0, len(data), 3):
        group = data[i : i + 3]
        # Build little-endian 24-bit value from up to 3 bytes
        value = 0
        for shift, byte in enumerate(group):
            value += byte * (256 ** shift)
        # N bytes → N+1 chars
        for idx in range(len(group) + 1):
            out.append(_BYTE_TO_BIT[(value >> (6 * idx)) & 0x3F])

    return "".join(out)


def decode_for_print(encoded: str) -> bytes:
    """Decode a WoW custom base64 string back to bytes."""
    if not isinstance(encoded, str):
        raise TypeError(f"Expected str, got {type(encoded).__name__}")

    encoded = encoded.strip()
    if len(encoded) <= 1:
        return b""

    out = []
    for i in range(0, len(encoded), 4):
        group = encoded[i : i + 4]
        indices = []
        for ch in group:
            idx = _BIT_TO_BYTE.get(ch)
            if idx is None:
                raise ValueError(f"Invalid character in encoded string: {ch!r}")
            indices.append(idx)

        # Build little-endian value
        value = 0
        for pos, idx in enumerate(indices):
            value += idx * (64 ** pos)

        # N chars → N-1 bytes
        bytes_to_take = 3 if len(group) == 4 else len(group) - 1
        for shift in range(bytes_to_take):
            out.append((value >> (8 * shift)) & 0xFF)

    return bytes(out)
