# frozen_string_literal: true

require 'spec_helper'
require_relative '../lua_deflate'
require 'json'

FIXTURES = JSON.parse(
  File.read(File.join(__dir__, '../../testdata/fixtures.json'))
).freeze

# Convert a fixture input (which may contain __type__ wrappers) to a native Ruby value.
def to_native(v)
  case v
  when Array then v.map { |el| to_native(el) }
  when Hash
    case v['__type__']
    when 'infinity'     then Float::INFINITY
    when 'neg_infinity' then -Float::INFINITY
    when 'float'        then v['value']
    when 'bytes'        then [v['hex']].pack('H*').force_encoding(Encoding::BINARY)
    else v.transform_values { |val| to_native(val) }
    end
  else v # nil, true, false, Integer, Float, String pass through
  end
end

# ── AceSerializer fixtures ─────────────────────────────────────────────────

RSpec.describe 'AceSerializer fixture tests' do
  let(:s) { WowAceSerializer.new }

  describe 'deserialize' do
    FIXTURES['ace_serializer'].each do |fixture|
      it fixture['name'] do
        result = s.deserialize(fixture['ace_serialized'])
        expect(result).to eq(to_native(fixture['input']))
      end
    end
  end

  describe 'serialize' do
    # Skip fixtures with serialize_deterministic: false (non-deterministic key order)
    FIXTURES['ace_serializer'].reject { |f| f['serialize_deterministic'] == false }.each do |fixture|
      it fixture['name'] do
        result = s.serialize(to_native(fixture['input']))
        expect(result).to eq(fixture['ace_serialized'])
      end
    end
  end

  describe 'round-trip' do
    # deserialize(wire) -> value1 -> serialize -> deserialize -> value2
    # Assert value2 equals value1 (internal consistency).
    FIXTURES['ace_serializer'].each do |fixture|
      it fixture['name'] do
        value1 = s.deserialize(fixture['ace_serialized'])
        wire2 = s.serialize(value1)
        value2 = s.deserialize(wire2)
        expect(value2).to eq(value1)
      end
    end
  end
end

# ── LuaDeflate fixtures ────────────────────────────────────────────────────

RSpec.describe 'LuaDeflate fixture tests' do
  describe 'encode' do
    FIXTURES['lua_deflate'].each do |fixture|
      it fixture['name'] do
        input = [fixture['input_hex']].pack('H*')
        expect(LuaDeflate.encode_for_print(input)).to eq(fixture['encoded'])
      end
    end
  end

  describe 'decode' do
    FIXTURES['lua_deflate'].each do |fixture|
      it fixture['name'] do
        decoded = LuaDeflate.decode_for_print(fixture['encoded'])
        expect(decoded.unpack1('H*')).to eq(fixture['input_hex'])
      end
    end
  end
end
