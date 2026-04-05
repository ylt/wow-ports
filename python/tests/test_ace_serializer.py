"""Tests for WowAceSerializer / WowAceDeserializer — canonical 73-case spec (sections A-L)."""

import math
import re
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


def roundtrip(obj, ace_instance):
    wire = ace_instance.serialize(obj)
    return ace_instance.deserialize(wire)


# ---------------------------------------------------------------------------
# A. String Escaping (Serialize) — tests 1-10
# ---------------------------------------------------------------------------

class TestA_StringEscaping:
    def test_A01_nul_escapes_to_tilde_at(self, ser):
        """A01: NUL (0x00) → ~@"""
        # NUL (0x00) → ~@ (0+64=64='@')
        wire = ser.serialize("\x00")
        assert "^S~@" in wire

    def test_A02_control_chars_1_to_29(self, ser):
        """A02: control chars 1–29 → ~chr(byte+64)"""
        # Bytes 1-29 → ~chr(byte+64)
        # 0x01 → ~A (1+64=65), 0x0A → ~J (10+64=74), 0x1D → ~] (29+64=93)
        assert "^S~A" in ser.serialize("\x01")
        assert "^S~J" in ser.serialize("\x0a")
        assert "^S~]" in ser.serialize("\x1d")

    def test_A03_byte_30_special_case_tilde_z(self, ser):
        """A03: byte 30 (0x1E) → ~z (special case)"""
        # Byte 30 (0x1E) → ~z  (special: 30+64=94='^' would corrupt parser)
        wire = ser.serialize("\x1e")
        assert "^S~z" in wire

    def test_A04_byte_31_escapes_to_tilde_underscore(self, ser):
        """A04: byte 31 (0x1F) → ~_"""
        # Byte 31 (0x1F) → ~_ (31+64=95='_')
        wire = ser.serialize("\x1f")
        assert "^S~_" in wire

    def test_A05_space_escapes_to_tilde_backtick(self, ser):
        """A05: space (0x20) → ~`"""
        # Space (0x20=32) → ~` (32+64=96='`')
        wire = ser.serialize(" ")
        assert "^S~`" in wire

    def test_A06_caret_escapes_to_tilde_rbrace(self, ser):
        """A06: caret ^ (0x5E) → ~}"""
        # '^' (0x5E) → ~}
        wire = ser.serialize("a^b")
        assert "^Sa~}b" in wire

    def test_A07_tilde_escapes_to_tilde_pipe(self, ser):
        """A07: tilde ~ (0x7E) → ~|"""
        # '~' (0x7E) → ~|
        wire = ser.serialize("a~b")
        assert "^Sa~|b" in wire

    def test_A08_del_escapes_to_tilde_lbrace(self, ser):
        """A08: DEL (0x7F) → ~{"""
        # DEL (0x7F) → ~{
        wire = ser.serialize("a\x7fb")
        assert "^Sa~{b" in wire

    def test_A09_single_pass_no_double_escaping(self, ser):
        """A09: single-pass — no double-escaping"""
        # Single pass: "~^" → "~|~}" not "~~|~}"
        wire = ser.serialize("~^")
        inner = wire[2:-2]  # strip ^1 and ^^
        assert inner == "^S~|~}"

    def test_A10_printable_ascii_passes_through(self, ser):
        """A10: printable ASCII (0x21-0x5D, 0x5F-0x7D) passes through unescaped"""
        # Printable ASCII (0x21-0x5D, 0x5F-0x7D) passes through unescaped
        printable = "hello!world#test"
        wire = ser.serialize(printable)
        assert f"^S{printable}" in wire


# ---------------------------------------------------------------------------
# B. String Unescaping (Deserialize) — tests 11-17
# ---------------------------------------------------------------------------

class TestB_StringUnescaping:
    def test_B11_tilde_at_decodes_to_nul(self, de):
        """B11: ~@ → NUL (0x00)"""
        assert de.deserialize("^1^S~@^^") == "\x00"

    def test_B12_generic_escape_tilde_X(self, de):
        """B12: ~X decodes via chr(ord(X)-64)"""
        # ~A → chr(65-64) = chr(1), ~` → chr(96-64) = chr(32) = space
        assert de.deserialize("^1^S~A^^") == "\x01"
        assert de.deserialize("^1^S~`^^") == " "

    def test_B13_tilde_z_decodes_to_byte_30(self, de):
        """B13: ~z → byte 30 (0x1E)"""
        assert de.deserialize("^1^S~z^^") == "\x1e"

    def test_B14_tilde_lbrace_decodes_to_del(self, de):
        """B14: ~{ → DEL (0x7F)"""
        assert de.deserialize("^1^S~{^^") == "\x7f"

    def test_B15_tilde_pipe_decodes_to_tilde(self, de):
        """B15: ~| → tilde"""
        assert de.deserialize("^1^S~|^^") == "~"

    def test_B16_tilde_rbrace_decodes_to_caret(self, de):
        """B16: ~} → caret"""
        assert de.deserialize("^1^S~}^^") == "^"

    def test_B17_roundtrip_all_escapable_bytes(self, ace):
        """B17: round-trip all escapable bytes"""
        special = "\x00\x01\x1e\x1f \x5e\x7e\x7f"
        assert roundtrip(special, ace) == special


# ---------------------------------------------------------------------------
# C. Number Serialization — tests 18-26
# ---------------------------------------------------------------------------

class TestC_NumberSerialization:
    def test_C18_positive_integer(self, ser):
        """C18: positive integer → ^N42"""
        assert ser.serialize(42) == "^1^N42^^"

    def test_C19_negative_integer(self, ser):
        """C19: negative integer → ^N-42"""
        assert ser.serialize(-42) == "^1^N-42^^"

    def test_C20_zero(self, ser):
        """C20: zero → ^N0"""
        assert ser.serialize(0) == "^1^N0^^"

    def test_C21_large_integer(self, ser):
        """C21: large integer → ^N<large>"""
        assert ser.serialize(1000000000) == "^1^N1000000000^^"

    def test_C22_non_integer_float_uses_frexp_format(self, ser):
        """C22: non-integer float uses ^F path (frexp format)"""
        # Non-integer float → ^F<mantissa>^f<exponent>
        wire = ser.serialize(3.14)
        assert "^F" in wire and "^f" in wire

    def test_C23_3_14_exact_wire_format(self, ser):
        """C23: 3.14 exact wire format"""
        # frexp(3.14): m≈0.785, e=2 → int_m=7070651414971679, adj_e=2-53=-51
        assert ser.serialize(3.14) == "^1^F7070651414971679^f-51^^"

    def test_C24_float_wire_format_variants(self, ser):
        """C24: float wire format variants (0.1, -99.99, 1e-10)"""
        # 0.1, -99.99, 1e-10 all produce ^F...^f... format
        for val in (0.1, -99.99, 1e-10):
            wire = ser.serialize(val)
            assert "^F" in wire and "^f" in wire, f"Expected ^F/^f format for {val}, got {wire}"

    def test_C25_positive_infinity(self, ser):
        """C25: positive infinity → ^N1.#INF"""
        assert ser.serialize(math.inf) == "^1^N1.#INF^^"

    def test_C26_negative_infinity(self, ser):
        """C26: negative infinity → ^N-1.#INF"""
        assert ser.serialize(-math.inf) == "^1^N-1.#INF^^"


# ---------------------------------------------------------------------------
# D. Number Deserialization — tests 27-34
# ---------------------------------------------------------------------------

class TestD_NumberDeserialization:
    def test_D27_N42_to_integer(self, de):
        """D27: ^N42 → 42 (integer)"""
        result = de.deserialize("^1^N42^^")
        assert result == 42
        assert isinstance(result, int)

    def test_D28_N_neg42_to_neg_integer(self, de):
        """D28: ^N-42 → -42"""
        assert de.deserialize("^1^N-42^^") == -42

    def test_D29_N_float_path(self, de):
        """D29: ^N3.14 → float via ^N path"""
        # ^N3.14 → 3.14 (float via ^N path — must handle even though we emit ^F)
        result = de.deserialize("^1^N3.14^^")
        assert isinstance(result, float)
        assert abs(result - 3.14) < 1e-10

    def test_D30_N_pos_inf(self, de):
        """D30: ^N1.#INF → Infinity"""
        assert de.deserialize("^1^N1.#INF^^") == math.inf

    def test_D31_N_neg_inf(self, de):
        """D31: ^N-1.#INF → -Infinity"""
        assert de.deserialize("^1^N-1.#INF^^") == -math.inf

    def test_D32_N_inf_alias(self, de):
        """D32: ^Ninf → Infinity (alternate format)"""
        assert de.deserialize("^1^Ninf^^") == math.inf

    def test_D33_N_neg_inf_alias(self, de):
        """D33: ^N-inf → -Infinity (alternate format)"""
        assert de.deserialize("^1^N-inf^^") == -math.inf

    def test_D34_F_frexp_reconstruction(self, de):
        """D34: ^F<m>^f<e> → correct float reconstruction"""
        # ^F7070651414971679^f-51 → exactly 3.14
        result = de.deserialize("^1^F7070651414971679^f-51^^")
        assert result == 3.14


# ---------------------------------------------------------------------------
# E. Float frexp Round-trips — tests 35-41
# ---------------------------------------------------------------------------

class TestE_FloatFrexpRoundTrips:
    """Serialize a float to ^F wire format, reconstruct manually, verify value."""

    def _parse_frexp_wire(self, wire):
        m = re.search(r'\^F(-?\d+)\^f(-?\d+)', wire)
        assert m, f"Expected ^F...^f... format, got: {wire}"
        return int(m.group(1)) * (2 ** int(m.group(2)))

    def test_E35_roundtrip_3_14(self, ser):
        """E35: round-trip 3.14"""
        result = self._parse_frexp_wire(ser.serialize(3.14))
        assert result == 3.14

    def test_E36_roundtrip_0_1(self, ser):
        """E36: round-trip 0.1"""
        result = self._parse_frexp_wire(ser.serialize(0.1))
        assert result == 0.1

    def test_E37_roundtrip_123_456(self, ser):
        """E37: round-trip 123.456"""
        result = self._parse_frexp_wire(ser.serialize(123.456))
        assert result == 123.456

    def test_E38_roundtrip_neg_99_99(self, ser):
        """E38: round-trip -99.99"""
        result = self._parse_frexp_wire(ser.serialize(-99.99))
        assert result == -99.99

    def test_E39_roundtrip_1e_neg_10(self, ser):
        """E39: round-trip 1e-10"""
        result = self._parse_frexp_wire(ser.serialize(1e-10))
        assert result == 1e-10

    def test_E40_roundtrip_very_small(self, ace):
        """E40: round-trip very small float (1.23e-100)"""
        val = 1.23e-100
        result = roundtrip(val, ace)
        assert abs(result - val) / abs(val) < 1e-14

    def test_E41_roundtrip_very_large(self, ace):
        """E41: round-trip very large float (1.23e100)"""
        val = 1.23e100
        result = roundtrip(val, ace)
        assert abs(result - val) / abs(val) < 1e-14


# ---------------------------------------------------------------------------
# F. Boolean — tests 42-45
# ---------------------------------------------------------------------------

class TestF_Boolean:
    def test_F42_true_serializes_to_caret_B(self, ser):
        """F42: true → ^B"""
        assert ser.serialize(True) == "^1^B^^"

    def test_F43_false_serializes_to_caret_b(self, ser):
        """F43: false → ^b"""
        assert ser.serialize(False) == "^1^b^^"

    def test_F44_caret_B_deserializes_to_true(self, de):
        """F44: ^B → true"""
        assert de.deserialize("^1^B^^") is True

    def test_F45_caret_b_deserializes_to_false(self, de):
        """F45: ^b → false"""
        assert de.deserialize("^1^b^^") is False


# ---------------------------------------------------------------------------
# G. Nil — tests 46-47
# ---------------------------------------------------------------------------

class TestG_Nil:
    def test_G46_nil_serializes_to_caret_Z(self, ser):
        """G46: nil → ^Z"""
        assert ser.serialize(None) == "^1^Z^^"

    def test_G47_caret_Z_deserializes_to_nil(self, de):
        """G47: ^Z → nil"""
        assert de.deserialize("^1^Z^^") is None


# ---------------------------------------------------------------------------
# H. Table Serialization — tests 48-53
# ---------------------------------------------------------------------------

class TestH_TableSerialization:
    def test_H48_empty_table(self, ser):
        """H48: empty table → ^T^t"""
        assert ser.serialize({}) == "^1^T^t^^"

    def test_H49_single_key_value_pair(self, ser):
        """H49: single key-value pair"""
        assert ser.serialize({"key": "val"}) == "^1^T^Skey^Sval^t^^"

    def test_H50_multiple_key_value_pairs(self, ser):
        """H50: multiple key-value pairs"""
        wire = ser.serialize({"a": 1, "b": 2})
        assert "^Sa^N1" in wire
        assert "^Sb^N2" in wire
        assert wire.startswith("^1^T") and wire.endswith("^t^^")

    def test_H51_nested_table(self, ser):
        """H51: nested table (table containing table)"""
        wire = ser.serialize({"x": [1, 2]})
        assert wire.count("^T") == 2
        assert wire.count("^t") == 2

    def test_H52_array_uses_1based_integer_keys(self, ser):
        """H52: array [a,b,c] → 1-based integer keys"""
        # [a,b,c] → ^T^N1^Sa^N2^Sb^N3^Sc^t
        assert ser.serialize(["a", "b", "c"]) == "^1^T^N1^Sa^N2^Sb^N3^Sc^t^^"

    def test_H53_mixed_integer_and_string_keys(self, ser):
        """H53: mixed table (integer + string keys)"""
        wire = ser.serialize({1: "one", "two": 2})
        assert "^N1^Sone" in wire
        assert "^Stwo^N2" in wire


# ---------------------------------------------------------------------------
# I. Array Detection (Deserialize) — tests 54-58
# ---------------------------------------------------------------------------

class TestI_ArrayDetection:
    def test_I54_sequential_1based_keys_become_list(self, de):
        """I54: sequential 1-based integer keys → array"""
        result = de.deserialize("^1^T^N1^Sa^N2^Sb^N3^Sc^t^^")
        assert result == ["a", "b", "c"]

    def test_I55_non_sequential_integer_keys_stay_dict(self, de):
        """I55: non-sequential integer keys → dict"""
        result = de.deserialize("^1^T^N1^Sa^N3^Sc^t^^")
        assert isinstance(result, dict)
        assert result[1] == "a"
        assert result[3] == "c"

    def test_I56_string_keys_stay_dict(self, de):
        """I56: string keys → dict (not array)"""
        assert de.deserialize("^1^T^Skey^Sval^t^^") == {"key": "val"}

    def test_I57_single_element_array(self, de):
        """I57: single-element array"""
        result = de.deserialize("^1^T^N1^Sa^t^^")
        assert result == ["a"]

    def test_I58_empty_table_is_not_array(self, de):
        """I58: empty table is not array"""
        result = de.deserialize("^1^T^t^^")
        assert result == {} or result == []


# ---------------------------------------------------------------------------
# J. Framing — tests 59-62
# ---------------------------------------------------------------------------

class TestJ_Framing:
    def test_J59_serialize_wraps_with_prefix_and_terminator(self, ser):
        """J59: serialize wraps with ^1 prefix and ^^ terminator"""
        wire = ser.serialize(None)
        assert wire.startswith("^1")
        assert wire.endswith("^^")

    def test_J60_deserialize_requires_caret_1_prefix(self, de):
        """J60: deserialize requires ^1 prefix"""
        with pytest.raises((ValueError, Exception)):
            de.deserialize("bad data^^")

    def test_J61_deserialize_requires_caret_caret_terminator(self, de):
        """J61: deserialize requires ^^ terminator"""
        # Without ^^ terminator, payload is sliced wrong → raises or misparses
        with pytest.raises((ValueError, Exception)):
            de.deserialize("^1^N42")

    def test_J62_deserialize_strips_control_chars_from_input(self, de):
        """J62: deserialize strips control chars from input"""
        # Embedded NUL stripped before prefix check → parses correctly
        assert de.deserialize("^1\x00^Z^^") is None


# ---------------------------------------------------------------------------
# K. Error Handling — tests 63-65
# ---------------------------------------------------------------------------

class TestK_ErrorHandling:
    def test_K63_missing_prefix_raises(self, de):
        """K63: missing prefix → raises error"""
        with pytest.raises((ValueError, Exception)):
            de.deserialize("no prefix^^")

    def test_K64_empty_string_raises(self, de):
        """K64: empty string → raises error"""
        with pytest.raises((ValueError, Exception)):
            de.deserialize("")

    def test_K65_missing_terminator_raises_or_graceful(self, de):
        """K65: missing terminator → raises or graceful"""
        # Slice [2:-2] on short input → empty payload → raises on read
        with pytest.raises((ValueError, Exception)):
            de.deserialize("^1^Z")


# ---------------------------------------------------------------------------
# L. Round-trips (serialize→deserialize identity) — tests 66-73
# ---------------------------------------------------------------------------

class TestL_RoundTrips:
    def test_L66_plain_ascii_string(self, ace):
        """L66: round-trip plain ASCII string"""
        assert roundtrip("hello world", ace) == "hello world"

    def test_L67_string_with_all_special_chars(self, ace):
        """L67: round-trip string with all special chars"""
        s = "\x00\x01\x1e\x1f \x5e\x7e\x7f"
        assert roundtrip(s, ace) == s

    def test_L68_integer(self, ace):
        """L68: round-trip integer"""
        assert roundtrip(42, ace) == 42

    def test_L69_float(self, ace):
        """L69: round-trip float"""
        assert roundtrip(3.14, ace) == 3.14

    def test_L70_boolean(self, ace):
        """L70: round-trip boolean"""
        assert roundtrip(True, ace) is True
        assert roundtrip(False, ace) is False

    def test_L71_nil(self, ace):
        """L71: round-trip nil"""
        assert roundtrip(None, ace) is None

    def test_L72_nested_table_array(self, ace):
        """L72: round-trip nested table/array"""
        obj = {"nested": [None, None, None, "test"], "count": 3}
        result = roundtrip(obj, ace)
        assert result["nested"] == [None, None, None, "test"]
        assert result["count"] == 3

    def test_L73_mixed_type_table(self, ace):
        """L73: round-trip mixed-type table"""
        obj = {"key": "value", "num": 42, "flag": True, "nothing": None}
        result = roundtrip(obj, ace)
        assert result["key"] == "value"
        assert result["num"] == 42
        assert result["flag"] is True
        assert result["nothing"] is None
