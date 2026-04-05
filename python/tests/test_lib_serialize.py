"""Tests for LibSerialize serialize/deserialize."""

import math
import struct
import pytest
from wow_serialization.lib_serialize import deserialize, serialize


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def roundtrip(obj):
    return deserialize(serialize(obj))


# ---------------------------------------------------------------------------
# Nil
# ---------------------------------------------------------------------------

class TestNil:
    def test_serialize_nil_does_not_raise(self):
        assert serialize(None) is not None

    def test_roundtrip_nil(self):
        assert roundtrip(None) is None


# ---------------------------------------------------------------------------
# Booleans
# ---------------------------------------------------------------------------

class TestBooleans:
    def test_roundtrip_true(self):
        assert roundtrip(True) is True

    def test_roundtrip_false(self):
        assert roundtrip(False) is False


# ---------------------------------------------------------------------------
# Integers
# ---------------------------------------------------------------------------

class TestIntegers:
    def test_roundtrip_zero(self):
        assert roundtrip(0) == 0

    def test_roundtrip_positive_small(self):
        assert roundtrip(42) == 42

    def test_roundtrip_127(self):
        # Boundary: last value in small-int positive range
        assert roundtrip(127) == 127

    def test_roundtrip_negative_small(self):
        assert roundtrip(-1) == -1

    def test_roundtrip_negative_large_small_int(self):
        assert roundtrip(-100) == -100

    def test_roundtrip_large_positive(self):
        # Forces large integer path (≥ 128)
        assert roundtrip(1000) == 1000

    def test_roundtrip_large_negative(self):
        assert roundtrip(-5000) == -5000

    def test_roundtrip_65535(self):
        assert roundtrip(65535) == 65535

    def test_roundtrip_65536(self):
        assert roundtrip(65536) == 65536

    def test_roundtrip_16777215(self):
        assert roundtrip(16777215) == 16777215


# ---------------------------------------------------------------------------
# Floats
# ---------------------------------------------------------------------------

class TestFloats:
    def test_roundtrip_float_small_string(self):
        # 3.14 → short string representation → FLOATSTR path
        result = roundtrip(3.14)
        assert abs(result - 3.14) < 1e-10

    def test_roundtrip_float_large(self):
        result = roundtrip(1.23e100)
        assert abs(result - 1.23e100) / abs(1.23e100) < 1e-14

    def test_roundtrip_float_negative(self):
        result = roundtrip(-2.71828)
        assert abs(result - (-2.71828)) < 1e-10

    def test_roundtrip_float_zero(self):
        result = roundtrip(0.0)
        assert result == 0.0 or result == 0

    def test_roundtrip_infinity(self):
        result = roundtrip(math.inf)
        assert result == math.inf

    def test_roundtrip_neg_infinity(self):
        result = roundtrip(-math.inf)
        assert result == -math.inf


# ---------------------------------------------------------------------------
# Strings
# ---------------------------------------------------------------------------

class TestStrings:
    def test_roundtrip_empty(self):
        assert roundtrip("") == ""

    def test_roundtrip_short(self):
        assert roundtrip("hi") == "hi"

    def test_roundtrip_normal(self):
        assert roundtrip("hello") == "hello"

    def test_roundtrip_long(self):
        s = "a" * 300
        assert roundtrip(s) == s

    def test_roundtrip_unicode(self):
        s = "héllo"
        assert roundtrip(s) == s


# ---------------------------------------------------------------------------
# Arrays
# ---------------------------------------------------------------------------

class TestArrays:
    def test_roundtrip_empty(self):
        assert roundtrip([]) == []

    def test_roundtrip_small(self):
        assert roundtrip([1, 2]) == [1, 2]

    def test_roundtrip_three_elements(self):
        # >2 elements triggers ref tracking path (bug fix test)
        assert roundtrip([10, 20, 30]) == [10, 20, 30]

    def test_roundtrip_mixed_types(self):
        result = roundtrip([1, "two", None, True])
        assert result[0] == 1
        assert result[1] == "two"
        assert result[2] is None
        assert result[3] is True

    def test_roundtrip_nested(self):
        result = roundtrip([[1, 2], [3, 4]])
        assert result[0][0] == 1
        assert result[1][1] == 4


# ---------------------------------------------------------------------------
# Dicts / Tables
# ---------------------------------------------------------------------------

class TestTables:
    def test_roundtrip_empty(self):
        assert roundtrip({}) == {}

    def test_roundtrip_single_pair(self):
        result = roundtrip({"key": "val"})
        assert result["key"] == "val"

    def test_roundtrip_three_keys(self):
        # >2 keys triggers ref tracking path (bug fix test)
        h = {"a": 1, "b": 2, "c": 3}
        result = roundtrip(h)
        assert result["a"] == 1
        assert result["b"] == 2
        assert result["c"] == 3

    def test_roundtrip_integer_keys(self):
        result = roundtrip({1: "one", 2: "two"})
        assert result[1] == "one"
        assert result[2] == "two"

    def test_roundtrip_nested(self):
        result = roundtrip({"outer": {"inner": 42}})
        assert result["outer"]["inner"] == 42


# ---------------------------------------------------------------------------
# String ref tracking
# ---------------------------------------------------------------------------

class TestStringRefTracking:
    def test_repeated_long_string_round_trips(self):
        # Long strings get tracked as refs on second use
        s = "repeated_key"
        data = {s: 1, "other": s}
        result = roundtrip(data)
        assert result[s] == 1
        assert result["other"] == s


# ---------------------------------------------------------------------------
# Cross-language: binary wire format
# ---------------------------------------------------------------------------

class TestWireFormat:
    def test_version_byte_is_1(self):
        wire = serialize(None)
        assert wire[0] == 1

    def test_nil_type_code(self):
        wire = serialize(None)
        # version=1, then NIL type code 0 as embedded or reader_table
        assert len(wire) >= 2

    def test_float_binary_encoding(self):
        # Floats with long string rep use big-endian double (>d)
        wire = serialize(1.23e100)
        # Should contain the 8-byte IEEE 754 double somewhere
        expected = struct.pack(">d", 1.23e100)
        assert expected in wire
