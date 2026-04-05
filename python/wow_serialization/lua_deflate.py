"""
LuaDeflate — WoW custom base64 encode/decode.

Character set: abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()
Encoding: 3-byte groups → 4 chars, little-endian.  Final group: N bytes → N+1 chars.
Decoding: 4-char groups → 3 bytes, little-endian.  Final group: N chars → N-1 bytes.
"""

import base64
import math

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


# ---------------------------------------------------------------------------
# Native variant — uses Python's stdlib base64 with byte/char swapping to
# handle the endianness difference between WoW (little-endian) and standard
# base64 (big-endian).
#
# Encode algorithm (ported from ruby/lua_deflate_native.rb):
#   1. Pad input to multiple of 3 bytes with \x00
#   2. Reverse each 3-byte group (LE → BE)
#   3. base64.b64encode (standard alphabet, no padding chars in output)
#   4. Reverse each 4-char group
#   5. Translate standard base64 alphabet → WoW alphabet
#   6. Trim to ceil(original_length * 4 / 3) chars
#
# Decode algorithm:
#   1. Strip whitespace; reject length <= 1
#   2. Record pre-padding length for byte-count calculation
#   3. Translate WoW alphabet → standard base64 alphabet
#   4. Pad to multiple of 4 with 'A' fill so groups align
#   5. Reverse each 4-char group
#   6. Replace 'A' filler with '=' padding for base64 decode
#   7. base64.b64decode
#   8. Reverse each 3-byte group (BE → LE)
#   9. Trim to (full_groups * 3 + leftover - 1) bytes
# ---------------------------------------------------------------------------

_STD_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
_WOW_ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"

_TO_WOW = str.maketrans(_STD_ALPHA, _WOW_ALPHA)
_FROM_WOW = str.maketrans(_WOW_ALPHA, _STD_ALPHA)


def encode_for_print_native(data: bytes) -> str:
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

    # Step 3: Standard base64 encode
    b64 = base64.b64encode(bytes(buf)).decode("ascii")  # includes trailing '=' padding

    # Step 4: Reverse each 4-char group, then translate alphabet
    # Work on the full b64 string (which is always a multiple of 4 chars)
    b64_list = list(b64)
    for i in range(0, len(b64_list), 4):
        b64_list[i], b64_list[i + 3] = b64_list[i + 3], b64_list[i]
        b64_list[i + 1], b64_list[i + 2] = b64_list[i + 2], b64_list[i + 1]
    reversed_b64 = "".join(b64_list)

    # Step 5: Translate alphabet
    translated = reversed_b64.translate(_TO_WOW)

    # Step 6: Trim to correct output length (some chars may be from padding)
    output_length = math.ceil(original_length * 4 / 3)
    return translated[:output_length]


def decode_for_print_native(encoded: str) -> bytes:
    """Decode a WoW custom base64 string (stdlib base64 variant)."""
    if not isinstance(encoded, str):
        raise TypeError(f"Expected str, got {type(encoded).__name__}")

    encoded = encoded.strip()
    if len(encoded) <= 1:
        return b""

    pre_padding_length = len(encoded)

    # Step 3: Translate WoW → standard base64 alphabet
    b64 = encoded.translate(_FROM_WOW)

    # Step 4: Pad to multiple of 4 with 'A' fill so groups align
    remainder = pre_padding_length % 4
    fill = (4 - remainder) % 4
    b64_padded = b64 + "A" * fill
    # b64_padded is now a multiple of 4 chars — no '=' needed for decode

    # Step 5: Reverse each 4-char group
    b64_list = list(b64_padded)
    for i in range(0, len(b64_list), 4):
        b64_list[i], b64_list[i + 3] = b64_list[i + 3], b64_list[i]
        b64_list[i + 1], b64_list[i + 2] = b64_list[i + 2], b64_list[i + 1]
    b64_for_decode = "".join(b64_list)

    # Step 6: Decode standard base64 (string is already a multiple of 4)
    try:
        decoded = bytearray(base64.b64decode(b64_for_decode))
    except Exception as exc:
        raise ValueError(f"Invalid encoded data: {exc}") from exc

    # Step 7: Reverse each 3-byte group (big-endian → little-endian)
    for i in range(0, len(decoded) - 2, 3):
        decoded[i], decoded[i + 2] = decoded[i + 2], decoded[i]

    # Step 8: Trim to correct byte count; 'A' filler bytes decode to zeros, discarded here
    full_groups, leftover = divmod(pre_padding_length, 4)
    byte_count = full_groups * 3 + (0 if leftover == 0 else leftover - 1)
    return bytes(decoded[:byte_count])
