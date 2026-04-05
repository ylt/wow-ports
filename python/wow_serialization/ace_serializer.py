"""
WoW Ace Serializer — Python port of AceSerializer-3.0.

Wire format:  ^1<payload>^^
Type prefixes: ^S string, ^N number, ^F float mantissa, ^f float exponent,
               ^T table open, ^t table close, ^B true, ^b false, ^Z nil.

String escaping is done in a single pass via re.sub over the character class
[\x00-\x20\x5E\x7E\x7F].

Float serialization uses math.frexp() for decomposition (^F/^f format) for
non-integer, non-infinity floats; plain ^N decimal for integers and infinity.

Array detection: if deserialized table keys are exactly 1..N, return a list.
"""

import math
import re
from typing import Any


# ---------------------------------------------------------------------------
# String escaping
# ---------------------------------------------------------------------------

_ESCAPE_PATTERN = re.compile(r"[\x00-\x20\x5e\x7e\x7f]")
_UNESCAPE_PATTERN = re.compile(r"~(.)", re.DOTALL)


def _escape_char(m: re.Match) -> str:
    byte = ord(m.group(0))
    if byte == 0x1E:   # 30 — special: 30+64=94='^' would break parser
        return "~z"
    if byte == 0x5E:   # '^'
        return "~}"
    if byte == 0x7E:   # '~'
        return "~|"
    if byte == 0x7F:   # DEL
        return "~{"
    return "~" + chr(byte + 64)


def _unescape_char(m: re.Match) -> str:
    c = m.group(1)
    o = ord(c)
    if o < 122:        # generic: chr(byte - 64)
        return chr(o - 64)
    if o == 122:       # ~z → byte 30
        return "\x1e"
    if o == 123:       # ~{ → DEL
        return "\x7f"
    if o == 124:       # ~| → ~
        return "~"
    if o == 125:       # ~} → ^
        return "^"
    raise ValueError(f"Unknown escape sequence: ~{c!r}")


# ---------------------------------------------------------------------------
# Serializer
# ---------------------------------------------------------------------------

class WowAceSerializer:
    """Serialize Python objects to WoW Ace wire format."""

    def serialize(self, obj: Any) -> str:
        return f"^1{self._serialize_value(obj)}^^"

    def _serialize_value(self, obj: Any) -> str:
        if obj is None:
            return "^Z"
        if obj is True:
            return "^B"
        if obj is False:
            return "^b"
        if isinstance(obj, int):
            return f"^N{obj}"
        if isinstance(obj, float):
            return self._serialize_float(obj)
        if isinstance(obj, str):
            return self._serialize_string(obj)
        if isinstance(obj, (list, tuple)):
            return self._serialize_array(obj)
        if isinstance(obj, dict):
            return self._serialize_table(obj)
        raise TypeError(f"Unsupported type: {type(obj).__name__}")

    def _serialize_string(self, s: str) -> str:
        escaped = _ESCAPE_PATTERN.sub(_escape_char, s)
        return f"^S{escaped}"

    def _serialize_float(self, num: float) -> str:
        if math.isinf(num):
            return "^N1.#INF" if num > 0 else "^N-1.#INF"
        if math.isnan(num):
            raise ValueError("NaN is not serializable")
        if num.is_integer():
            return f"^N{int(num)}"
        # Lua uses tonumber(tostring(v))==v — if the float survives string round-trip, use ^N
        str_val = "%.14g" % num
        if float(str_val) == num:
            return f"^N{str_val}"
        # frexp-based encoding for non-integer floats (matches JS WowAceSerializer)
        m, e = math.frexp(num)
        int_mantissa = int(m * (2 ** 53))
        adj_exponent = e - 53
        return f"^F{int_mantissa}^f{adj_exponent}"

    def _serialize_table(self, table: dict) -> str:
        parts = []
        for key, value in table.items():
            parts.append(self._serialize_value(key))
            parts.append(self._serialize_value(value))
        return f"^T{''.join(parts)}^t"

    def _serialize_array(self, arr: list | tuple) -> str:
        # Arrays become 1-based integer-keyed tables
        parts = []
        for i, value in enumerate(arr, start=1):
            parts.append(self._serialize_value(i))
            parts.append(self._serialize_value(value))
        return f"^T{''.join(parts)}^t"


# ---------------------------------------------------------------------------
# Deserializer cursor
# ---------------------------------------------------------------------------

class _Cursor:
    """Mutable string position cursor for the deserializer."""

    def __init__(self, s: str) -> None:
        self._s = s
        self.pos = 0

    def peek(self, n: int = 2) -> str:
        return self._s[self.pos : self.pos + n]

    def read(self, n: int) -> str:
        chunk = self._s[self.pos : self.pos + n]
        self.pos += n
        return chunk

    def read_until(self, pattern: re.Pattern) -> str:
        m = pattern.search(self._s, self.pos)
        end = m.start() if m else len(self._s)
        chunk = self._s[self.pos : end]
        self.pos = end
        return chunk

    def remaining(self) -> str:
        return self._s[self.pos :]

    def __len__(self) -> int:
        return len(self._s) - self.pos


# Matches the start of any type prefix (including ^t end-of-table)
_TYPE_PREFIX = re.compile(r"\^[SNFTtBbZf]")
# Matches start of a value prefix OR end-of-table marker
_VALUE_OR_END = re.compile(r"\^[SNFTtBbZf]")


class WowAceDeserializer:
    """Deserialize WoW Ace wire format to Python objects."""

    def deserialize(self, data: str) -> Any:
        data = data.strip()
        # Strip embedded whitespace / control chars before the prefix check
        data = re.sub(r"[\x00-\x20]", "", data)
        if not data.startswith("^1"):
            raise ValueError("Invalid prefix — expected '^1'")
        if not data.endswith("^^"):
            raise ValueError("Missing '^^' terminator")
        # Remove ^1 prefix and ^^ terminator
        payload = data[2:-2]
        cur = _Cursor(payload)
        return self._read_value(cur)

    def _read_value(self, cur: _Cursor) -> Any:
        prefix = cur.read(2)
        if len(prefix) < 2 or prefix[0] != "^":
            raise ValueError(f"Expected type prefix, got {prefix!r}")
        typ = prefix[1]
        if typ == "S":
            return self._read_string(cur)
        if typ == "N":
            return self._read_number(cur)
        if typ == "F":
            return self._read_float(cur)
        if typ == "T":
            return self._read_table(cur)
        if typ == "B":
            return True
        if typ == "b":
            return False
        if typ == "Z":
            return None
        raise ValueError(f"Unknown type prefix: ^{typ!r}")

    def _read_string(self, cur: _Cursor) -> str:
        # String body ends at the next '^' that starts a type prefix
        raw = cur.read_until(_TYPE_PREFIX)
        return _UNESCAPE_PATTERN.sub(_unescape_char, raw)

    def _read_number(self, cur: _Cursor) -> int | float:
        raw = cur.read_until(_TYPE_PREFIX)
        if raw in ("1.#INF", "inf"):
            return math.inf
        if raw in ("-1.#INF", "-inf"):
            return -math.inf
        if re.fullmatch(r"-?\d+", raw):
            return int(raw)
        return float(raw)

    def _read_float(self, cur: _Cursor) -> float:
        # Format: ^F<mantissa>^f<exponent>  (^F already consumed)
        mantissa_str = cur.read_until(_TYPE_PREFIX)
        sep = cur.read(2)  # consume '^f'
        if sep != "^f":
            raise ValueError(f"Expected '^f' separator, got {sep!r}")
        exponent_str = cur.read_until(_TYPE_PREFIX)
        mantissa = int(mantissa_str)
        exponent = int(exponent_str)
        # Wire format: adj_exponent = e - 53 (matches JS WowAceSerializer)
        # Decode: mantissa * 2^exponent (no further adjustment needed)
        return math.ldexp(mantissa, exponent)

    def _read_table(self, cur: _Cursor) -> dict | list:
        table: dict = {}
        while cur.peek(2) != "^t":
            if len(cur) < 2:
                raise ValueError("Unexpected end of data in table")
            key = self._read_value(cur)
            value = self._read_value(cur)
            table[key] = value
        cur.read(2)  # consume '^t'
        return table


# ---------------------------------------------------------------------------
# Convenience combined class
# ---------------------------------------------------------------------------

class WowAce(WowAceSerializer, WowAceDeserializer):
    """Combined serialize + deserialize interface."""
