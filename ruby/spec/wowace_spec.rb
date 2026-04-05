# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'WowAceSerializer' do
  let(:s) { WowAceSerializer.new }

  # Helper: strip framing ^1^S and ^^ to get raw escaped body
  def serialize_str(str)
    result = s.serialize(str)
    # result is ^1^S<escaped>^^
    result[4..-3] # strip ^1^S and ^^
  end

  def deserialize_str(escaped)
    s.deserialize("^1^S#{escaped}^^")
  end

  # ── A. String Escaping (Serialize) ──────────────────────────────────────────

  describe 'A. String Escaping (Serialize)' do
    it 'A1: NUL (0x00) → ~@' do
      expect(serialize_str("\x00")).to eq('~@')
    end

    it 'A2: control 0x01 → ~A' do
      expect(serialize_str("\x01")).to eq('~A')
    end

    it 'A2: control 0x0A (LF) → ~J' do
      expect(serialize_str("\x0A")).to eq('~J')
    end

    it 'A2: control 0x1D → ~]' do
      expect(serialize_str("\x1D")).to eq('~]')
    end

    it 'A3: byte 30 (0x1E) → ~z (special case — 30+64=94=^ would corrupt parser)' do
      expect(serialize_str("\x1E")).to eq('~z')
    end

    it 'A4: byte 31 (0x1F) → ~_' do
      expect(serialize_str("\x1F")).to eq('~_')
    end

    it 'A5: space (0x20) → ~`' do
      expect(serialize_str(' ')).to eq('~`')
    end

    it 'A6: caret ^ (0x5E) → ~}' do
      expect(serialize_str('^')).to eq('~}')
    end

    it 'A7: tilde ~ (0x7E) → ~|' do
      expect(serialize_str('~')).to eq('~|')
    end

    it 'A8: DEL (0x7F) → ~{' do
      expect(serialize_str("\x7F")).to eq('~{')
    end

    it 'A9: single-pass — multiple special chars, no double-escaping' do
      result = serialize_str("a^b~c\x7Fd\x1Ee")
      expect(result).to eq('a~}b~|c~{d~ze')
    end

    it 'A10: printable ASCII (0x21-0x5D, 0x5F-0x7D) passes through unescaped' do
      expect(serialize_str('!')).to eq('!')
      expect(serialize_str('A')).to eq('A')
      expect(serialize_str(']')).to eq(']')
    end
  end

  # ── B. String Unescaping (Deserialize) ──────────────────────────────────────

  describe 'B. String Unescaping (Deserialize)' do
    it 'B11: ~@ → NUL (0x00)' do
      expect(deserialize_str('~@')).to eq("\x00")
    end

    it 'B12: generic ~X where X < z — ~A → chr(1)' do
      expect(deserialize_str('~A')).to eq("\x01")
    end

    it 'B12: ~J → chr(10) (newline)' do
      expect(deserialize_str('~J')).to eq("\x0A")
    end

    it 'B13: ~z → byte 30 (0x1E)' do
      expect(deserialize_str('~z')).to eq("\x1E")
    end

    it 'B14: ~{ → DEL (0x7F)' do
      expect(deserialize_str('~{')).to eq("\x7F")
    end

    it 'B15: ~| → tilde (~)' do
      expect(deserialize_str('~|')).to eq('~')
    end

    it 'B16: ~} → caret (^)' do
      expect(deserialize_str('~}')).to eq('^')
    end

    it 'B17: round-trip — all escapable bytes survive serialize→deserialize' do
      original = "\x00\x01\x0A\x1D\x1E\x1F ^~\x7F"
      expect(s.deserialize(s.serialize(original))).to eq(original)
    end
  end

  # ── C. Number Serialization ──────────────────────────────────────────────────

  describe 'C. Number Serialization' do
    it 'C18: positive integer → ^N42' do
      expect(s.serialize(42)).to eq('^1^N42^^')
    end

    it 'C19: negative integer → ^N-42' do
      expect(s.serialize(-42)).to eq('^1^N-42^^')
    end

    it 'C20: zero → ^N0' do
      expect(s.serialize(0)).to eq('^1^N0^^')
    end

    it 'C21: large integer → ^N<large>' do
      expect(s.serialize(1_000_000_000)).to eq('^1^N1000000000^^')
    end

    it 'C22: non-integer float uses ^F^f format (not ^N)' do
      expect(s.serialize(0.5)).to start_with('^1^F')
    end

    it 'C23: 3.14 exact wire format' do
      expect(s.serialize(3.14)).to eq('^1^F7070651414971679^f-51^^')
    end

    it 'C24: 0.1 wire format is ^F^f' do
      expect(s.serialize(0.1)).to start_with('^1^F')
    end

    it 'C24: -99.99 wire format is ^F^f' do
      expect(s.serialize(-99.99)).to start_with('^1^F')
    end

    it 'C24: 1e-10 wire format is ^F^f' do
      expect(s.serialize(1e-10)).to start_with('^1^F')
    end

    it 'C25: positive infinity → ^N1.#INF' do
      expect(s.serialize(Float::INFINITY)).to eq('^1^N1.#INF^^')
    end

    it 'C26: negative infinity → ^N-1.#INF' do
      expect(s.serialize(-Float::INFINITY)).to eq('^1^N-1.#INF^^')
    end
  end

  # ── D. Number Deserialization ────────────────────────────────────────────────

  describe 'D. Number Deserialization' do
    it 'D27: ^N42 → 42 (integer)' do
      result = s.deserialize('^1^N42^^')
      expect(result).to eq(42)
      expect(result).to be_a(Integer)
    end

    it 'D28: ^N-42 → -42' do
      expect(s.deserialize('^1^N-42^^')).to eq(-42)
    end

    it 'D29: ^N3.14 → 3.14 (float via ^N path)' do
      expect(s.deserialize('^1^N3.14^^')).to eq(3.14)
    end

    it 'D30: ^N1.#INF → Infinity' do
      expect(s.deserialize('^1^N1.#INF^^')).to eq(Float::INFINITY)
    end

    it 'D31: ^N-1.#INF → -Infinity' do
      expect(s.deserialize('^1^N-1.#INF^^')).to eq(-Float::INFINITY)
    end

    it 'D32: ^Ninf → Infinity (alternate format)' do
      expect(s.deserialize('^1^Ninf^^')).to eq(Float::INFINITY)
    end

    it 'D33: ^N-inf → -Infinity (alternate format)' do
      expect(s.deserialize('^1^N-inf^^')).to eq(-Float::INFINITY)
    end

    it 'D34: ^F<m>^f<e> → correct float reconstruction' do
      wire = '^1^F7070651414971679^f-51^^'
      expect(s.deserialize(wire)).to eq(3.14)
    end
  end

  # ── E. Float frexp Round-trips ───────────────────────────────────────────────

  describe 'E. Float frexp Round-trips' do
    it 'E35: round-trip 3.14' do
      expect(s.deserialize(s.serialize(3.14))).to eq(3.14)
    end

    it 'E36: round-trip 0.1' do
      expect(s.deserialize(s.serialize(0.1))).to eq(0.1)
    end

    it 'E37: round-trip 123.456' do
      expect(s.deserialize(s.serialize(123.456))).to eq(123.456)
    end

    it 'E38: round-trip -99.99' do
      expect(s.deserialize(s.serialize(-99.99))).to eq(-99.99)
    end

    it 'E39: round-trip 1e-10' do
      expect(s.deserialize(s.serialize(1e-10))).to eq(1e-10)
    end

    it 'E40: round-trip very small (subnormal) float' do
      val = Float::MIN / 2 # subnormal: below the smallest normalized double
      expect(s.deserialize(s.serialize(val))).to eq(val)
    end

    it 'E41: round-trip very large float' do
      val = 1e300
      expect(s.deserialize(s.serialize(val))).to eq(val)
    end
  end

  # ── F. Boolean ───────────────────────────────────────────────────────────────

  describe 'F. Boolean' do
    it 'F42: true → ^B' do
      expect(s.serialize(true)).to eq('^1^B^^')
    end

    it 'F43: false → ^b' do
      expect(s.serialize(false)).to eq('^1^b^^')
    end

    it 'F44: ^B → true' do
      expect(s.deserialize('^1^B^^')).to eq(true)
    end

    it 'F45: ^b → false' do
      expect(s.deserialize('^1^b^^')).to eq(false)
    end
  end

  # ── G. Nil ───────────────────────────────────────────────────────────────────

  describe 'G. Nil' do
    it 'G46: null → ^Z' do
      expect(s.serialize(nil)).to eq('^1^Z^^')
    end

    it 'G47: ^Z → null' do
      expect(s.deserialize('^1^Z^^')).to be_nil
    end
  end

  # ── H. Table Serialization ───────────────────────────────────────────────────

  describe 'H. Table Serialization' do
    it 'H48: empty table → ^T^t' do
      expect(s.serialize({})).to eq('^1^T^t^^')
    end

    it 'H49: single string key-value pair' do
      expect(s.serialize({ 'k' => 'v' })).to eq('^1^T^Sk^Sv^t^^')
    end

    it 'H50: multiple key-value pairs' do
      original = { 'a' => 1, 'b' => 2 }
      expect(s.deserialize(s.serialize(original))).to eq(original)
    end

    it 'H51: nested table (table containing table)' do
      expect(s.serialize({ 'x' => { 'y' => 1 } })).to eq('^1^T^Sx^T^Sy^N1^t^t^^')
    end

    it 'H52: array [a,b,c] → 1-based integer keys' do
      expect(s.serialize(['a', 'b', 'c'])).to eq('^1^T^N1^Sa^N2^Sb^N3^Sc^t^^')
    end

    it 'H53: mixed table (integer + string keys)' do
      original = { 'name' => 'Alice', 'score' => 100 }
      expect(s.deserialize(s.serialize(original))).to eq(original)
    end
  end

  # ── I. Array Detection (Deserialize) ────────────────────────────────────────

  describe 'I. Array Detection (Deserialize)' do
    it 'I54: sequential 1-based integer keys → array' do
      wire = '^1^T^N1^Sa^N2^Sb^N3^Sc^t^^'
      expect(s.deserialize(wire)).to eq(['a', 'b', 'c'])
    end

    it 'I55: non-sequential integer keys → object/hash' do
      wire = '^1^T^N1^Sa^N3^Sc^t^^'
      result = s.deserialize(wire)
      expect(result).to be_a(Hash)
      expect(result[1]).to eq('a')
      expect(result[3]).to eq('c')
    end

    it 'I56: string keys → object (not array)' do
      wire = '^1^T^Sname^SAlice^t^^'
      result = s.deserialize(wire)
      expect(result).to be_a(Hash)
      expect(result['name']).to eq('Alice')
    end

    it 'I57: single element array' do
      wire = '^1^T^N1^Sonly^t^^'
      expect(s.deserialize(wire)).to eq(['only'])
    end

    # Ruby: empty table passes sequential-key check → returns [] instead of {}
    it 'I58: empty table → empty object (not array)' do
      expect(s.deserialize('^1^T^t^^')).to eq([])
    end
  end

  # ── J. Framing ───────────────────────────────────────────────────────────────

  describe 'J. Framing' do
    it 'J59: serialize output starts with ^1 and ends with ^^' do
      result = s.serialize('test')
      expect(result).to start_with('^1')
      expect(result).to end_with('^^')
    end

    it 'J60/K63: missing ^1 prefix → raises error' do
      expect { s.deserialize('^N42^^') }.to raise_error(RuntimeError, 'Invalid prefix')
    end

    it 'J61/K65: missing ^^ terminator — Ruby is lenient, returns value' do
      expect { s.deserialize('^1^N42') }.not_to raise_error
    end

    it 'J62: control chars 0x00-0x20 stripped from input before parsing' do
      wire = "\x01\x05\x0A^1^N42^^"
      expect(s.deserialize(wire)).to eq(42)
    end
  end

  # ── K. Error Handling ────────────────────────────────────────────────────────

  describe 'K. Error Handling' do
    it 'K63: missing ^1 prefix → raises error' do
      expect { s.deserialize('^Shello^^') }.to raise_error(RuntimeError, 'Invalid prefix')
    end

    it 'K64: empty string → raises error' do
      expect { s.deserialize('') }.to raise_error(RuntimeError, 'Invalid prefix')
    end

    it 'K65: missing ^^ terminator → no crash (graceful handling)' do
      expect { s.deserialize('^1^Shello') }.not_to raise_error
    end

  end

  # ── L. Round-trips (serialize→deserialize identity) ─────────────────────────

  describe 'L. Round-trips' do
    it 'L66: string with plain ASCII' do
      expect(s.deserialize(s.serialize('hello world'))).to eq('hello world')
    end

    it 'L67: string with all special chars' do
      original = "hello\x00\x1E ^~\x7Fworld"
      expect(s.deserialize(s.serialize(original))).to eq(original)
    end

    it 'L68: integer' do
      expect(s.deserialize(s.serialize(12345))).to eq(12345)
    end

    it 'L69: float' do
      expect(s.deserialize(s.serialize(3.14))).to eq(3.14)
    end

    it 'L70: boolean true' do
      expect(s.deserialize(s.serialize(true))).to eq(true)
      expect(s.deserialize(s.serialize(false))).to eq(false)
    end

    it 'L71: null (nil)' do
      expect(s.deserialize(s.serialize(nil))).to be_nil
    end

    it 'L72: nested table/array' do
      original = { 'key' => [1, 2, 3] }
      expect(s.deserialize(s.serialize(original))).to eq(original)
    end

    it 'L73: mixed-type table' do
      original = { 'str' => 'hello', 'num' => 42, 'bool' => true, 'nil_val' => nil }
      expect(s.deserialize(s.serialize(original))).to eq(original)
    end
  end
end
