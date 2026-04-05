"""Tests for WowCbor wrapper."""

import cbor2
import pytest
from wow_serialization.wow_cbor import WowCbor


def describe_WowCbor():

    def describe_roundtrip():
        def it_string():
            assert WowCbor.decode(WowCbor.encode("hello")) == "hello"

        def it_integer():
            assert WowCbor.decode(WowCbor.encode(42)) == 42

        def it_boolean():
            assert WowCbor.decode(WowCbor.encode(True)) is True

        def it_none():
            assert WowCbor.decode(WowCbor.encode(None)) is None

        def it_string_keyed_dict():
            data = {"key": "value", "num": 7}
            result = WowCbor.decode(WowCbor.encode(data))
            assert result["key"] == "value"
            assert result["num"] == 7

        def it_list():
            data = ["a", "b", "c"]
            assert WowCbor.decode(WowCbor.encode(data)) == data

    def describe_byte_string_conversion():
        def it_bytes_converted_to_utf8_string():
            # CBOR encode bytes directly (cbor2 encodes Python bytes as CBOR type 2)
            result = WowCbor.decode(cbor2.dumps(b"hello"))
            assert result == "hello"
            assert isinstance(result, str)

        def it_nested_bytes_in_dict_converted():
            result = WowCbor.decode(cbor2.dumps({"key": b"world"}))
            assert result["key"] == "world"
            assert isinstance(result["key"], str)

        def it_bytes_in_list_converted():
            assert WowCbor.decode(cbor2.dumps([b"a", b"b"])) == ["a", "b"]

    def describe_array_detection():
        def it_sequential_1based_int_keys_to_list():
            # cbor2 preserves integer keys in dicts
            result = WowCbor.decode(cbor2.dumps({1: "a", 2: "b", 3: "c"}))
            assert result == ["a", "b", "c"]

        def it_non_sequential_int_keys_stay_as_dict():
            result = WowCbor.decode(cbor2.dumps({1: "a", 3: "c"}))
            assert isinstance(result, dict)
            assert result[1] == "a"
            assert result[3] == "c"

        def it_zero_based_int_keys_stay_as_dict():
            result = WowCbor.decode(cbor2.dumps({0: "a", 1: "b", 2: "c"}))
            assert isinstance(result, dict)

        def it_string_keyed_dict_stays_as_dict():
            result = WowCbor.decode(WowCbor.encode({"a": 1, "b": 2}))
            assert isinstance(result, dict)
            assert result["a"] == 1

        def it_non_string_keys_preserved():
            result = WowCbor.decode(cbor2.dumps({10: "x", 20: "y"}))
            assert isinstance(result, dict)
            assert result[10] == "x"
            assert result[20] == "y"
