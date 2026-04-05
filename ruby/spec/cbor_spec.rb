# frozen_string_literal: true

require_relative '../wow_cbor'
require_relative '../pipeline'

RSpec.describe 'WowCbor' do
  # ── encode/decode round-trip ───────────────────────────────────────────────

  describe 'encode→decode round-trip' do
    it 'string value' do
      expect(WowCbor.decode(WowCbor.encode('hello'))).to eq('hello')
    end

    it 'integer value' do
      expect(WowCbor.decode(WowCbor.encode(42))).to eq(42)
    end

    it 'boolean true' do
      expect(WowCbor.decode(WowCbor.encode(true))).to eq(true)
    end

    it 'nil value' do
      expect(WowCbor.decode(WowCbor.encode(nil))).to be_nil
    end

    it 'hash with string keys' do
      data = { 'key' => 'value', 'num' => 7 }
      result = WowCbor.decode(WowCbor.encode(data))
      expect(result['key']).to eq('value')
      expect(result['num']).to eq(7)
    end

    it 'array' do
      data = ['a', 'b', 'c']
      expect(WowCbor.decode(WowCbor.encode(data))).to eq(data)
    end
  end

  # ── byte string conversion ─────────────────────────────────────────────────

  describe 'byte string → UTF-8 conversion' do
    it 'binary string is decoded to UTF-8' do
      # Build CBOR byte string for "hello": 0x45 (type 2, len 5) + bytes
      cbor = "\x45hello"
      result = WowCbor.decode(cbor)
      expect(result).to eq('hello')
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it 'nested binary string in hash is converted' do
      inner = +'world'  # +str creates a mutable copy
      inner.force_encoding(Encoding::BINARY)
      data = { 'key' => inner }
      encoded = WowCbor.encode(data)
      result = WowCbor.decode(encoded)
      expect(result['key']).to eq('world')
    end
  end

  # ── array detection ────────────────────────────────────────────────────────

  describe 'array detection' do
    it 'sequential 1-based integer-keyed hash → array' do
      data = { 1 => 'a', 2 => 'b', 3 => 'c' }
      encoded = WowCbor.encode(data)
      result = WowCbor.decode(encoded)
      expect(result).to eq(['a', 'b', 'c'])
    end

    it 'non-sequential int keys stay as hash' do
      data = { 1 => 'a', 3 => 'c' }
      encoded = WowCbor.encode(data)
      result = WowCbor.decode(encoded)
      expect(result).to be_a(Hash)
      expect(result).not_to be_a(Array)
    end

    it 'string-keyed hash stays as hash' do
      data = { 'a' => 1, 'b' => 2 }
      result = WowCbor.decode(WowCbor.encode(data))
      expect(result).to be_a(Hash)
      expect(result['a']).to eq(1)
    end
  end
end

RSpec.describe 'Pipeline Plater v2' do
  it 'encodes with !PLATER:2! prefix' do
    enc = Pipeline.encode(ExportResult.new('plater', 2, { 'x' => 1 }, nil))
    expect(enc).to start_with('!PLATER:2!')
  end

  it 'decodes !PLATER:2! → plater v2' do
    enc = Pipeline.encode(ExportResult.new('plater', 2, { 'x' => 1 }, nil))
    dec = Pipeline.decode(enc)
    expect(dec.addon).to eq('plater')
    expect(dec.version).to eq(2)
  end

  it 'Plater v2 round-trip preserves data' do
    data = { 'profile' => 'Default', 'enabled' => true, 'level' => 5 }
    enc = Pipeline.encode(ExportResult.new('plater', 2, data, nil))
    dec = Pipeline.decode(enc)
    expect(dec.data['profile']).to eq('Default')
    expect(dec.data['enabled']).to eq(true)
    expect(dec.data['level']).to eq(5)
  end

  it '!PLATER:2! is detected before ! catch-all' do
    enc = Pipeline.encode(ExportResult.new('plater', 2, 'test', nil))
    expect(enc).to start_with('!PLATER:2!')
    dec = Pipeline.decode(enc)
    expect(dec.addon).to eq('plater')
    expect(dec.version).to eq(2)
  end
end
