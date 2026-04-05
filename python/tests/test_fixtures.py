"""Fixture-based tests — reads testdata/fixtures.json and tests all languages' outputs."""

import json
import math
import os
import pytest
from wow_serialization.ace_serializer import WowAce
from wow_serialization.lua_deflate import decode_for_print, encode_for_print

FIXTURES_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'testdata', 'fixtures.json')

with open(FIXTURES_PATH, 'r', encoding='utf-8') as _f:
    _FIXTURES = json.load(_f)

_ACE_FIXTURES = _FIXTURES['ace_serializer']
_ACE_DET_FIXTURES = [f for f in _ACE_FIXTURES if f.get('serialize_deterministic') is not False]
_LD_FIXTURES = _FIXTURES['lua_deflate']


def to_native(v):
    """Convert a fixture value (which may contain __type__ wrappers) to a native Python value."""
    if v is None or isinstance(v, (bool, int, float, str)):
        return v
    if isinstance(v, list):
        return [to_native(el) for el in v]
    if isinstance(v, dict):
        t = v.get('__type__')
        if t == 'infinity':
            return math.inf
        if t == 'neg_infinity':
            return -math.inf
        if t == 'float':
            return float(v['value'])
        if t == 'bytes':
            return bytes.fromhex(v['hex']).decode('latin-1')
        return {k: to_native(val) for k, val in v.items()}
    return v


@pytest.fixture
def ace():
    return WowAce()


def describe_ace_serializer_fixtures():

    def describe_deserialize():
        @pytest.mark.parametrize('fixture', _ACE_FIXTURES,
                                 ids=[f['name'] for f in _ACE_FIXTURES])
        def it_deserializes(fixture, ace):
            result = ace.deserialize(fixture['ace_serialized'])
            assert result == to_native(fixture['input'])

    def describe_serialize():
        @pytest.mark.parametrize('fixture', _ACE_DET_FIXTURES,
                                 ids=[f['name'] for f in _ACE_DET_FIXTURES])
        def it_serializes(fixture, ace):
            result = ace.serialize(to_native(fixture['input']))
            assert result == fixture['ace_serialized']

    def describe_roundtrip():
        @pytest.mark.parametrize('fixture', _ACE_FIXTURES,
                                 ids=[f['name'] for f in _ACE_FIXTURES])
        def it_roundtrips(fixture, ace):
            value1 = ace.deserialize(fixture['ace_serialized'])
            wire2 = ace.serialize(value1)
            value2 = ace.deserialize(wire2)
            assert value2 == value1


def describe_lua_deflate_fixtures():

    def describe_encode():
        @pytest.mark.parametrize('fixture', _LD_FIXTURES,
                                 ids=[f['name'] for f in _LD_FIXTURES])
        def it_encodes(fixture):
            input_bytes = bytes.fromhex(fixture['input_hex'])
            assert encode_for_print(input_bytes) == fixture['encoded']

    def describe_decode():
        @pytest.mark.parametrize('fixture', _LD_FIXTURES,
                                 ids=[f['name'] for f in _LD_FIXTURES])
        def it_decodes(fixture):
            decoded = decode_for_print(fixture['encoded'])
            assert decoded.hex() == fixture['input_hex']
