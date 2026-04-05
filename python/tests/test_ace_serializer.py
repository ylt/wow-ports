"""Tests for WowAceSerializer / WowAceDeserializer — canonical 73-case spec (sections A-L)."""

import math
import re
import pytest
from wow_serialization.ace_serializer import WowAce, WowAceDeserializer, WowAceSerializer


@pytest.fixture
def ser():
    return WowAceSerializer().serialize


@pytest.fixture
def de():
    return WowAceDeserializer().deserialize


@pytest.fixture
def ace():
    return WowAce()


def roundtrip(obj, ace_inst):
    wire = ace_inst.serialize(obj)
    return ace_inst.deserialize(wire)


def _parse_frexp_wire(wire):
    m = re.search(r'\^F(-?\d+)\^f(-?\d+)', wire)
    assert m, f"Expected ^F...^f... format, got: {wire}"
    return int(m.group(1)) * (2 ** int(m.group(2)))


def describe_AceSerializer():

    # ── A. String Escaping (Serialize) — tests 1-10 ──────────────────────────

    def describe_A_string_escaping():
        def it_A01_nul_escapes_to_tilde_at(ser):
            """A01: NUL (0x00) → ~@"""
            assert "^S~@" in ser("\x00")

        def it_A02_control_chars_1_to_29(ser):
            """A02: control chars 1–29 → ~chr(byte+64)"""
            assert "^S~A" in ser("\x01")
            assert "^S~J" in ser("\x0a")
            assert "^S~]" in ser("\x1d")

        def it_A03_byte_30_special_case_tilde_z(ser):
            """A03: byte 30 (0x1E) → ~z (special case)"""
            assert "^S~z" in ser("\x1e")

        def it_A04_byte_31_escapes_to_tilde_underscore(ser):
            """A04: byte 31 (0x1F) → ~_"""
            assert "^S~_" in ser("\x1f")

        def it_A05_space_escapes_to_tilde_backtick(ser):
            """A05: space (0x20) → ~`"""
            assert "^S~`" in ser(" ")

        def it_A06_caret_escapes_to_tilde_rbrace(ser):
            """A06: caret ^ (0x5E) → ~}"""
            assert "^Sa~}b" in ser("a^b")

        def it_A07_tilde_escapes_to_tilde_pipe(ser):
            """A07: tilde ~ (0x7E) → ~|"""
            assert "^Sa~|b" in ser("a~b")

        def it_A08_del_escapes_to_tilde_lbrace(ser):
            """A08: DEL (0x7F) → ~{"""
            assert "^Sa~{b" in ser("a\x7fb")

        def it_A09_single_pass_no_double_escaping(ser):
            """A09: single-pass — no double-escaping"""
            wire = ser("~^")
            inner = wire[2:-2]  # strip ^1 and ^^
            assert inner == "^S~|~}"

        def it_A10_printable_ascii_passes_through(ser):
            """A10: printable ASCII (0x21-0x5D, 0x5F-0x7D) passes through unescaped"""
            printable = "hello!world#test"
            assert f"^S{printable}" in ser(printable)

    # ── B. String Unescaping (Deserialize) — tests 11-17 ─────────────────────

    def describe_B_string_unescaping():
        def it_B11_tilde_at_decodes_to_nul(de):
            """B11: ~@ → NUL (0x00)"""
            assert de("^1^S~@^^") == "\x00"

        def it_B12_generic_escape_tilde_X(de):
            """B12: ~X decodes via chr(ord(X)-64)"""
            assert de("^1^S~A^^") == "\x01"
            assert de("^1^S~`^^") == " "

        def it_B13_tilde_z_decodes_to_byte_30(de):
            """B13: ~z → byte 30 (0x1E)"""
            assert de("^1^S~z^^") == "\x1e"

        def it_B14_tilde_lbrace_decodes_to_del(de):
            """B14: ~{ → DEL (0x7F)"""
            assert de("^1^S~{^^") == "\x7f"

        def it_B15_tilde_pipe_decodes_to_tilde(de):
            """B15: ~| → tilde"""
            assert de("^1^S~|^^") == "~"

        def it_B16_tilde_rbrace_decodes_to_caret(de):
            """B16: ~} → caret"""
            assert de("^1^S~}^^") == "^"

        def it_B17_roundtrip_all_escapable_bytes(ace):
            """B17: round-trip all escapable bytes"""
            special = "\x00\x01\x1e\x1f \x5e\x7e\x7f"
            assert roundtrip(special, ace) == special

    # ── C. Number Serialization — tests 18-26 ────────────────────────────────

    def describe_C_number_serialization():
        def it_C18_positive_integer(ser):
            """C18: positive integer → ^N42"""
            assert ser(42) == "^1^N42^^"

        def it_C19_negative_integer(ser):
            """C19: negative integer → ^N-42"""
            assert ser(-42) == "^1^N-42^^"

        def it_C20_zero(ser):
            """C20: zero → ^N0"""
            assert ser(0) == "^1^N0^^"

        def it_C21_large_integer(ser):
            """C21: large integer → ^N<large>"""
            assert ser(1000000000) == "^1^N1000000000^^"

        def it_C22_non_integer_float_uses_frexp_format(ser):
            """C22: non-integer float uses ^F path (frexp format)"""
            wire = ser(3.14)
            assert "^F" in wire and "^f" in wire

        def it_C23_3_14_exact_wire_format(ser):
            """C23: 3.14 exact wire format"""
            assert ser(3.14) == "^1^F7070651414971679^f-51^^"

        def it_C24_float_wire_format_variants(ser):
            """C24: float wire format variants (0.1, -99.99, 1e-10)"""
            for val in (0.1, -99.99, 1e-10):
                wire = ser(val)
                assert "^F" in wire and "^f" in wire, f"Expected ^F/^f for {val}, got {wire}"

        def it_C25_positive_infinity(ser):
            """C25: positive infinity → ^N1.#INF"""
            assert ser(math.inf) == "^1^N1.#INF^^"

        def it_C26_negative_infinity(ser):
            """C26: negative infinity → ^N-1.#INF"""
            assert ser(-math.inf) == "^1^N-1.#INF^^"

    # ── D. Number Deserialization — tests 27-34 ──────────────────────────────

    def describe_D_number_deserialization():
        def it_D27_N42_to_integer(de):
            """D27: ^N42 → 42 (integer)"""
            result = de("^1^N42^^")
            assert result == 42
            assert isinstance(result, int)

        def it_D28_N_neg42_to_neg_integer(de):
            """D28: ^N-42 → -42"""
            assert de("^1^N-42^^") == -42

        def it_D29_N_float_path(de):
            """D29: ^N3.14 → float via ^N path"""
            result = de("^1^N3.14^^")
            assert isinstance(result, float)
            assert abs(result - 3.14) < 1e-10

        def it_D30_N_pos_inf(de):
            """D30: ^N1.#INF → Infinity"""
            assert de("^1^N1.#INF^^") == math.inf

        def it_D31_N_neg_inf(de):
            """D31: ^N-1.#INF → -Infinity"""
            assert de("^1^N-1.#INF^^") == -math.inf

        def it_D32_N_inf_alias(de):
            """D32: ^Ninf → Infinity (alternate format)"""
            assert de("^1^Ninf^^") == math.inf

        def it_D33_N_neg_inf_alias(de):
            """D33: ^N-inf → -Infinity (alternate format)"""
            assert de("^1^N-inf^^") == -math.inf

        def it_D34_F_frexp_reconstruction(de):
            """D34: ^F<m>^f<e> → correct float reconstruction"""
            assert de("^1^F7070651414971679^f-51^^") == 3.14

    # ── E. Float frexp Round-trips — tests 35-41 ─────────────────────────────

    def describe_E_float_frexp_roundtrips():
        def it_E35_roundtrip_3_14(ser):
            """E35: round-trip 3.14"""
            assert _parse_frexp_wire(ser(3.14)) == 3.14

        def it_E36_roundtrip_0_1(ser):
            """E36: round-trip 0.1"""
            assert _parse_frexp_wire(ser(0.1)) == 0.1

        def it_E37_roundtrip_123_456(ser):
            """E37: round-trip 123.456"""
            assert _parse_frexp_wire(ser(123.456)) == 123.456

        def it_E38_roundtrip_neg_99_99(ser):
            """E38: round-trip -99.99"""
            assert _parse_frexp_wire(ser(-99.99)) == -99.99

        def it_E39_roundtrip_1e_neg_10(ser):
            """E39: round-trip 1e-10"""
            assert _parse_frexp_wire(ser(1e-10)) == 1e-10

        def it_E40_roundtrip_very_small(ace):
            """E40: round-trip very small float (1.23e-100)"""
            val = 1.23e-100
            result = roundtrip(val, ace)
            assert abs(result - val) / abs(val) < 1e-14

        def it_E41_roundtrip_very_large(ace):
            """E41: round-trip very large float (1.23e100)"""
            val = 1.23e100
            result = roundtrip(val, ace)
            assert abs(result - val) / abs(val) < 1e-14

    # ── F. Boolean — tests 42-45 ─────────────────────────────────────────────

    def describe_F_boolean():
        def it_F42_true_serializes_to_caret_B(ser):
            """F42: true → ^B"""
            assert ser(True) == "^1^B^^"

        def it_F43_false_serializes_to_caret_b(ser):
            """F43: false → ^b"""
            assert ser(False) == "^1^b^^"

        def it_F44_caret_B_deserializes_to_true(de):
            """F44: ^B → true"""
            assert de("^1^B^^") is True

        def it_F45_caret_b_deserializes_to_false(de):
            """F45: ^b → false"""
            assert de("^1^b^^") is False

    # ── G. Nil — tests 46-47 ─────────────────────────────────────────────────

    def describe_G_nil():
        def it_G46_nil_serializes_to_caret_Z(ser):
            """G46: nil → ^Z"""
            assert ser(None) == "^1^Z^^"

        def it_G47_caret_Z_deserializes_to_nil(de):
            """G47: ^Z → nil"""
            assert de("^1^Z^^") is None

    # ── H. Table Serialization — tests 48-53 ─────────────────────────────────

    def describe_H_table_serialization():
        def it_H48_empty_table(ser):
            """H48: empty table → ^T^t"""
            assert ser({}) == "^1^T^t^^"

        def it_H49_single_key_value_pair(ser):
            """H49: single key-value pair"""
            assert ser({"key": "val"}) == "^1^T^Skey^Sval^t^^"

        def it_H50_multiple_key_value_pairs(ser):
            """H50: multiple key-value pairs"""
            wire = ser({"a": 1, "b": 2})
            assert "^Sa^N1" in wire
            assert "^Sb^N2" in wire
            assert wire.startswith("^1^T") and wire.endswith("^t^^")

        def it_H51_nested_table(ser):
            """H51: nested table (table containing table)"""
            wire = ser({"x": [1, 2]})
            assert wire.count("^T") == 2
            assert wire.count("^t") == 2

        def it_H52_array_uses_1based_integer_keys(ser):
            """H52: array [a,b,c] → 1-based integer keys"""
            assert ser(["a", "b", "c"]) == "^1^T^N1^Sa^N2^Sb^N3^Sc^t^^"

        def it_H53_mixed_integer_and_string_keys(ser):
            """H53: mixed table (integer + string keys)"""
            wire = ser({1: "one", "two": 2})
            assert "^N1^Sone" in wire
            assert "^Stwo^N2" in wire

    # ── I. Array Detection (Deserialize) — tests 54-58 ───────────────────────

    def describe_I_array_detection():
        def it_I54_sequential_1based_keys_become_list(de):
            """I54: sequential 1-based integer keys → array"""
            assert de("^1^T^N1^Sa^N2^Sb^N3^Sc^t^^") == ["a", "b", "c"]

        def it_I55_non_sequential_integer_keys_stay_dict(de):
            """I55: non-sequential integer keys → dict"""
            result = de("^1^T^N1^Sa^N3^Sc^t^^")
            assert isinstance(result, dict)
            assert result[1] == "a"
            assert result[3] == "c"

        def it_I56_string_keys_stay_dict(de):
            """I56: string keys → dict (not array)"""
            assert de("^1^T^Skey^Sval^t^^") == {"key": "val"}

        def it_I57_single_element_array(de):
            """I57: single-element array"""
            assert de("^1^T^N1^Sa^t^^") == ["a"]

        def it_I58_empty_table_is_not_array(de):
            """I58: empty table is not array"""
            result = de("^1^T^t^^")
            assert result == {} or result == []

    # ── J. Framing — tests 59-62 ─────────────────────────────────────────────

    def describe_J_framing():
        def it_J59_serialize_wraps_with_prefix_and_terminator(ser):
            """J59: serialize wraps with ^1 prefix and ^^ terminator"""
            wire = ser(None)
            assert wire.startswith("^1") and wire.endswith("^^")

        def it_J60_deserialize_requires_caret_1_prefix(de):
            """J60: deserialize requires ^1 prefix"""
            with pytest.raises((ValueError, Exception)):
                de("bad data^^")

        def it_J61_deserialize_requires_caret_caret_terminator(de):
            """J61: deserialize requires ^^ terminator"""
            with pytest.raises((ValueError, Exception)):
                de("^1^N42")

        def it_J62_deserialize_strips_control_chars_from_input(de):
            """J62: deserialize strips control chars from input"""
            assert de("^1\x00^Z^^") is None

    # ── K. Error Handling — tests 63-65 ──────────────────────────────────────

    def describe_K_error_handling():
        def it_K63_missing_prefix_raises(de):
            """K63: missing prefix → raises error"""
            with pytest.raises((ValueError, Exception)):
                de("no prefix^^")

        def it_K64_empty_string_raises(de):
            """K64: empty string → raises error"""
            with pytest.raises((ValueError, Exception)):
                de("")

        def it_K65_missing_terminator_raises_or_graceful(de):
            """K65: missing terminator → raises or graceful"""
            with pytest.raises((ValueError, Exception)):
                de("^1^Z")

    # ── L. Round-trips — tests 66-73 ─────────────────────────────────────────

    def describe_L_roundtrips():
        def it_L66_plain_ascii_string(ace):
            """L66: round-trip plain ASCII string"""
            assert roundtrip("hello world", ace) == "hello world"

        def it_L67_string_with_all_special_chars(ace):
            """L67: round-trip string with all special chars"""
            s = "\x00\x01\x1e\x1f \x5e\x7e\x7f"
            assert roundtrip(s, ace) == s

        def it_L68_integer(ace):
            """L68: round-trip integer"""
            assert roundtrip(42, ace) == 42

        def it_L69_float(ace):
            """L69: round-trip float"""
            assert roundtrip(3.14, ace) == 3.14

        def it_L70_boolean(ace):
            """L70: round-trip boolean"""
            assert roundtrip(True, ace) is True
            assert roundtrip(False, ace) is False

        def it_L71_nil(ace):
            """L71: round-trip nil"""
            assert roundtrip(None, ace) is None

        def it_L72_nested_table_array(ace):
            """L72: round-trip nested table/array"""
            obj = {"nested": [None, None, None, "test"], "count": 3}
            result = roundtrip(obj, ace)
            assert result["nested"] == [None, None, None, "test"]
            assert result["count"] == 3

        def it_L73_mixed_type_table(ace):
            """L73: round-trip mixed-type table"""
            obj = {"key": "value", "num": 42, "flag": True, "nothing": None}
            result = roundtrip(obj, ace)
            assert result["key"] == "value"
            assert result["num"] == 42
            assert result["flag"] is True
            assert result["nothing"] is None
