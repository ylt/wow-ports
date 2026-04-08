"""Tests for LibCompress decompression."""

import pytest
from azerite.lib_compress import decompress, LibCompressError


def describe_LibCompress():

    def describe_method_01_uncompressed():
        def it_passes_through_raw_bytes():
            wire = b'\x01hello'
            assert decompress(wire) == b'hello'

        def it_handles_empty_payload():
            wire = b'\x01'
            assert decompress(wire) == b''

    def describe_method_02_lzw():
        def it_decompresses_single_byte_codes():
            wire = bytes([0x02, 104, 101, 108, 108, 111])
            assert decompress(wire) == b'hello'

        def it_decompresses_with_dictionary_hits():
            # Codes: 65,66,256,258,66 → "ABABABAB"
            wire = bytes([0x02, 65, 66, 0xFE, 2, 2, 0xFE, 4, 2, 66])
            assert decompress(wire) == b'ABABABAB'

        def it_decompresses_single_char():
            wire = bytes([0x02, 65])
            assert decompress(wire) == b'A'

    def describe_method_03_huffman():
        def it_decompresses_a_minimal_huffman_stream():
            # 1 symbol ('A'=65), orig_size=3, code=0 (1-bit)
            wire = bytes([0x03, 0x00, 0x03, 0x00, 0x00, 0x41, 0x06])
            assert decompress(wire) == b'AAA'

    def describe_error_handling():
        def it_raises_on_empty_input():
            with pytest.raises(LibCompressError):
                decompress(b'')

        def it_raises_on_none_input():
            with pytest.raises(LibCompressError):
                decompress(None)

        def it_raises_on_unknown_method():
            with pytest.raises(LibCompressError, match="Unknown compression method"):
                decompress(b'\x05data')
