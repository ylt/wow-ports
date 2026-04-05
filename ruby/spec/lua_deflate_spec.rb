# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lua_deflate'
require_relative '../lua_deflate_native'

RSpec.describe 'LuaDeflate' do

  # ── M. Encode ────────────────────────────────────────────────────────────────

  describe 'M. Encode' do
    it 'M74: 3-byte input → 4 encoded chars (full group)' do
      expect(LuaDeflate.encode_for_print('abc').length).to eq(4)
    end

    it 'M75: 1-byte input → 2 encoded chars (tail)' do
      expect(LuaDeflate.encode_for_print('a').length).to eq(2)
    end

    it 'M76: 2-byte input → 3 encoded chars (tail)' do
      expect(LuaDeflate.encode_for_print('ab').length).to eq(3)
    end

    it 'M77: 6-byte input → 8 encoded chars (two full groups)' do
      expect(LuaDeflate.encode_for_print('abcdef').length).to eq(8)
    end

    it 'M78: empty input → empty string' do
      expect(LuaDeflate.encode_for_print('')).to eq('')
    end

    it 'M79: output uses only alphabet chars a-zA-Z0-9()' do
      encoded = LuaDeflate.encode_for_print('hello world test data here!!')
      expect(encoded).to match(/\A[a-zA-Z0-9()]+\z/)
    end
  end

  # ── N. Decode ────────────────────────────────────────────────────────────────

  describe 'N. Decode' do
    it 'N80: 4-char input → 3 bytes (full group)' do
      encoded = LuaDeflate.encode_for_print('abc')
      expect(encoded.length).to eq(4)
      expect(LuaDeflate.decode_for_print(encoded).bytesize).to eq(3)
    end

    it 'N81: 2-char input → 1 byte (tail)' do
      encoded = LuaDeflate.encode_for_print('a')
      expect(encoded.length).to eq(2)
      expect(LuaDeflate.decode_for_print(encoded).bytesize).to eq(1)
    end

    it 'N82: 3-char input → 2 bytes (tail)' do
      encoded = LuaDeflate.encode_for_print('ab')
      expect(encoded.length).to eq(3)
      expect(LuaDeflate.decode_for_print(encoded).bytesize).to eq(2)
    end

    it 'N83: whitespace stripped from start/end before decode' do
      encoded = LuaDeflate.encode_for_print('hi')
      expect(LuaDeflate.decode_for_print("  #{encoded}\n")).to eq('hi')
    end

    it 'N84: length-1 input → nil' do
      expect(LuaDeflate.decode_for_print('a')).to be_nil
    end

    it 'N85: empty string → nil (strlen ≤ 1 after whitespace strip)' do
      expect(LuaDeflate.decode_for_print('')).to be_nil
    end

    it 'N86: invalid alphabet character → nil' do
      expect(LuaDeflate.decode_for_print('ab+c')).to be_nil
    end
  end

  # ── O. Round-trips ───────────────────────────────────────────────────────────

  describe 'O. Round-trips' do
    it 'O87: simple ASCII string' do
      expect(LuaDeflate.decode_for_print(LuaDeflate.encode_for_print('hello'))).to eq('hello')
    end

    it 'O88: binary data — bytes 0-127 round-trip correctly' do
      # Note: LuaDeflate.decode_for_print uses .chr without encoding argument,
      # which raises for bytes > 127. We test the safe 0-127 range.
      all_low_bytes = (0..127).map(&:chr).join
      encoded = LuaDeflate.encode_for_print(all_low_bytes)
      expect(LuaDeflate.decode_for_print(encoded)).to eq(all_low_bytes)
    end

    it 'O89: large payload (1000+ bytes) round-trips' do
      input = 'abcdefghij' * 120
      expect(LuaDeflate.decode_for_print(LuaDeflate.encode_for_print(input))).to eq(input)
    end

    it 'O90: single byte round-trips' do
      expect(LuaDeflate.decode_for_print(LuaDeflate.encode_for_print('x'))).to eq('x')
    end

    it 'O91: two bytes round-trip' do
      expect(LuaDeflate.decode_for_print(LuaDeflate.encode_for_print('xy'))).to eq('xy')
    end

    it 'O92: three bytes round-trip (group boundary)' do
      expect(LuaDeflate.decode_for_print(LuaDeflate.encode_for_print('xyz'))).to eq('xyz')
    end

    it 'O93: null bytes (0x00) round-trip correctly' do
      input = "\x00\x00\x00"
      expect(LuaDeflate.decode_for_print(LuaDeflate.encode_for_print(input))).to eq(input)
    end
  end

  # ── P. Native Variant ────────────────────────────────────────────────────────

  describe 'P. Native Variant (LuaDeflateNative)' do
    it 'P94: native encode output byte-identical to reference encode' do
      inputs = ['hello', 'abc', 'The quick brown fox', 'x' * 99]
      inputs.each do |input|
        expect(LuaDeflateNative.encode_for_print(input)).to eq(LuaDeflate.encode_for_print(input)),
          "Mismatch for input: #{input[0, 20].inspect}"
      end
    end

    it 'P95: native decode output byte-identical to reference decode' do
      input = 'round trip test string 123'
      encoded = LuaDeflate.encode_for_print(input)
      expect(LuaDeflateNative.decode_for_print(encoded)).to eq(LuaDeflate.decode_for_print(encoded))
    end

    it 'P96: native round-trip' do
      input = 'native round-trip test'
      encoded = LuaDeflateNative.encode_for_print(input)
      expect(LuaDeflateNative.decode_for_print(encoded)).to eq(input)
    end
  end
end
