"""Tests for WowAceSerializer / WowAceDeserializer."""

import math
import pytest
from wow_serialization.ace_serializer import WowAce, WowAceDeserializer, WowAceSerializer


@pytest.fixture
def ser():
    return WowAceSerializer()


@pytest.fixture
def de():
    return WowAceDeserializer()


@pytest.fixture
def ace():
    return WowAce()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def roundtrip(obj, ace_instance):
    wire = ace_instance.serialize(obj)
    result = ace_instance.deserialize(wire)
    return result


# ---------------------------------------------------------------------------
# Serializer — framing
# ---------------------------------------------------------------------------

class TestFraming:
    def test_wraps_with_version_and_terminator(self, ser):
        wire = ser.serialize(None)
        assert wire.startswith("^1")
        assert wire.endswith("^^")

    def test_minimal_null(self, ser):
        assert ser.serialize(None) == "^1^Z^^"

    def test_true(self, ser):
        assert ser.serialize(True) == "^1^B^^"

    def test_false(self, ser):
        assert ser.serialize(False) == "^1^b^^"


# ---------------------------------------------------------------------------
# Serializer — primitives
# ---------------------------------------------------------------------------

class TestSerializePrimitives:
    def test_integer_positive(self, ser):
        assert ser.serialize(42) == "^1^N42^^"

    def test_integer_negative(self, ser):
        assert ser.serialize(-7) == "^1^N-7^^"

    def test_integer_zero(self, ser):
        assert ser.serialize(0) == "^1^N0^^"

    def test_float_integer_valued(self, ser):
        # Float that is integer-valued → ^N with int repr
        assert ser.serialize(3.0) == "^1^N3^^"

    def test_float_infinity_positive(self, ser):
        assert ser.serialize(math.inf) == "^1^N1.#INF^^"

    def test_float_infinity_negative(self, ser):
        assert ser.serialize(-math.inf) == "^1^N-1.#INF^^"

    def test_float_nan_raises(self, ser):
        with pytest.raises((ValueError, Exception)):
            ser.serialize(float("nan"))

    def test_float_frexp_format(self, ser):
        # Non-integer float should use ^F...^f... format
        wire = ser.serialize(3.14)
        assert "^F" in wire
        assert "^f" in wire

    def test_simple_string(self, ser):
        assert ser.serialize("hello") == "^1^Shello^^"

    def test_empty_string(self, ser):
        assert ser.serialize("") == "^1^S^^"


# ---------------------------------------------------------------------------
# Serializer — string escaping (single-pass)
# ---------------------------------------------------------------------------

class TestStringEscaping:
    def test_escape_caret(self, ser):
        # '^' → '~}'
        wire = ser.serialize("a^b")
        assert "^Sa~}b" in wire

    def test_escape_tilde(self, ser):
        # '~' → '~|'
        wire = ser.serialize("a~b")
        assert "^Sa~|b" in wire

    def test_escape_del(self, ser):
        # DEL (0x7F) → '~{'
        wire = ser.serialize("a\x7fb")
        assert "^Sa~{b" in wire

    def test_escape_byte30(self, ser):
        # Byte 30 → '~z'  (special: 30+64=94='^' would corrupt)
        wire = ser.serialize("\x1e")
        assert "^S~z" in wire

    def test_escape_space(self, ser):
        # Space (0x20=32) → '~`' (32+64=96='`')
        wire = ser.serialize(" ")
        assert "^S~`" in wire

    def test_escape_control_char(self, ser):
        # Byte 1 → '~A' (1+64=65='A')
        wire = ser.serialize("\x01")
        assert "^S~A" in wire

    def test_no_double_escaping(self, ser):
        # Single pass: "~^" should produce "~|~}" not "~~|~}" or similar
        wire = ser.serialize("~^")
        inner = wire[2:-2]  # strip ^1 and ^^
        assert inner == "^S~|~}"

    def test_all_special_chars_roundtrip(self, ace):
        special = "\x00\x01\x1e\x1f \x5e\x7e\x7f"
        assert roundtrip(special, ace) == special


# ---------------------------------------------------------------------------
# Serializer — tables and arrays
# ---------------------------------------------------------------------------

class TestSerializeTables:
    def test_empty_dict(self, ser):
        assert ser.serialize({}) == "^1^T^t^^"

    def test_simple_dict(self, ser):
        wire = ser.serialize({"key": "val"})
        assert wire == "^1^T^Skey^Sval^t^^"

    def test_empty_list(self, ser):
        assert ser.serialize([]) == "^1^T^t^^"

    def test_array_uses_1based_keys(self, ser):
        wire = ser.serialize(["a", "b"])
        assert wire == "^1^T^N1^Sa^N2^Sb^t^^"

    def test_nested(self, ser):
        wire = ser.serialize({"x": [1, 2]})
        assert "^T" in wire
        assert "^t" in wire


# ---------------------------------------------------------------------------
# Deserializer — primitives
# ---------------------------------------------------------------------------

class TestDeserializePrimitives:
    def test_null(self, de):
        assert de.deserialize("^1^Z^^") is None

    def test_true(self, de):
        assert de.deserialize("^1^B^^") is True

    def test_false(self, de):
        assert de.deserialize("^1^b^^") is False

    def test_integer(self, de):
        result = de.deserialize("^1^N42^^")
        assert result == 42
        assert isinstance(result, int)

    def test_negative_integer(self, de):
        result = de.deserialize("^1^N-7^^")
        assert result == -7

    def test_float_decimal(self, de):
        result = de.deserialize("^1^N3.14^^")
        assert isinstance(result, float)
        assert abs(result - 3.14) < 1e-10

    def test_positive_infinity(self, de):
        assert de.deserialize("^1^N1.#INF^^") == math.inf

    def test_negative_infinity(self, de):
        assert de.deserialize("^1^N-1.#INF^^") == -math.inf

    def test_inf_alias(self, de):
        assert de.deserialize("^1^Ninf^^") == math.inf

    def test_neg_inf_alias(self, de):
        assert de.deserialize("^1^N-inf^^") == -math.inf

    def test_float_frexp_format(self, de):
        # Manually constructed: 0.5 = frexp gives m=0.5, e=0
        # int_mantissa = int(0.5 * 2^53) = 4503599627370496
        # wire: ^F4503599627370496^f0
        result = de.deserialize("^1^F4503599627370496^f0^^")
        assert abs(result - math.ldexp(4503599627370496, 0 - 53)) < 1e-15

    def test_simple_string(self, de):
        assert de.deserialize("^1^Shello^^") == "hello"

    def test_empty_string(self, de):
        assert de.deserialize("^1^S^^") == ""

    def test_invalid_prefix_raises(self, de):
        with pytest.raises((ValueError, Exception)):
            de.deserialize("bad data")


# ---------------------------------------------------------------------------
# Deserializer — string unescaping
# ---------------------------------------------------------------------------

class TestStringUnescaping:
    def test_unescape_caret(self, de):
        assert de.deserialize("^1^Sa~}b^^") == "a^b"

    def test_unescape_tilde(self, de):
        assert de.deserialize("^1^Sa~|b^^") == "a~b"

    def test_unescape_del(self, de):
        assert de.deserialize("^1^Sa~{b^^") == "a\x7fb"

    def test_unescape_byte30(self, de):
        assert de.deserialize("^1^S~z^^") == "\x1e"

    def test_unescape_space(self, de):
        assert de.deserialize("^1^S~`^^") == " "

    def test_unescape_control(self, de):
        assert de.deserialize("^1^S~A^^") == "\x01"


# ---------------------------------------------------------------------------
# Deserializer — tables and array detection
# ---------------------------------------------------------------------------

class TestDeserializeTables:
    def test_empty_table(self, de):
        result = de.deserialize("^1^T^t^^")
        assert result == {} or result == []

    def test_sequential_1based_keys_become_list(self, de):
        # {1: "a", 2: "b", 3: "c"} → ["a", "b", "c"]
        result = de.deserialize("^1^T^N1^Sa^N2^Sb^N3^Sc^t^^")
        assert result == ["a", "b", "c"]

    def test_non_sequential_keys_stay_dict(self, de):
        # {1: "a", 3: "c"} — gap, not sequential → dict
        result = de.deserialize("^1^T^N1^Sa^N3^Sc^t^^")
        assert isinstance(result, dict)
        assert result[1] == "a"
        assert result[3] == "c"

    def test_string_keys_stay_dict(self, de):
        result = de.deserialize("^1^T^Skey^Sval^t^^")
        assert result == {"key": "val"}

    def test_nested_table(self, de):
        wire = "^1^T^Snested^T^N1^Z^N2^Z^t^t^^"
        result = de.deserialize(wire)
        assert result["nested"] == [None, None]


# ---------------------------------------------------------------------------
# Round-trip tests
# ---------------------------------------------------------------------------

class TestRoundTrip:
    def test_null(self, ace):
        assert roundtrip(None, ace) is None

    def test_true(self, ace):
        assert roundtrip(True, ace) is True

    def test_false(self, ace):
        assert roundtrip(False, ace) is False

    def test_integer(self, ace):
        assert roundtrip(42, ace) == 42
        assert isinstance(roundtrip(42, ace), int)

    def test_negative_integer(self, ace):
        assert roundtrip(-999, ace) == -999

    def test_float(self, ace):
        val = 3.14159265358979
        result = roundtrip(val, ace)
        assert abs(result - val) < 1e-14

    def test_float_zero(self, ace):
        assert roundtrip(0.0, ace) == 0

    def test_float_negative(self, ace):
        val = -2.71828
        result = roundtrip(val, ace)
        assert abs(result - val) < 1e-10

    def test_float_large(self, ace):
        val = 1.23e100
        result = roundtrip(val, ace)
        assert abs(result - val) / abs(val) < 1e-14

    def test_float_small(self, ace):
        val = 1.23e-100
        result = roundtrip(val, ace)
        assert abs(result - val) / abs(val) < 1e-14

    def test_infinity_positive(self, ace):
        assert roundtrip(math.inf, ace) == math.inf

    def test_infinity_negative(self, ace):
        assert roundtrip(-math.inf, ace) == -math.inf

    def test_simple_string(self, ace):
        assert roundtrip("hello world", ace) == "hello world"

    def test_string_with_caret(self, ace):
        assert roundtrip("a^b", ace) == "a^b"

    def test_string_with_tilde(self, ace):
        assert roundtrip("a~b", ace) == "a~b"

    def test_string_all_specials(self, ace):
        s = "\x00\x01\x1e\x1f \x5e\x7e\x7f"
        assert roundtrip(s, ace) == s

    def test_empty_string(self, ace):
        assert roundtrip("", ace) == ""

    def test_list(self, ace):
        assert roundtrip(["a", "b", "c"], ace) == ["a", "b", "c"]

    def test_list_mixed(self, ace):
        result = roundtrip([1, "two", None, True], ace)
        assert result == [1, "two", None, True]

    def test_dict(self, ace):
        result = roundtrip({"key": "value", "num": 42}, ace)
        assert result["key"] == "value"
        assert result["num"] == 42

    def test_nested_complex(self, ace):
        obj = {
            "hello": "world",
            "test": 123,
            "nested": [None, None, None, "test"],
        }
        result = roundtrip(obj, ace)
        assert result["hello"] == "world"
        assert result["test"] == 123
        assert result["nested"] == [None, None, None, "test"]

    def test_empty_list(self, ace):
        # Empty list → empty table → can come back as {} or []
        result = roundtrip([], ace)
        assert result == [] or result == {}

    def test_empty_dict(self, ace):
        result = roundtrip({}, ace)
        assert result == {} or result == []

    def test_protocol_example(self, ace):
        # From PROTOCOL.md complete example
        obj = {
            "hello": "world",
            "test": 123,
            "nested": [None, None, None, "test"],
        }
        wire = ace.serialize(obj)
        # Must contain version prefix and terminator
        assert wire.startswith("^1")
        assert wire.endswith("^^")
        result = ace.deserialize(wire)
        assert result["hello"] == "world"
        assert result["nested"][3] == "test"
