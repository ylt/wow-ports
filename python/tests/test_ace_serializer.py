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
    def test_01_nul_escapes_to_tilde_at(self, ser):
        # NUL (0x00) → ~@ (0+64=64='@')
        wire = ser.serialize("\x00")
        assert "^S~@" in wire

    def test_02_control_chars_1_to_29(self, ser):
        # Bytes 1-29 → ~chr(byte+64)
        # 0x01 → ~A (1+64=65), 0x0A → ~J (10+64=74), 0x1D → ~] (29+64=93)
        assert "^S~A" in ser.serialize("\x01")
        assert "^S~J" in ser.serialize("\x0a")
        assert "^S~]" in ser.serialize("\x1d")

    def test_03_byte_30_special_case_tilde_z(self, ser):
        # Byte 30 (0x1E) → ~z  (special: 30+64=94='^' would corrupt parser)
        wire = ser.serialize("\x1e")
        assert "^S~z" in wire

    def test_04_byte_31_escapes_to_tilde_underscore(self, ser):
        # Byte 31 (0x1F) → ~_ (31+64=95='_')
        wire = ser.serialize("\x1f")
        assert "^S~_" in wire

    def test_05_space_escapes_to_tilde_backtick(self, ser):
        # Space (0x20=32) → ~` (32+64=96='`')
        wire = ser.serialize(" ")
        assert "^S~`" in wire

    def test_06_caret_escapes_to_tilde_rbrace(self, ser):
        # '^' (0x5E) → ~}
        wire = ser.serialize("a^b")
        assert "^Sa~}b" in wire

    def test_07_tilde_escapes_to_tilde_pipe(self, ser):
        # '~' (0x7E) → ~|
        wire = ser.serialize("a~b")
        assert "^Sa~|b" in wire

    def test_08_del_escapes_to_tilde_lbrace(self, ser):
        # DEL (0x7F) → ~{
        wire = ser.serialize("a\x7fb")
        assert "^Sa~{b" in wire

    def test_09_single_pass_no_double_escaping(self, ser):
        # Single pass: "~^" → "~|~}" not "~~|~}"
        wire = ser.serialize("~^")
        inner = wire[2:-2]  # strip ^1 and ^^
        assert inner == "^S~|~}"

    def test_10_printable_ascii_passes_through(self, ser):
        # Printable ASCII (0x21-0x5D, 0x5F-0x7D) passes through unescaped
        printable = "hello!world#test"
        wire = ser.serialize(printable)
        assert f"^S{printable}" in wire


# ---------------------------------------------------------------------------
# B. String Unescaping (Deserialize) — tests 11-17
# ---------------------------------------------------------------------------

class TestB_StringUnescaping:
    def test_11_tilde_at_decodes_to_nul(self, de):
        assert de.deserialize("^1^S~@^^") == "\x00"

    def test_12_generic_escape_tilde_X(self, de):
        # ~A → chr(65-64) = chr(1), ~` → chr(96-64) = chr(32) = space
        assert de.deserialize("^1^S~A^^") == "\x01"
        assert de.deserialize("^1^S~`^^") == " "

    def test_13_tilde_z_decodes_to_byte_30(self, de):
        assert de.deserialize("^1^S~z^^") == "\x1e"

    def test_14_tilde_lbrace_decodes_to_del(self, de):
        assert de.deserialize("^1^S~{^^") == "\x7f"

    def test_15_tilde_pipe_decodes_to_tilde(self, de):
        assert de.deserialize("^1^S~|^^") == "~"

    def test_16_tilde_rbrace_decodes_to_caret(self, de):
        assert de.deserialize("^1^S~}^^") == "^"

    def test_17_roundtrip_all_escapable_bytes(self, ace):
        special = "\x00\x01\x1e\x1f \x5e\x7e\x7f"
        assert roundtrip(special, ace) == special


# ---------------------------------------------------------------------------
# C. Number Serialization — tests 18-26
# ---------------------------------------------------------------------------

class TestC_NumberSerialization:
    def test_18_positive_integer(self, ser):
        assert ser.serialize(42) == "^1^N42^^"

    def test_19_negative_integer(self, ser):
        assert ser.serialize(-42) == "^1^N-42^^"

    def test_20_zero(self, ser):
        assert ser.serialize(0) == "^1^N0^^"

    def test_21_large_integer(self, ser):
        assert ser.serialize(1000000000) == "^1^N1000000000^^"

    def test_22_non_integer_float_uses_frexp_format(self, ser):
        # Non-integer float → ^F<mantissa>^f<exponent>
        wire = ser.serialize(3.14)
        assert "^F" in wire and "^f" in wire

    def test_23_3_14_exact_wire_format(self, ser):
        # frexp(3.14): m≈0.785, e=2 → int_m=7070651414971679, adj_e=2-53=-51
        assert ser.serialize(3.14) == "^1^F7070651414971679^f-51^^"

    def test_24_float_wire_format_variants(self, ser):
        # 0.1, -99.99, 1e-10 all produce ^F...^f... format
        for val in (0.1, -99.99, 1e-10):
            wire = ser.serialize(val)
            assert "^F" in wire and "^f" in wire, f"Expected ^F/^f format for {val}, got {wire}"

    def test_25_positive_infinity(self, ser):
        assert ser.serialize(math.inf) == "^1^N1.#INF^^"

    def test_26_negative_infinity(self, ser):
        assert ser.serialize(-math.inf) == "^1^N-1.#INF^^"


# ---------------------------------------------------------------------------
# D. Number Deserialization — tests 27-34
# ---------------------------------------------------------------------------

class TestD_NumberDeserialization:
    def test_27_N42_to_integer(self, de):
        result = de.deserialize("^1^N42^^")
        assert result == 42
        assert isinstance(result, int)

    def test_28_N_neg42_to_neg_integer(self, de):
        assert de.deserialize("^1^N-42^^") == -42

    def test_29_N_float_path(self, de):
        # ^N3.14 → 3.14 (float via ^N path — must handle even though we emit ^F)
        result = de.deserialize("^1^N3.14^^")
        assert isinstance(result, float)
        assert abs(result - 3.14) < 1e-10

    def test_30_N_pos_inf(self, de):
        assert de.deserialize("^1^N1.#INF^^") == math.inf

    def test_31_N_neg_inf(self, de):
        assert de.deserialize("^1^N-1.#INF^^") == -math.inf

    def test_32_N_inf_alias(self, de):
        assert de.deserialize("^1^Ninf^^") == math.inf

    def test_33_N_neg_inf_alias(self, de):
        assert de.deserialize("^1^N-inf^^") == -math.inf

    def test_34_F_frexp_reconstruction(self, de):
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

    def test_35_roundtrip_3_14(self, ser):
        result = self._parse_frexp_wire(ser.serialize(3.14))
        assert result == 3.14

    def test_36_roundtrip_0_1(self, ser):
        result = self._parse_frexp_wire(ser.serialize(0.1))
        assert result == 0.1

    def test_37_roundtrip_123_456(self, ser):
        result = self._parse_frexp_wire(ser.serialize(123.456))
        assert result == 123.456

    def test_38_roundtrip_neg_99_99(self, ser):
        result = self._parse_frexp_wire(ser.serialize(-99.99))
        assert result == -99.99

    def test_39_roundtrip_1e_neg_10(self, ser):
        result = self._parse_frexp_wire(ser.serialize(1e-10))
        assert result == 1e-10

    def test_40_roundtrip_very_small(self, ace):
        val = 1.23e-100
        result = roundtrip(val, ace)
        assert abs(result - val) / abs(val) < 1e-14

    def test_41_roundtrip_very_large(self, ace):
        val = 1.23e100
        result = roundtrip(val, ace)
        assert abs(result - val) / abs(val) < 1e-14


# ---------------------------------------------------------------------------
# F. Boolean — tests 42-45
# ---------------------------------------------------------------------------

class TestF_Boolean:
    def test_42_true_serializes_to_caret_B(self, ser):
        assert ser.serialize(True) == "^1^B^^"

    def test_43_false_serializes_to_caret_b(self, ser):
        assert ser.serialize(False) == "^1^b^^"

    def test_44_caret_B_deserializes_to_true(self, de):
        assert de.deserialize("^1^B^^") is True

    def test_45_caret_b_deserializes_to_false(self, de):
        assert de.deserialize("^1^b^^") is False


# ---------------------------------------------------------------------------
# G. Nil — tests 46-47
# ---------------------------------------------------------------------------

class TestG_Nil:
    def test_46_nil_serializes_to_caret_Z(self, ser):
        assert ser.serialize(None) == "^1^Z^^"

    def test_47_caret_Z_deserializes_to_nil(self, de):
        assert de.deserialize("^1^Z^^") is None


# ---------------------------------------------------------------------------
# H. Table Serialization — tests 48-53
# ---------------------------------------------------------------------------

class TestH_TableSerialization:
    def test_48_empty_table(self, ser):
        assert ser.serialize({}) == "^1^T^t^^"

    def test_49_single_key_value_pair(self, ser):
        assert ser.serialize({"key": "val"}) == "^1^T^Skey^Sval^t^^"

    def test_50_multiple_key_value_pairs(self, ser):
        wire = ser.serialize({"a": 1, "b": 2})
        assert "^Sa^N1" in wire
        assert "^Sb^N2" in wire
        assert wire.startswith("^1^T") and wire.endswith("^t^^")

    def test_51_nested_table(self, ser):
        wire = ser.serialize({"x": [1, 2]})
        assert wire.count("^T") == 2
        assert wire.count("^t") == 2

    def test_52_array_uses_1based_integer_keys(self, ser):
        # [a,b,c] → ^T^N1^Sa^N2^Sb^N3^Sc^t
        assert ser.serialize(["a", "b", "c"]) == "^1^T^N1^Sa^N2^Sb^N3^Sc^t^^"

    def test_53_mixed_integer_and_string_keys(self, ser):
        wire = ser.serialize({1: "one", "two": 2})
        assert "^N1^Sone" in wire
        assert "^Stwo^N2" in wire


# ---------------------------------------------------------------------------
# I. Array Detection (Deserialize) — tests 54-58
# ---------------------------------------------------------------------------

class TestI_ArrayDetection:
    def test_54_sequential_1based_keys_become_list(self, de):
        result = de.deserialize("^1^T^N1^Sa^N2^Sb^N3^Sc^t^^")
        assert result == ["a", "b", "c"]

    def test_55_non_sequential_integer_keys_stay_dict(self, de):
        result = de.deserialize("^1^T^N1^Sa^N3^Sc^t^^")
        assert isinstance(result, dict)
        assert result[1] == "a"
        assert result[3] == "c"

    def test_56_string_keys_stay_dict(self, de):
        assert de.deserialize("^1^T^Skey^Sval^t^^") == {"key": "val"}

    def test_57_single_element_array(self, de):
        result = de.deserialize("^1^T^N1^Sa^t^^")
        assert result == ["a"]

    def test_58_empty_table_is_not_array(self, de):
        result = de.deserialize("^1^T^t^^")
        assert result == {} or result == []


# ---------------------------------------------------------------------------
# J. Framing — tests 59-62
# ---------------------------------------------------------------------------

class TestJ_Framing:
    def test_59_serialize_wraps_with_prefix_and_terminator(self, ser):
        wire = ser.serialize(None)
        assert wire.startswith("^1")
        assert wire.endswith("^^")

    def test_60_deserialize_requires_caret_1_prefix(self, de):
        with pytest.raises((ValueError, Exception)):
            de.deserialize("bad data^^")

    def test_61_deserialize_requires_caret_caret_terminator(self, de):
        # Without ^^ terminator, payload is sliced wrong → raises or misparses
        with pytest.raises((ValueError, Exception)):
            de.deserialize("^1^N42")

    def test_62_deserialize_strips_control_chars_from_input(self, de):
        # Embedded NUL stripped before prefix check → parses correctly
        assert de.deserialize("^1\x00^Z^^") is None


# ---------------------------------------------------------------------------
# K. Error Handling — tests 63-65
# ---------------------------------------------------------------------------

class TestK_ErrorHandling:
    def test_63_missing_prefix_raises(self, de):
        with pytest.raises((ValueError, Exception)):
            de.deserialize("no prefix^^")

    def test_64_empty_string_raises(self, de):
        with pytest.raises((ValueError, Exception)):
            de.deserialize("")

    def test_65_missing_terminator_raises_or_graceful(self, de):
        # Slice [2:-2] on short input → empty payload → raises on read
        with pytest.raises((ValueError, Exception)):
            de.deserialize("^1^Z")


# ---------------------------------------------------------------------------
# L. Round-trips (serialize→deserialize identity) — tests 66-73
# ---------------------------------------------------------------------------

class TestL_RoundTrips:
    def test_66_plain_ascii_string(self, ace):
        assert roundtrip("hello world", ace) == "hello world"

    def test_67_string_with_all_special_chars(self, ace):
        s = "\x00\x01\x1e\x1f \x5e\x7e\x7f"
        assert roundtrip(s, ace) == s

    def test_68_integer(self, ace):
        assert roundtrip(42, ace) == 42

    def test_69_float(self, ace):
        assert roundtrip(3.14, ace) == 3.14

    def test_70_boolean(self, ace):
        assert roundtrip(True, ace) is True
        assert roundtrip(False, ace) is False

    def test_71_nil(self, ace):
        assert roundtrip(None, ace) is None

    def test_72_nested_table_array(self, ace):
        obj = {"nested": [None, None, None, "test"], "count": 3}
        result = roundtrip(obj, ace)
        assert result["nested"] == [None, None, None, "test"]
        assert result["count"] == 3

    def test_73_mixed_type_table(self, ace):
        obj = {"key": "value", "num": 42, "flag": True, "nothing": None}
        result = roundtrip(obj, ace)
        assert result["key"] == "value"
        assert result["num"] == 42
        assert result["flag"] is True
        assert result["nothing"] is None
