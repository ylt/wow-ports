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
