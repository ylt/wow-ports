"""Tests for Pipeline encode/decode."""

import pytest
from wow_serialization.pipeline import Pipeline, ExportResult


def roundtrip(addon, version, data, metadata=None):
    enc = Pipeline.encode(ExportResult(addon=addon, version=version, data=data, metadata=metadata))
    return Pipeline.decode(enc)


def describe_Pipeline():

    def describe_prefix_encoding():
        def it_wa_v1_uses_bang_prefix():
            enc = Pipeline.encode(ExportResult('weakauras', 1, 'x', None))
            assert enc.startswith('!')
            assert not enc.startswith('!WA:2!')
            assert not enc.startswith('!E1!')

        def it_elvui_uses_e1_prefix():
            enc = Pipeline.encode(ExportResult('elvui', 1, 'x', None))
            assert enc.startswith('!E1!')

        def it_legacy_v0_uses_no_prefix():
            enc = Pipeline.encode(ExportResult('weakauras', 0, 'x', None))
            assert not enc.startswith('!')

        def it_wa_v2_uses_wa2_prefix():
            enc = Pipeline.encode(ExportResult('weakauras', 2, {'a': 1}, None))
            assert enc.startswith('!WA:2!')

    def describe_prefix_detection():
        def it_e1_detects_elvui_v1():
            dec = roundtrip('elvui', 1, {'a': 1})
            assert dec.addon == 'elvui'
            assert dec.version == 1

        def it_bang_detects_weakauras_v1():
            dec = roundtrip('weakauras', 1, {'a': 1})
            assert dec.addon == 'weakauras'
            assert dec.version == 1

        def it_no_prefix_detects_legacy_v0():
            dec = roundtrip('weakauras', 0, {'a': 1})
            assert dec.addon == 'weakauras'
            assert dec.version == 0

        def it_wa2_detects_weakauras_v2():
            dec = roundtrip('weakauras', 2, {'a': 1})
            assert dec.addon == 'weakauras'
            assert dec.version == 2

    def describe_export_result_structure():
        def it_decode_returns_all_four_fields():
            dec = roundtrip('weakauras', 1, {'x': 1})
            assert hasattr(dec, 'addon')
            assert hasattr(dec, 'version')
            assert hasattr(dec, 'data')
            assert hasattr(dec, 'metadata')

    def describe_roundtrip():
        def it_wa_v1_string():
            dec = roundtrip('weakauras', 1, 'hello')
            assert dec.data == 'hello'
            assert dec.addon == 'weakauras'
            assert dec.version == 1
            assert dec.metadata is None

        def it_wa_v1_dict():
            dec = roundtrip('weakauras', 1, {'key': 'value', 'num': 42})
            assert dec.data['key'] == 'value'
            assert dec.data['num'] == 42

        def it_wa_v1_array():
            data = ['a', 'b', 'c']
            assert roundtrip('weakauras', 1, data).data == data

        def it_wa_v1_nested():
            data = {'outer': {'inner': 99}, 'list': [1, 2]}
            dec = roundtrip('weakauras', 1, data)
            assert dec.data['outer']['inner'] == 99
            assert dec.data['list'] == [1, 2]

        def it_legacy_v0_roundtrip():
            dec = roundtrip('weakauras', 0, {'flag': True, 'n': -5})
            assert dec.data['flag'] is True
            assert dec.data['n'] == -5

        def it_wa_v2_roundtrip():
            dec = roundtrip('weakauras', 2, {'key': 'v2data', 'num': 7})
            assert dec.data['key'] == 'v2data'
            assert dec.data['num'] == 7

    def describe_elvui_metadata():
        def it_roundtrip_preserves_profile_type_and_key():
            metadata = {'profile_type': 'profile', 'profile_key': 'Default'}
            dec = roundtrip('elvui', 1, {'setting': 1}, metadata)
            assert dec.addon == 'elvui'
            assert dec.metadata['profile_type'] == 'profile'
            assert dec.metadata['profile_key'] == 'Default'
            assert dec.data['setting'] == 1

        def it_elvui_without_metadata_gives_none():
            dec = roundtrip('elvui', 1, {'a': 1}, None)
            assert dec.metadata is None
