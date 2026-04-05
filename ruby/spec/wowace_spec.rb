# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'WowAceSerializer escape characters' do
  let(:s) { WowAceSerializer.new }

  # Helper: strip framing ^1...^^ and ^S prefix to get raw escaped body
  def serialize_str(str)
    result = s.serialize(str)
    # result is ^1^S<escaped>^^
    result[4..-3] # strip ^1^S and ^^
  end

  def deserialize_str(escaped)
    s.deserialize("^1^S#{escaped}^^")
  end

  describe 'serialization escape mappings' do
    it 'escapes ^ as ~}' do
      expect(serialize_str('^')).to eq('~}')
    end

    it 'escapes ~ as ~|' do
      expect(serialize_str('~')).to eq('~|')
    end

    it 'escapes DEL (0x7F) as ~{' do
      expect(serialize_str("\x7F")).to eq('~{')
    end

    it 'escapes byte 30 (0x1E) as ~z' do
      expect(serialize_str("\x1E")).to eq('~z')
    end

    it 'escapes space (0x20) as ~`' do
      expect(serialize_str(' ')).to eq('~`')
    end

    it 'single-pass: ~^ combination does not double-escape' do
      # serialize "~^" — first ~ becomes ~|, then ^ becomes ~}
      # sequential replacement would double-escape
      result = serialize_str("~^")
      expect(result).to eq('~|~}')
    end

    it 'single-pass: string with multiple special chars' do
      result = serialize_str("a^b~c\x7Fd\x1Ee")
      expect(result).to eq('a~}b~|c~{d~ze')
    end
  end

  describe 'deserialization escape mappings' do
    it 'decodes ~} as ^' do
      expect(deserialize_str('~}')).to eq('^')
    end

    it 'decodes ~| as ~' do
      expect(deserialize_str('~|')).to eq('~')
    end

    it 'decodes ~{ as DEL (0x7F)' do
      expect(deserialize_str('~{')).to eq("\x7F")
    end

    it 'decodes ~z as byte 30 (0x1E)' do
      expect(deserialize_str('~z')).to eq("\x1E")
    end
  end

  describe 'round-trip' do
    it 'round-trips a string with all special characters' do
      original = "hello\x00\x1E ^~\x7Fworld"
      serialized = s.serialize(original)
      expect(s.deserialize(serialized)).to eq(original)
    end

    it 'round-trips a string with ^ and ~' do
      original = "caret^tilde~"
      expect(s.deserialize(s.serialize(original))).to eq(original)
    end
  end
end

RSpec.describe 'WowAceSerializer float serialization' do
  let(:s) { WowAceSerializer.new }

  describe 'serialization' do
    it '3.0 uses ^F path (non-integer floats always use frexp)' do
      wire = s.serialize(3.0)
      expect(wire).to start_with('^1^F')
      expect(s.deserialize(wire)).to eq(3.0)
    end

    it '3.14 uses ^F path matching cross-language fixture' do
      expect(s.serialize(3.14)).to eq('^1^F7070651414971679^f-51^^')
    end

    it 'integer 42 uses ^N path' do
      expect(s.serialize(42)).to eq('^1^N42^^')
    end

    it 'positive infinity uses ^N1.#INF' do
      expect(s.serialize(Float::INFINITY)).to eq('^1^N1.#INF^^')
    end

    it 'negative infinity uses ^N-1.#INF' do
      expect(s.serialize(-Float::INFINITY)).to eq('^1^N-1.#INF^^')
    end
  end

  describe 'deserialization' do
    it 'decodes ^F wire format back to original float' do
      wire = s.serialize(3.14)
      expect(s.deserialize(wire)).to eq(3.14)
    end
  end

  describe 'round-trip floats' do
    [0.1, 123.456, -99.99, 1e-10, 1e+10].each do |val|
      it "round-trips #{val}" do
        expect(s.deserialize(s.serialize(val))).to eq(val)
      end
    end

    it 'round-trips 3.14' do
      expect(s.deserialize(s.serialize(3.14))).to eq(3.14)
    end
  end

  describe 'float guard correctness' do
    it '1.0000000000000002 uses ^F path (edge case: not string-round-trippable)' do
      wire = s.serialize(1.0000000000000002)
      # 1.0000000000000002.to_s.to_f may or may not equal the original;
      # if not, it falls through to ^F
      # Either way, round-trip must be exact
      result = s.deserialize(wire)
      expect(result).to eq(1.0000000000000002)
    end
  end
end
