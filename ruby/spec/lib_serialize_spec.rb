# frozen_string_literal: true

require_relative '../lib_serialize'

RSpec.describe 'LibSerialize' do
  def ser(obj)
    LibSerializeSerialize.serialize(obj)
  end

  def de(data)
    LibSerializeDeserialize.deserialize(data)
  end

  def roundtrip(obj)
    de(ser(obj))
  end

  describe 'serialize_nil (bug fix: write_object calls serialize_nil)' do
    it 'serializes nil without raising' do
      expect { ser(nil) }.not_to raise_error
    end

    it 'round-trips nil' do
      expect(roundtrip(nil)).to be_nil
    end
  end

  describe 'basic type round-trips' do
    it 'round-trips true' do
      expect(roundtrip(true)).to eq(true)
    end

    it 'round-trips false' do
      expect(roundtrip(false)).to eq(false)
    end

    it 'round-trips a small integer' do
      expect(roundtrip(42)).to eq(42)
    end

    it 'round-trips a negative integer' do
      expect(roundtrip(-99)).to eq(-99)
    end

    it 'round-trips a string' do
      expect(roundtrip('hello')).to eq('hello')
    end

    it 'round-trips a float' do
      expect(roundtrip(3.14)).to be_within(1e-10).of(3.14)
    end
  end

  describe 'array round-trips' do
    it 'round-trips an empty array' do
      expect(roundtrip([])).to eq([])
    end

    it 'round-trips a simple array' do
      expect(roundtrip([1, 2, 3])).to eq([1, 2, 3])
    end

    it 'round-trips an array with mixed types' do
      result = roundtrip([1, 'two', nil, true])
      expect(result[0]).to eq(1)
      expect(result[1]).to eq('two')
      expect(result[2]).to be_nil
      expect(result[3]).to eq(true)
    end
  end

  describe 'hash round-trips' do
    it 'round-trips an empty hash' do
      expect(roundtrip({})).to eq({})
    end

    it 'round-trips a simple hash' do
      result = roundtrip({ 'key' => 'value' })
      expect(result['key']).to eq('value')
    end
  end

  describe 'array ref tracking (bug fix: ARRAY_REF_INDICES → TABLE_REF_INDICES)' do
    it 'serializes an array with >2 elements without raising' do
      # Use values < 128 to avoid pre-existing NUMBER_INDICES[1] bug for 128-255
      arr = [1, 2, 3]
      expect { ser(arr) }.not_to raise_error
    end

    it 'round-trips array with more than 2 elements' do
      expect(roundtrip([10, 20, 30])).to eq([10, 20, 30])
    end
  end

  describe 'hash ref tracking (bug fix: HASH_REF_INDICES → TABLE_REF_INDICES)' do
    it 'serializes a hash with >2 keys without raising' do
      h = { 'a' => 1, 'b' => 2, 'c' => 3 }
      expect { ser(h) }.not_to raise_error
    end

    it 'round-trips hash with more than 2 keys' do
      h = { 'a' => 1, 'b' => 2, 'c' => 3 }
      result = roundtrip(h)
      expect(result['a']).to eq(1)
      expect(result['b']).to eq(2)
      expect(result['c']).to eq(3)
    end
  end

  describe 'mixed table deserialization (bug fix: 0-based → 1-based indexing)' do
    it 'deserializes array portion of mixed table with 1-based keys' do
      # Use values < 128 to avoid pre-existing NUMBER_INDICES[1] bug for 128-255
      result = roundtrip([10, 20, 30])
      expect(result).to eq([10, 20, 30])
    end
  end
end
