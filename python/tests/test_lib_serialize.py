"""Tests for LibSerialize serialize/deserialize."""

import math
import struct
import pytest
from wow_serialization.lib_serialize import deserialize, serialize


def roundtrip(obj):
    return deserialize(serialize(obj))


def describe_LibSerialize():

    def describe_nil():
        def it_serialize_nil_does_not_raise():
            assert serialize(None) is not None

        def it_roundtrip_nil():
            assert roundtrip(None) is None

    def describe_booleans():
        def it_roundtrip_true():
            assert roundtrip(True) is True

        def it_roundtrip_false():
            assert roundtrip(False) is False

    def describe_integers():
        def it_roundtrip_zero():
            assert roundtrip(0) == 0

        def it_roundtrip_positive_small():
            assert roundtrip(42) == 42

        def it_roundtrip_127():
            # Boundary: last value in small-int positive range
            assert roundtrip(127) == 127

        def it_roundtrip_negative_small():
            assert roundtrip(-1) == -1

        def it_roundtrip_negative_large_small_int():
            assert roundtrip(-100) == -100

        def it_roundtrip_large_positive():
            # Forces large integer path (≥ 128)
            assert roundtrip(1000) == 1000

        def it_roundtrip_large_negative():
            assert roundtrip(-5000) == -5000

        def it_roundtrip_65535():
            assert roundtrip(65535) == 65535

        def it_roundtrip_65536():
            assert roundtrip(65536) == 65536

        def it_roundtrip_16777215():
            assert roundtrip(16777215) == 16777215

    def describe_floats():
        def it_roundtrip_float_small_string():
            # 3.14 → short string representation → FLOATSTR path
            result = roundtrip(3.14)
            assert abs(result - 3.14) < 1e-10

        def it_roundtrip_float_large():
            result = roundtrip(1.23e100)
            assert abs(result - 1.23e100) / abs(1.23e100) < 1e-14

        def it_roundtrip_float_negative():
            result = roundtrip(-2.71828)
            assert abs(result - (-2.71828)) < 1e-10

        def it_roundtrip_float_zero():
            result = roundtrip(0.0)
            assert result == 0.0 or result == 0

        def it_roundtrip_infinity():
            assert roundtrip(math.inf) == math.inf

        def it_roundtrip_neg_infinity():
            assert roundtrip(-math.inf) == -math.inf

    def describe_strings():
        def it_roundtrip_empty():
            assert roundtrip("") == ""

        def it_roundtrip_short():
            assert roundtrip("hi") == "hi"

        def it_roundtrip_normal():
            assert roundtrip("hello") == "hello"

        def it_roundtrip_long():
            s = "a" * 300
            assert roundtrip(s) == s

        def it_roundtrip_unicode():
            assert roundtrip("héllo") == "héllo"

    def describe_arrays():
        def it_roundtrip_empty():
            assert roundtrip([]) == []

        def it_roundtrip_small():
            assert roundtrip([1, 2]) == [1, 2]

        def it_roundtrip_three_elements():
            # >2 elements triggers ref tracking path (bug fix test)
            assert roundtrip([10, 20, 30]) == [10, 20, 30]

        def it_roundtrip_mixed_types():
            result = roundtrip([1, "two", None, True])
            assert result[0] == 1
            assert result[1] == "two"
            assert result[2] is None
            assert result[3] is True

        def it_roundtrip_nested():
            result = roundtrip([[1, 2], [3, 4]])
            assert result[0][0] == 1
            assert result[1][1] == 4

    def describe_tables():
        def it_roundtrip_empty():
            assert roundtrip({}) == {}

        def it_roundtrip_single_pair():
            assert roundtrip({"key": "val"})["key"] == "val"

        def it_roundtrip_three_keys():
            # >2 keys triggers ref tracking path (bug fix test)
            result = roundtrip({"a": 1, "b": 2, "c": 3})
            assert result["a"] == 1
            assert result["b"] == 2
            assert result["c"] == 3

        def it_roundtrip_integer_keys():
            result = roundtrip({1: "one", 2: "two"})
            assert result[1] == "one"
            assert result[2] == "two"

        def it_roundtrip_nested():
            result = roundtrip({"outer": {"inner": 42}})
            assert result["outer"]["inner"] == 42

    def describe_string_ref_tracking():
        def it_repeated_long_string_round_trips():
            # Long strings get tracked as refs on second use
            s = "repeated_key"
            data = {s: 1, "other": s}
            result = roundtrip(data)
            assert result[s] == 1
            assert result["other"] == s

    def describe_wire_format():
        def it_version_byte_is_1():
            assert serialize(None)[0] == 1

        def it_nil_type_code():
            assert len(serialize(None)) >= 2

        def it_float_binary_encoding():
            # Floats with long string rep use big-endian double (>d)
            wire = serialize(1.23e100)
            assert struct.pack(">d", 1.23e100) in wire
