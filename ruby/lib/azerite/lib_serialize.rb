# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Azerite
  class LibSerialize
    extend T::Sig

    EMBEDDED_INDEX_SHIFT = T.let(2, Integer)
    EMBEDDED_COUNT_SHIFT = T.let(4, Integer)

    READER_INDEX = T.let({
      NIL: 0,

      NUM_16_POS: 1,
      NUM_16_NEG: 2,
      NUM_24_POS: 3,
      NUM_24_NEG: 4,
      NUM_32_POS: 5,
      NUM_32_NEG: 6,
      NUM_64_POS: 7,
      NUM_64_NEG: 8,
      NUM_FLOAT: 9,
      NUM_FLOATSTR_POS: 10,
      NUM_FLOATSTR_NEG: 11,

      BOOL_T: 12,
      BOOL_F: 13,

      STR_8: 14,
      STR_16: 15,
      STR_24: 16,

      TABLE_8: 17,
      TABLE_16: 18,
      TABLE_24: 19,

      ARRAY_8: 20,
      ARRAY_16: 21,
      ARRAY_24: 22,

      MIXED_8: 23,
      MIXED_16: 24,
      MIXED_24: 25,

      STRINGREF_8: 26,
      STRINGREF_16: 27,
      STRINGREF_24: 28,

      TABLEREF_8: 29,
      TABLEREF_16: 30,
      TABLEREF_24: 31
    }.freeze, T::Hash[Symbol, Integer])

    EMBEDDED_INDEX = T.let({
      STRING: 0,
      TABLE: 1,
      ARRAY: 2,
      MIXED: 3
    }.freeze, T::Hash[Symbol, Integer])

    NUMBER_INDICES = T.let([
      nil,
      nil,
      READER_INDEX[:NUM_16_POS],
      READER_INDEX[:NUM_24_POS],
      READER_INDEX[:NUM_32_POS],
      nil,
      nil,
      READER_INDEX[:NUM_64_POS]
    ].freeze, T::Array[T.nilable(Integer)])

    TYPE_INDICES = T.let({
      STRING: [
        nil,
        READER_INDEX[:STR_8],
        READER_INDEX[:STR_16],
        READER_INDEX[:STR_24]
      ],
      TABLE: [
        nil,
        READER_INDEX[:TABLE_8],
        READER_INDEX[:TABLE_16],
        READER_INDEX[:TABLE_24]
      ],
      ARRAY: [
        nil,
        READER_INDEX[:ARRAY_8],
        READER_INDEX[:ARRAY_16],
        READER_INDEX[:ARRAY_24]
      ],
      MIXED: [
        nil,
        READER_INDEX[:MIXED_8],
        READER_INDEX[:MIXED_16],
        READER_INDEX[:MIXED_24]
      ]
    }.freeze, T::Hash[Symbol, T::Array[T.nilable(Integer)]])

    STRING_REF_INDICES = T.let([
      nil,
      READER_INDEX[:STRINGREF_8],
      READER_INDEX[:STRINGREF_16],
      READER_INDEX[:STRINGREF_24]
    ].freeze, T::Array[T.nilable(Integer)])

    TABLE_REF_INDICES = T.let([
      nil,
      READER_INDEX[:TABLEREF_8],
      READER_INDEX[:TABLEREF_16],
      READER_INDEX[:TABLEREF_24]
    ].freeze, T::Array[T.nilable(Integer)])

    sig { params(value: Integer).returns(Integer) }
    def get_required_bytes(value)
      return 1 if value < 256
      return 2 if value < 65_536
      return 3 if value < 16_777_216

      raise 'Object limit exceeded'
    end

    sig { params(value: Integer).returns(Integer) }
    def get_required_bytes_number(value)
      return 1 if value < 256
      return 2 if value < 65_536
      return 3 if value < 16_777_216
      return 4 if value < 4_294_967_296

      7
    end
  end

  class LibSerializeDeserialize < LibSerialize
    extend T::Sig

    sig { params(data: String).void }
    def initialize(data)
      @data = T.let(data, String)
      @pos = T.let(0, Integer)
      @string_refs = T.let([], T::Array[String])
      @table_refs = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])
    end

    sig { params(data: String).returns(T.untyped) }
    def self.deserialize(data)
      new(data).deserialize
    end

    sig { returns(T.untyped) }
    def deserialize
      version = read_byte
      raise "Invalid LibSerialize data: bad version byte #{version}" unless version == 1

      read_object
    rescue StandardError => e
      raise "LibSerialize deserialization failed: #{e.message}"
    end

    sig { params(length: Integer).returns(String) }
    def read_bytes(length)
      bytes = T.must(@data[@pos, length])
      @pos += length
      bytes
    end

    sig { params(str: String).returns(Float) }
    def string_to_float(str)
      str.unpack1('G')
    end

    sig { params(str: String, required: Integer).returns(Integer) }
    def string_to_int(str, required)
      bytes = T.cast(str.unpack('C*'), T::Array[Integer])

      case required
      when 1
        T.must(bytes[0])
      when 2
        (T.must(bytes[0]) << 8) | T.must(bytes[1])
      when 3
        (T.must(bytes[0]) << 16) | (T.must(bytes[1]) << 8) | T.must(bytes[2])
      when 4
        (T.must(bytes[0]) << 24) | (T.must(bytes[1]) << 16) | (T.must(bytes[2]) << 8) | T.must(bytes[3])
      when 7
        (T.must(bytes[0]) << 48) | (T.must(bytes[1]) << 40) | (T.must(bytes[2]) << 32) |
          (T.must(bytes[3]) << 24) | (T.must(bytes[4]) << 16) | (T.must(bytes[5]) << 8) | T.must(bytes[6])
      else
        raise "Invalid required bytes: #{required}"
      end
    end

    sig { returns(T.untyped) }
    def read_object
      value = read_byte

      return (value - 1) / 2 if value.odd?

      if value % 4 == 2
        typ = (value - 2) / 4
        count = (typ - (typ % 4)) / 4
        typ %= 4
        return embedded_reader(typ, count)
      end

      if value % 8 == 4
        packed = (read_byte * 256) + value
        return value % 16 == 12 ? -(packed - 12) / 16 : (packed - 4) / 16
      end

      reader_table(value / 8)
    end

    sig { params(entry_count: Integer, value: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T::Hash[T.untyped, T.untyped]) }
    def read_table(entry_count, value = nil)
      is_new = value.nil?
      value ||= {}
      add_reference(@table_refs, value) if is_new

      entry_count.times do
        k, v = read_pair(method(:read_object))
        value[k] = v
      end

      value
    end

    sig { params(entry_count: Integer, value: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T::Hash[T.untyped, T.untyped]) }
    def read_array(entry_count, value = nil)
      is_new = value.nil?
      value ||= {}
      add_reference(@table_refs, value) if is_new

      entry_count.times do |i|
        value[i + 1] = read_object
      end

      value
    end

    sig { params(array_count: Integer, map_count: Integer).returns(T::Hash[T.untyped, T.untyped]) }
    def read_mixed(array_count, map_count)
      value = {}
      add_reference(@table_refs, value)

      # Inline array reading -- do NOT call read_array (it would add a spurious table ref)
      array_count.times do |i|
        value[i + 1] = read_object
      end

      read_table(map_count, value)

      value
    end

    sig { params(length: Integer).returns(String) }
    def read_string(length)
      value = read_bytes(length)
      add_reference(@string_refs, value) if length > 2
      value
    end

    sig { returns(Integer) }
    def read_byte
      read_int(1)
    end

    sig { params(required: Integer).returns(Integer) }
    def read_int(required)
      string_to_int(read_bytes(required), required)
    end

    sig { params(fn: Method, args: T.untyped).returns(T::Array[T.untyped]) }
    def read_pair(fn, *args)
      first = T.unsafe(fn).call(*args)
      second = T.unsafe(fn).call(*args)
      [first, second]
    end

    sig { params(type: Integer, count: Integer).returns(T.untyped) }
    def embedded_reader(type, count)
      case type
      when EMBEDDED_INDEX[:STRING]
        read_string(count)
      when EMBEDDED_INDEX[:TABLE]
        read_table(count)
      when EMBEDDED_INDEX[:ARRAY]
        read_array(count)
      when EMBEDDED_INDEX[:MIXED]
        read_mixed((count % 4) + 1, (count / 4).floor + 1)
      else
        raise "Unknown embedded type: #{type}"
      end
    end

    sig { params(type: Integer).returns(T.untyped) }
    def reader_table(type)
      case type
      when READER_INDEX[:NIL]
        nil
      when READER_INDEX[:NUM_16_POS]
        read_int(2)
      when READER_INDEX[:NUM_16_NEG]
        -read_int(2)
      when READER_INDEX[:NUM_24_POS]
        read_int(3)
      when READER_INDEX[:NUM_24_NEG]
        -read_int(3)
      when READER_INDEX[:NUM_32_POS]
        read_int(4)
      when READER_INDEX[:NUM_32_NEG]
        -read_int(4)
      when READER_INDEX[:NUM_64_POS]
        read_int(7)
      when READER_INDEX[:NUM_64_NEG]
        -read_int(7)
      when READER_INDEX[:NUM_FLOAT]
        string_to_float(read_bytes(8))
      when READER_INDEX[:NUM_FLOATSTR_POS]
        read_bytes(read_byte).to_f
      when READER_INDEX[:NUM_FLOATSTR_NEG]
        -read_bytes(read_byte).to_f
      when READER_INDEX[:BOOL_T]
        true
      when READER_INDEX[:BOOL_F]
        false
      when READER_INDEX[:STR_8]
        read_string(read_byte)
      when READER_INDEX[:STR_16]
        read_string(read_int(2))
      when READER_INDEX[:STR_24]
        read_string(read_int(3))
      when READER_INDEX[:TABLE_8]
        read_table(read_byte)
      when READER_INDEX[:TABLE_16]
        read_table(read_int(2))
      when READER_INDEX[:TABLE_24]
        read_table(read_int(3))
      when READER_INDEX[:ARRAY_8]
        read_array(read_byte)
      when READER_INDEX[:ARRAY_16]
        read_array(read_int(2))
      when READER_INDEX[:ARRAY_24]
        read_array(read_int(3))
      when READER_INDEX[:MIXED_8]
        read_mixed(*T.unsafe(read_pair(method(:read_byte))))
      when READER_INDEX[:MIXED_16]
        read_mixed(*T.unsafe(read_pair(method(:read_int), 2)))
      when READER_INDEX[:MIXED_24]
        read_mixed(*T.unsafe(read_pair(method(:read_int), 3)))
      when READER_INDEX[:STRINGREF_8]
        @string_refs[read_byte - 1]
      when READER_INDEX[:STRINGREF_16]
        @string_refs[read_int(2) - 1]
      when READER_INDEX[:STRINGREF_24]
        @string_refs[read_int(3) - 1]
      when READER_INDEX[:TABLEREF_8]
        @table_refs[read_byte - 1]
      when READER_INDEX[:TABLEREF_16]
        @table_refs[read_int(2) - 1]
      when READER_INDEX[:TABLEREF_24]
        @table_refs[read_int(3) - 1]
      else
        raise "Unknown type in reader table: #{type}"
      end
    end

    sig { params(refs: T::Array[T.untyped], value: T.untyped).void }
    def add_reference(refs, value)
      refs << value
    end
  end

  class LibSerializeSerialize < LibSerialize
    extend T::Sig

    sig { params(data: T.untyped).void }
    def initialize(data)
      @string_refs = T.let({}, T::Hash[String, Integer])
      @object_refs = T.let({}, T::Hash[Integer, Integer])
      @data = T.let(data, T.untyped)
      @buffer = T.let([], T::Array[String])
    end

    sig { params(data: T.untyped).returns(String) }
    def self.serialize(data)
      new(data).serialize
    end

    sig { params(byte: Integer).void }
    def write_byte(byte)
      @buffer << byte.chr
    end

    sig { params(string: String).void }
    def write_string(string)
      @buffer << string
    end

    alias write_bytes write_string

    sig { params(n: Integer, required: Integer).returns(String) }
    def int_to_string(n, required)
      case required
      when 1
        [n].pack('C')
      when 2
        [n].pack('n')
      when 3
        [(n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF].pack('C3')
      when 4
        [n].pack('N')
      when 7
        [
          (n >> 48) & 0xFF,
          (n >> 40) & 0xFF,
          (n >> 32) & 0xFF,
          (n >> 24) & 0xFF,
          (n >> 16) & 0xFF,
          (n >> 8) & 0xFF,
          n & 0xFF
        ].pack('C7')
      else
        raise "Invalid required bytes: #{required}"
      end
    end

    sig { params(n: Float).returns(String) }
    def float_to_string(n)
      [n].pack('G')
    end

    sig { returns(String) }
    def serialize
      write_int(1, 1)
      write_object(@data)
      @buffer.join
    end

    sig { params(object: T.untyped).void }
    def write_object(object)
      case object
      when String, Symbol
        serialize_string(object.to_s)
      when Numeric
        serialize_number(object)
      when true, false
        serialize_boolean(object)
      when nil
        serialize_nil
      when Array
        serialize_array(object)
      when Hash
        serialize_table(object)
      else
        raise "Unsupported type: #{object.class}"
      end
    end

    sig { void }
    def write_nil
      write_byte(T.must(READER_INDEX[:NIL]))
    end

    alias serialize_nil write_nil

    sig { params(num: Integer, required: Integer).void }
    def write_int(num, required)
      write_string(int_to_string(num, required))
    end

    sig { params(number: Numeric).void }
    def serialize_number(number)
      if number.is_a?(Float)
        serialize_float(number)
      elsif number > -4096 && number < 4096
        serialize_small_integer(T.cast(number, Integer))
      else
        serialize_large_integer(T.cast(number, Integer))
      end
    end

    sig { params(num: Float).void }
    def serialize_float(num)
      num_abs = num.abs
      as_string = num_abs.to_s
      if as_string.length < 7 && as_string.to_f == num_abs && num_abs.finite?
        sign = num.negative? ? 1 : 0
        write_byte((T.must(READER_INDEX[:NUM_FLOATSTR_POS]) + sign) << 3)
        write_byte(as_string.length)
        write_string(as_string)
      else
        write_byte(T.must(READER_INDEX[:NUM_FLOAT]) << 3)
        write_string([num].pack('G'))
      end
    end

    sig { params(num: Integer).void }
    def serialize_small_integer(num)
      if num >= 0 && num < 128
        write_byte((num * 2) + 1)
      else
        sign = num.negative? ? 8 : 0
        num = (num.abs * 16) + sign + 4
        upper = (num / 256).floor
        lower = num % 256
        write_byte(lower)
        write_byte(upper)
      end
    end

    sig { params(num: Integer).void }
    def serialize_large_integer(num)
      sign = num.negative? ? 1 : 0
      num = num.abs
      required_bytes = get_required_bytes_number(num)
      required_bytes = 2 if required_bytes == 1
      write_byte((T.must(NUMBER_INDICES[required_bytes]) + sign) << 3)
      write_int(num, required_bytes)
    end

    sig { params(bool: T::Boolean).void }
    def serialize_boolean(bool)
      write_byte((bool ? T.must(READER_INDEX[:BOOL_T]) : T.must(READER_INDEX[:BOOL_F])) << 3)
    end

    sig { params(str: String).void }
    def serialize_string(str)
      ref = @string_refs[str]
      if ref
        required_bytes = get_required_bytes(ref)
        ref_type = T.must(STRING_REF_INDICES[required_bytes])
        write_byte(ref_type << 3)
        write_int(ref, required_bytes)
      else
        len = str.bytesize
        write_type_with_count(:STRING, len)
        write_string(str)
        @string_refs[str] = @string_refs.count + 1 if len > 2
      end
    end

    sig { params(data: T::Array[T.untyped]).void }
    def serialize_array(data)
      ref = @object_refs[data.object_id]
      if ref
        required_bytes = get_required_bytes(ref)
        ref_type = T.must(TABLE_REF_INDICES[required_bytes])
        write_byte(ref_type << 3)
        write_int(ref, required_bytes)
      else
        len = data.length
        write_type_with_count(:ARRAY, len)
        data.each do |item|
          write_object(item)
        end
        @object_refs[data.object_id] = @object_refs.count + 1 if len > 2
      end
    end

    sig { params(data: T::Hash[T.untyped, T.untyped]).void }
    def serialize_table(data)
      ref = @object_refs[data.object_id]
      if ref
        required_bytes = get_required_bytes(ref)
        ref_type = T.must(TABLE_REF_INDICES[required_bytes])
        write_byte(ref_type << 3)
        write_int(ref, required_bytes)
      else
        keys = data.keys
        len = keys.length
        # Detect Lua-style array: sequential 1-based integer keys (int or string)
        if len.positive? && keys.each_with_index.all? do |k, i|
          (k.is_a?(Integer) && k == i + 1) || (k.is_a?(String) && k == (i + 1).to_s)
        end
          write_type_with_count(:ARRAY, len)
          keys.each { |k| write_object(data[k]) }
        else
          write_type_with_count(:TABLE, len)
          data.each do |key, value|
            write_object(key)
            write_object(value)
          end
        end
        @object_refs[data.object_id] = @object_refs.count + 1 if len > 2
      end
    end

    sig { params(type_name: Symbol, count: Integer).void }
    def write_type_with_count(type_name, count)
      if count < 16
        embedded_type = T.must(EMBEDDED_INDEX[type_name])
        write_byte((embedded_type << EMBEDDED_INDEX_SHIFT) | (count << EMBEDDED_COUNT_SHIFT) | 2)
      else
        required = get_required_bytes(count)
        type = T.must(T.must(TYPE_INDICES[type_name])[required])
        write_byte(type << 3)
        write_int(count, required)
      end
    end
  end
end
