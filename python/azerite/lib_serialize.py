"""
LibSerialize — Python port of the Ruby LibSerialize implementation.

Ported from ruby/lib_serialize.rb.

Binary type-length-value serialization format used by WoW addons.
Uses big-endian byte order for all multi-byte integers and floats.

struct equivalents for Ruby pack/unpack:
  'G' (big-endian double)  → struct.pack('>d', n)
  'n' (uint16 BE)          → struct.pack('>H', n)
  'N' (uint32 BE)          → struct.pack('>I', n)
  'C' (uint8)              → bytes([n])
"""

import struct

# ---------------------------------------------------------------------------
# Constants (shared by serializer and deserializer)
# ---------------------------------------------------------------------------

EMBEDDED_INDEX_SHIFT = 2
EMBEDDED_COUNT_SHIFT = 4

READER_INDEX = {
    "NIL": 0,
    "NUM_16_POS": 1,
    "NUM_16_NEG": 2,
    "NUM_24_POS": 3,
    "NUM_24_NEG": 4,
    "NUM_32_POS": 5,
    "NUM_32_NEG": 6,
    "NUM_64_POS": 7,
    "NUM_64_NEG": 8,
    "NUM_FLOAT": 9,
    "NUM_FLOATSTR_POS": 10,
    "NUM_FLOATSTR_NEG": 11,
    "BOOL_T": 12,
    "BOOL_F": 13,
    "STR_8": 14,
    "STR_16": 15,
    "STR_24": 16,
    "TABLE_8": 17,
    "TABLE_16": 18,
    "TABLE_24": 19,
    "ARRAY_8": 20,
    "ARRAY_16": 21,
    "ARRAY_24": 22,
    "MIXED_8": 23,
    "MIXED_16": 24,
    "MIXED_24": 25,
    "STRINGREF_8": 26,
    "STRINGREF_16": 27,
    "STRINGREF_24": 28,
    "TABLEREF_8": 29,
    "TABLEREF_16": 30,
    "TABLEREF_24": 31,
}

EMBEDDED_INDEX = {
    "STRING": 0,
    "TABLE": 1,
    "ARRAY": 2,
    "MIXED": 3,
}

RI = READER_INDEX  # shorthand

NUMBER_INDICES: list[int] = [
    0,
    0,
    RI["NUM_16_POS"],
    RI["NUM_24_POS"],
    RI["NUM_32_POS"],
    0,
    0,
    RI["NUM_64_POS"],
]

TYPE_INDICES: dict[str, list[int]] = {
    "STRING": [0, RI["STR_8"], RI["STR_16"], RI["STR_24"]],
    "TABLE": [0, RI["TABLE_8"], RI["TABLE_16"], RI["TABLE_24"]],
    "ARRAY": [0, RI["ARRAY_8"], RI["ARRAY_16"], RI["ARRAY_24"]],
    "MIXED": [0, RI["MIXED_8"], RI["MIXED_16"], RI["MIXED_24"]],
}

STRING_REF_INDICES: list[int] = [
    0,
    RI["STRINGREF_8"],
    RI["STRINGREF_16"],
    RI["STRINGREF_24"],
]
TABLE_REF_INDICES: list[int] = [
    0,
    RI["TABLEREF_8"],
    RI["TABLEREF_16"],
    RI["TABLEREF_24"],
]


def _get_required_bytes(value: int) -> int:
    if value < 256:
        return 1
    if value < 65536:
        return 2
    if value < 16777216:
        return 3
    raise ValueError("Object limit exceeded")


def _get_required_bytes_number(value: int) -> int:
    if value < 256:
        return 1
    if value < 65536:
        return 2
    if value < 16777216:
        return 3
    if value < 4294967296:
        return 4
    return 7


# ---------------------------------------------------------------------------
# Deserializer
# ---------------------------------------------------------------------------


class LibSerializeDeserializer:
    def __init__(self, data: bytes) -> None:
        self._data = data
        self._pos = 0
        self._string_refs: list = []
        self._table_refs: list = []

    @classmethod
    def deserialize(cls, data: bytes):
        return cls(data).deserialize_root()

    def deserialize_root(self):
        self._read_byte()  # version byte (always 1)
        return self._read_object()

    # ── low-level I/O ──────────────────────────────────────────────────────

    def _read_bytes(self, length: int) -> bytes:
        chunk = self._data[self._pos : self._pos + length]
        self._pos += length
        return chunk

    def _read_byte(self) -> int:
        return self._read_int(1)

    def _read_int(self, required: int) -> int:
        return int.from_bytes(self._read_bytes(required), "big")

    def _string_to_float(self, data: bytes) -> float:
        return struct.unpack(">d", data)[0]

    def _add_reference(self, refs: list, value) -> None:
        refs.append(value)

    # ── object reader ──────────────────────────────────────────────────────

    def _read_object(self):
        value = self._read_byte()

        if value % 2 == 1:
            return (value - 1) // 2

        if value % 4 == 2:
            typ = (value - 2) // 4
            count = (typ - typ % 4) // 4
            typ = typ % 4
            return self._embedded_reader(typ, count)

        if value % 8 == 4:
            packed = self._read_byte() * 256 + value
            if value % 16 == 12:
                return -(packed - 12) // 16
            else:
                return (packed - 4) // 16

        return self._reader_table(value // 8)

    def _embedded_reader(self, typ: int, count: int):
        if typ == EMBEDDED_INDEX["STRING"]:
            return self._read_string(count)
        if typ == EMBEDDED_INDEX["TABLE"]:
            return self._read_table(count)
        if typ == EMBEDDED_INDEX["ARRAY"]:
            return self._read_array(count)
        if typ == EMBEDDED_INDEX["MIXED"]:
            array_count = count % 4 + 1
            map_count = count // 4 + 1
            return self._read_mixed(array_count, map_count)
        raise ValueError(f"Unknown embedded type: {typ}")

    def _reader_table(self, typ: int):
        if typ == RI["NIL"]:
            return None
        if typ == RI["NUM_16_POS"]:
            return self._read_int(2)
        if typ == RI["NUM_16_NEG"]:
            return -self._read_int(2)
        if typ == RI["NUM_24_POS"]:
            return self._read_int(3)
        if typ == RI["NUM_24_NEG"]:
            return -self._read_int(3)
        if typ == RI["NUM_32_POS"]:
            return self._read_int(4)
        if typ == RI["NUM_32_NEG"]:
            return -self._read_int(4)
        if typ == RI["NUM_64_POS"]:
            return self._read_int(7)
        if typ == RI["NUM_64_NEG"]:
            return -self._read_int(7)
        if typ == RI["NUM_FLOAT"]:
            return self._string_to_float(self._read_bytes(8))
        if typ == RI["NUM_FLOATSTR_POS"]:
            return float(self._read_bytes(self._read_byte()).decode())
        if typ == RI["NUM_FLOATSTR_NEG"]:
            return -float(self._read_bytes(self._read_byte()).decode())
        if typ == RI["BOOL_T"]:
            return True
        if typ == RI["BOOL_F"]:
            return False
        if typ == RI["STR_8"]:
            return self._read_string(self._read_byte())
        if typ == RI["STR_16"]:
            return self._read_string(self._read_int(2))
        if typ == RI["STR_24"]:
            return self._read_string(self._read_int(3))
        if typ == RI["TABLE_8"]:
            return self._read_table(self._read_byte())
        if typ == RI["TABLE_16"]:
            return self._read_table(self._read_int(2))
        if typ == RI["TABLE_24"]:
            return self._read_table(self._read_int(3))
        if typ == RI["ARRAY_8"]:
            return self._read_array(self._read_byte())
        if typ == RI["ARRAY_16"]:
            return self._read_array(self._read_int(2))
        if typ == RI["ARRAY_24"]:
            return self._read_array(self._read_int(3))
        if typ == RI["MIXED_8"]:
            return self._read_mixed(self._read_byte(), self._read_byte())
        if typ == RI["MIXED_16"]:
            return self._read_mixed(self._read_int(2), self._read_int(2))
        if typ == RI["MIXED_24"]:
            return self._read_mixed(self._read_int(3), self._read_int(3))
        if typ == RI["STRINGREF_8"]:
            return self._string_refs[self._read_byte() - 1]
        if typ == RI["STRINGREF_16"]:
            return self._string_refs[self._read_int(2) - 1]
        if typ == RI["STRINGREF_24"]:
            return self._string_refs[self._read_int(3) - 1]
        if typ == RI["TABLEREF_8"]:
            return self._table_refs[self._read_byte() - 1]
        if typ == RI["TABLEREF_16"]:
            return self._table_refs[self._read_int(2) - 1]
        if typ == RI["TABLEREF_24"]:
            return self._table_refs[self._read_int(3) - 1]
        raise ValueError(f"Unknown type in reader table: {typ}")

    def _read_table(self, entry_count: int, value: dict | None = None) -> dict:
        is_new = value is None
        if is_new:
            value = {}
            self._add_reference(self._table_refs, value)
        for _ in range(entry_count):
            k = self._read_object()
            v = self._read_object()
            value[k] = v
        return value

    def _read_array(self, entry_count: int, value: dict | None = None) -> dict:
        is_new = value is None
        if is_new:
            value = {}
            self._add_reference(self._table_refs, value)
        for i in range(entry_count):
            value[i + 1] = self._read_object()
        return value

    def _read_mixed(self, array_count: int, map_count: int) -> dict:
        value: dict = {}
        self._add_reference(self._table_refs, value)
        # Inline array reading — do NOT call _read_array (it would add a spurious table ref)
        for i in range(array_count):
            value[i + 1] = self._read_object()
        self._read_table(map_count, value)
        return value

    def _read_string(self, length: int):
        raw = self._read_bytes(length)
        # Python-specific: 0xFF prefix marks a bytes object (see _serialize_bytes).
        # 0xFF is never a valid UTF-8 lead byte so no str round-trip produces it.
        if raw and raw[0] == 0xFF:
            value = raw[1:]
            if length > 2:
                self._add_reference(self._string_refs, value)
            return value
        value = raw.decode("utf-8", errors="replace")
        if length > 2:
            self._add_reference(self._string_refs, value)
        return value


# ---------------------------------------------------------------------------
# Serializer
# ---------------------------------------------------------------------------


class LibSerializeSerializer:
    def __init__(self, data) -> None:
        self._data = data
        self._string_refs: dict = {}
        self._object_refs: dict = {}
        self._buffer: bytearray = bytearray()

    @classmethod
    def serialize(cls, data) -> bytes:
        return cls(data).serialize_root()

    def serialize_root(self) -> bytes:
        self._write_int(1, 1)  # version byte
        self._write_object(self._data)
        return bytes(self._buffer)

    # ── low-level I/O ──────────────────────────────────────────────────────

    def _write_byte(self, byte: int) -> None:
        self._buffer.append(byte & 0xFF)

    def _write_bytes(self, data: bytes) -> None:
        self._buffer.extend(data)

    def _int_to_bytes(self, n: int, required: int) -> bytes:
        if required == 1:
            return bytes([n & 0xFF])
        if required == 2:
            return struct.pack(">H", n)
        if required == 3:
            return bytes([(n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF])
        if required == 4:
            return struct.pack(">I", n)
        if required == 7:
            return bytes(
                [
                    (n >> 48) & 0xFF,
                    (n >> 40) & 0xFF,
                    (n >> 32) & 0xFF,
                    (n >> 24) & 0xFF,
                    (n >> 16) & 0xFF,
                    (n >> 8) & 0xFF,
                    n & 0xFF,
                ]
            )
        raise ValueError(f"Invalid required bytes: {required}")

    def _write_int(self, n: int, required: int) -> None:
        self._write_bytes(self._int_to_bytes(n, required))

    def _float_to_bytes(self, n: float) -> bytes:
        return struct.pack(">d", n)

    # ── object writer ──────────────────────────────────────────────────────

    def _write_object(self, obj) -> None:
        if isinstance(obj, bool):
            self._serialize_boolean(obj)
        elif obj is None:
            self._serialize_nil()
        elif isinstance(obj, int):
            self._serialize_number(obj)
        elif isinstance(obj, float):
            self._serialize_number(obj)
        elif isinstance(obj, bytes):
            self._serialize_bytes(obj)
        elif isinstance(obj, str):
            self._serialize_string(obj)
        elif isinstance(obj, (list, tuple)):
            self._serialize_array(obj)
        elif isinstance(obj, dict):
            self._serialize_table(obj)
        else:
            raise TypeError(f"Unsupported type: {type(obj).__name__}")

    def _serialize_nil(self) -> None:
        self._write_byte(RI["NIL"])

    def _serialize_boolean(self, b: bool) -> None:
        index = RI["BOOL_T"] if b else RI["BOOL_F"]
        self._write_byte(index << 3)

    def _serialize_number(self, number) -> None:
        if isinstance(number, float):
            self._serialize_float(number)
        elif number > -4096 and number < 4096:
            self._serialize_small_integer(number)
        else:
            self._serialize_large_integer(number)

    def _serialize_float(self, num: float) -> None:
        num_abs = abs(num)
        as_string = str(num_abs)
        if (
            len(as_string) < 7
            and float(as_string) == num_abs
            and num_abs != float("inf")
        ):
            sign = 1 if num < 0 else 0
            self._write_byte((sign + RI["NUM_FLOATSTR_POS"]) << 3)
            encoded = as_string.encode()
            self._write_byte(len(encoded))
            self._write_bytes(encoded)
        else:
            self._write_byte(RI["NUM_FLOAT"] << 3)
            self._write_bytes(self._float_to_bytes(num))

    def _serialize_small_integer(self, num: int) -> None:
        if num >= 0 and num < 128:
            self._write_byte(num * 2 + 1)
        else:
            sign = 8 if num < 0 else 0
            n = abs(num) * 16 + sign + 4
            lower = n % 256
            upper = n // 256
            self._write_byte(lower)
            self._write_byte(upper)

    def _serialize_large_integer(self, num: int) -> None:
        sign = 1 if num < 0 else 0
        num = abs(num)
        required_bytes = _get_required_bytes_number(num)
        if required_bytes == 1:
            required_bytes = 2
        type_index = NUMBER_INDICES[required_bytes]
        self._write_byte((sign + type_index) << 3)
        self._write_int(num, required_bytes)

    def _serialize_string(self, s: str) -> None:
        ref = self._string_refs.get(s)
        if ref is not None:
            required_bytes = _get_required_bytes(ref)
            ref_type = STRING_REF_INDICES[required_bytes]
            self._write_byte(ref_type << 3)
            self._write_int(ref, required_bytes)
        else:
            encoded = s.encode("utf-8")
            length = len(encoded)
            self._write_type_with_count("STRING", length)
            self._write_bytes(encoded)
            if length > 2:
                self._string_refs[s] = len(self._string_refs) + 1

    def _serialize_bytes(self, data: bytes) -> None:
        # Python-specific: prefix raw bytes with 0xFF sentinel so the
        # deserializer can distinguish bytes from str on round-trip.
        # 0xFF is never a valid UTF-8 lead byte, so no str serialization
        # will produce this prefix.
        ref_key = data
        ref = self._string_refs.get(ref_key)
        if ref is not None:
            required_bytes = _get_required_bytes(ref)
            ref_type = STRING_REF_INDICES[required_bytes]
            self._write_byte(ref_type << 3)
            self._write_int(ref, required_bytes)
        else:
            tagged = b"\xff" + data
            length = len(tagged)
            self._write_type_with_count("STRING", length)
            self._write_bytes(tagged)
            if length > 2:
                self._string_refs[ref_key] = len(self._string_refs) + 1

    def _serialize_array(self, data: list | tuple) -> None:
        key = id(data)
        ref = self._object_refs.get(key)
        if ref is not None:
            required_bytes = _get_required_bytes(ref)
            ref_type = TABLE_REF_INDICES[required_bytes]
            self._write_byte(ref_type << 3)
            self._write_int(ref, required_bytes)
        else:
            length = len(data)
            self._write_type_with_count("ARRAY", length)
            for item in data:
                self._write_object(item)
            if length > 2:
                self._object_refs[key] = len(self._object_refs) + 1

    def _serialize_table(self, data: dict) -> None:
        key = id(data)
        ref = self._object_refs.get(key)
        if ref is not None:
            required_bytes = _get_required_bytes(ref)
            ref_type = TABLE_REF_INDICES[required_bytes]
            self._write_byte(ref_type << 3)
            self._write_int(ref, required_bytes)
        else:
            keys = list(data.keys())
            length = len(keys)
            # Detect Lua-style array: sequential 1-based integer keys (int or str)
            if length > 0 and all(
                (isinstance(k, int) and k == i + 1)
                or (isinstance(k, str) and k == str(i + 1))
                for i, k in enumerate(keys)
            ):
                self._write_type_with_count("ARRAY", length)
                for k in keys:
                    self._write_object(data[k])
            else:
                self._write_type_with_count("TABLE", length)
                for k, v in data.items():
                    self._write_object(k)
                    self._write_object(v)
            if length > 2:
                self._object_refs[key] = len(self._object_refs) + 1

    def _write_type_with_count(self, type_name: str, count: int) -> None:
        if count < 16:
            embedded_type = EMBEDDED_INDEX[type_name]
            self._write_byte(
                embedded_type << EMBEDDED_INDEX_SHIFT
                | count << EMBEDDED_COUNT_SHIFT
                | 2
            )
        else:
            required = _get_required_bytes(count)
            type_idx = TYPE_INDICES[type_name][required]
            self._write_byte(type_idx << 3)
            self._write_int(count, required)


# ---------------------------------------------------------------------------
# Convenience functions
# ---------------------------------------------------------------------------


def serialize(obj) -> bytes:
    return LibSerializeSerializer.serialize(obj)


def deserialize(data: bytes):
    return LibSerializeDeserializer.deserialize(data)
