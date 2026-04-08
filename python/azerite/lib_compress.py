"""
Clean-room implementation of LibCompress decompression.

Written from the wire format specification only — NOT derived from
the GPL-licensed LibCompress.lua source code.

Method markers: 0x01 = uncompressed, 0x02 = LZW, 0x03 = Huffman
"""


class LibCompressError(Exception):
    pass


def decompress(data: bytes) -> bytes:
    if not data:
        raise LibCompressError("Cannot decompress empty data")

    method = data[0]
    if method == 1:
        return data[1:]
    if method == 2:
        return _decompress_lzw(data)
    if method == 3:
        return _decompress_huffman(data)
    raise LibCompressError(f"Unknown compression method ({method})")


# ── LZW ──────────────────────────────────────────────────────────────────────

def _decompress_lzw(data: bytes) -> bytes:
    pos = 1  # skip method byte
    dict_entries: dict[int, bytes] = {i: bytes([i]) for i in range(256)}
    dict_size = 256

    code, delta = _read_code(data, pos)
    pos += delta
    w = dict_entries[code]
    result = [w]

    while pos < len(data):
        code, delta = _read_code(data, pos)
        pos += delta

        if code < dict_size:
            entry = dict_entries[code]
        else:
            entry = w + w[0:1]  # special case: code not yet in dict

        result.append(entry)
        dict_entries[dict_size] = w + entry[0:1]
        dict_size += 1
        w = entry

    return b"".join(result)


def _read_code(data: bytes, pos: int) -> tuple[int, int]:
    """Read a variable-length LZW code from the byte stream."""
    a = data[pos]
    if a < 250:
        return (a, 1)
    count = 256 - a
    r = 0
    for n in range(pos + count, pos, -1):
        r = r * 255 + data[n] - 1
    return (r, count + 1)


# ── Huffman ──────────────────────────────────────────────────────────────────

def _decompress_huffman(data: bytes) -> bytes:
    buf_size = len(data)

    # Header
    num_symbols = data[1] + 1
    orig_size = data[2] | (data[3] << 8) | (data[4] << 16)
    if orig_size == 0:
        return b""

    # Read symbol→code map from bitstream
    bitfield = 0
    bitfield_len = 0
    byte_pos = 5  # first byte after header

    code_map: dict[int, dict[int, int]] = {}  # map[code_len][code] = symbol_byte
    min_code_len = None
    max_code_len = 0
    symbols_read = 0
    state = "symbol"
    symbol = 0

    while symbols_read < num_symbols:
        if byte_pos >= buf_size:
            raise LibCompressError("Truncated Huffman map")

        bitfield |= data[byte_pos] << bitfield_len
        bitfield_len += 8

        if state == "symbol":
            symbol = bitfield & 0xFF
            bitfield >>= 8
            bitfield_len -= 8
            state = "code"
        else:
            code_result = _extract_escaped_code(bitfield, bitfield_len)
            if code_result is not None:
                code, code_len, bitfield, bitfield_len = code_result
                unescaped, ul = _unescape(code, code_len)

                if ul not in code_map:
                    code_map[ul] = {}
                code_map[ul][unescaped] = symbol
                if min_code_len is None or ul < min_code_len:
                    min_code_len = ul
                if ul > max_code_len:
                    max_code_len = ul
                symbols_read += 1
                state = "symbol"

        byte_pos += 1

    # Decode compressed data
    result = bytearray()
    dec_size = 0
    test_len = min_code_len

    while True:
        if test_len <= bitfield_len:
            test_code = bitfield & ((1 << test_len) - 1)
            sym = code_map.get(test_len, {}).get(test_code)
            if sym is not None:
                result.append(sym)
                dec_size += 1
                if dec_size >= orig_size:
                    break
                bitfield >>= test_len
                bitfield_len -= test_len
                test_len = min_code_len
            else:
                test_len += 1
                if test_len > max_code_len:
                    raise LibCompressError("Huffman decode error: code too long")
        else:
            c = data[byte_pos] if byte_pos < buf_size else 0
            bitfield |= c << bitfield_len
            bitfield_len += 8
            if byte_pos > buf_size:
                break
            byte_pos += 1

    return bytes(result)


def _extract_escaped_code(
    bitfield: int, field_len: int
) -> tuple[int, int, int, int] | None:
    """Find escaped Huffman code terminated by two consecutive set bits."""
    if field_len < 2:
        return None

    prev = 0
    for i in range(field_len):
        bit = bitfield & (1 << i)
        if prev != 0 and bit != 0:
            code = bitfield & ((1 << (i - 1)) - 1)
            remaining = bitfield >> (i + 1)
            remaining_len = field_len - i - 1
            return (code, i - 1, remaining, remaining_len)
        prev = bit

    return None


def _unescape(code: int, code_len: int) -> tuple[int, int]:
    """Remove escape encoding: 1-bit encoded as '11', 0-bit as '0'."""
    unescaped = 0
    out_pos = 0
    i = 0
    while i < code_len:
        bit = code & (1 << i)
        if bit != 0:
            unescaped |= 1 << out_pos
            i += 1  # skip paired 1-bit
        i += 1
        out_pos += 1
    return (unescaped, out_pos)
