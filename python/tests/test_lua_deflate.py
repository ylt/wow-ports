"""Tests for LuaDeflate encode/decode — canonical 23-case spec (sections M-P)."""

import os
import re
import pytest
from wow_serialization.lua_deflate import decode_for_print, encode_for_print
from wow_serialization.lua_deflate_native import (
    decode_for_print as decode_for_print_native,
    encode_for_print as encode_for_print_native,
)


def describe_LuaDeflate():

    # ── M. Encode — tests 74-79 ───────────────────────────────────────────────

    def describe_M_encode():
        def it_M74_three_byte_input_gives_4_chars():
            """M74: 3-byte input → 4 encoded chars (full group)"""
            assert len(encode_for_print(b"ABC")) == 4

        def it_M75_one_byte_input_gives_2_chars():
            """M75: 1-byte input → 2 encoded chars (tail)"""
            assert len(encode_for_print(b"A")) == 2

        def it_M76_two_byte_input_gives_3_chars():
            """M76: 2-byte input → 3 encoded chars (tail)"""
            assert len(encode_for_print(b"AB")) == 3

        def it_M77_six_byte_input_gives_8_chars():
            """M77: 6-byte input → 8 encoded chars (two full groups)"""
            assert len(encode_for_print(b"ABCDEF")) == 8

        def it_M78_empty_input_gives_empty_string():
            """M78: empty input → empty string"""
            assert encode_for_print(b"") == ""

        def it_M79_output_uses_only_alphabet_chars():
            """M79: output uses only alphabet chars a-zA-Z0-9()"""
            encoded = encode_for_print(bytes(range(256)))
            assert re.fullmatch(r'[a-zA-Z0-9()]+', encoded)

    # ── N. Decode — tests 80-86 ───────────────────────────────────────────────

    def describe_N_decode():
        def it_N80_four_char_input_gives_3_bytes():
            """N80: 4-char input → 3 bytes (full group)"""
            assert len(decode_for_print("aaaa")) == 3

        def it_N81_two_char_input_gives_1_byte():
            """N81: 2-char input → 1 byte (tail)"""
            assert len(decode_for_print("aa")) == 1

        def it_N82_three_char_input_gives_2_bytes():
            """N82: 3-char input → 2 bytes (tail)"""
            encoded = encode_for_print(b"AB")
            assert len(encoded) == 3
            assert len(decode_for_print(encoded)) == 2

        def it_N83_whitespace_stripped_before_decode():
            """N83: whitespace stripped from start/end before decode"""
            encoded = encode_for_print(b"test")
            assert decode_for_print("  " + encoded + "\n") == b"test"

        def it_N84_length_1_input_returns_none_or_empty():
            """N84: length-1 input → None or empty"""
            result = decode_for_print("a")
            assert result is None or result == b""

        def it_N85_empty_string_returns_none_or_empty():
            """N85: empty string → None or empty"""
            result = decode_for_print("")
            assert result is None or result == b""

        def it_N86_invalid_character_raises():
            """N86: invalid character raises"""
            with pytest.raises((ValueError, KeyError, TypeError)):
                decode_for_print("!!")

    # ── O. Round-trips — tests 87-93 ─────────────────────────────────────────

    def describe_O_roundtrips():
        def it_O87_simple_ascii_string():
            """O87: simple ASCII string"""
            assert decode_for_print(encode_for_print(b"Hello, World!")) == b"Hello, World!"

        def it_O88_binary_all_256_byte_values():
            """O88: binary data — all 256 byte values"""
            data = bytes(range(256))
            assert decode_for_print(encode_for_print(data)) == data

        def it_O89_large_payload():
            """O89: large payload (1000+ bytes)"""
            data = os.urandom(1024)
            assert decode_for_print(encode_for_print(data)) == data

        def it_O90_single_byte():
            """O90: single byte"""
            assert decode_for_print(encode_for_print(b"A")) == b"A"

        def it_O91_two_bytes():
            """O91: two bytes"""
            assert decode_for_print(encode_for_print(b"AB")) == b"AB"

        def it_O92_three_bytes_boundary():
            """O92: three bytes (boundary)"""
            assert decode_for_print(encode_for_print(b"ABC")) == b"ABC"

        def it_O93_null_bytes_roundtrip():
            """O93: null bytes (0x00) round-trip correctly"""
            data = b"\x00" * 10
            assert decode_for_print(encode_for_print(data)) == data

    # ── P. Native Variant — tests 94-96 ──────────────────────────────────────

    def describe_P_native_variant():
        def it_P94_native_encode_byte_identical_to_reference():
            """P94: native encode output byte-identical to reference encode"""
            for data in [b"hello", b"ABC", b"The quick brown fox", b"x" * 99]:
                assert encode_for_print_native(data) == encode_for_print(data), \
                    f"Mismatch for: {data[:20]}"

        def it_P95_native_decode_byte_identical_to_reference():
            """P95: native decode output byte-identical to reference decode"""
            data = b"round trip test string 123"
            encoded = encode_for_print(data)
            assert decode_for_print_native(encoded) == decode_for_print(encoded)

        def it_P96_native_roundtrip():
            """P96: native round-trip"""
            for data in [b"Hello, World!", bytes(range(256))]:
                assert decode_for_print_native(encode_for_print_native(data)) == data
