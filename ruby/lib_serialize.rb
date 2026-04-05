# frozen_string_literal: true

class LibSerialize
  EMBEDDED_INDEX_SHIFT = 2
  EMBEDDED_COUNT_SHIFT = 4

  READER_INDEX = {
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
    TABLEREF_24: 31,
  }.freeze

  EMBEDDED_INDEX = {
    STRING: 0,
    TABLE: 1,
    ARRAY: 2,
    MIXED: 3,
  }.freeze

  NUMBER_INDICES = [
    nil,
    nil,
    READER_INDEX[:NUM_16_POS],
    READER_INDEX[:NUM_24_POS],
    READER_INDEX[:NUM_32_POS],
    nil,
    nil,
    READER_INDEX[:NUM_64_POS],
  ].freeze

  TYPE_INDICES = {
    STRING: [
      nil,
      READER_INDEX[:STR_8],
      READER_INDEX[:STR_16],
      READER_INDEX[:STR_24],
    ],
    TABLE: [
      nil,
      READER_INDEX[:TABLE_8],
      READER_INDEX[:TABLE_16],
      READER_INDEX[:TABLE_24],
    ],
    ARRAY: [
      nil,
      READER_INDEX[:ARRAY_8],
      READER_INDEX[:ARRAY_16],
      READER_INDEX[:ARRAY_24],
    ],
    MIXED: [
      nil,
      READER_INDEX[:MIXED_8],
      READER_INDEX[:MIXED_16],
      READER_INDEX[:MIXED_24],
    ],
  }.freeze

  STRING_REF_INDICES = [
    nil,
    READER_INDEX[:STRINGREF_8],
    READER_INDEX[:STRINGREF_16],
    READER_INDEX[:STRINGREF_24],
  ].freeze

  TABLE_REF_INDICES = [
    nil,
    READER_INDEX[:TABLEREF_8],
    READER_INDEX[:TABLEREF_16],
    READER_INDEX[:TABLEREF_24],
  ].freeze

  def get_required_bytes(value)
    return 1 if value < 256
    return 2 if value < 65536
    return 3 if value < 16777216

    raise "Object limit exceeded"
  end

  def get_required_bytes_number(value)
    return 1 if value < 256
    return 2 if value < 65536
    return 3 if value < 16777216
    return 4 if value < 4294967296

    7
  end
end

class LibSerializeDeserialize < LibSerialize
  def initialize(data)
    @data = data
    @pos = 0
    @string_refs = []
    @table_refs = []
  end

  def self.deserialize(data)
    new(data).deserialize
  end

  def deserialize
    version = read_byte
    raise "Invalid LibSerialize data: bad version byte #{version}" unless version == 1
    read_object
  rescue => e
    raise "LibSerialize deserialization failed: #{e.message}"
  end

  def read_bytes(length)
    bytes = @data[@pos, length]
    @pos += length
    bytes
  end

  def string_to_float(str)
    str.unpack1('G')
  end

  def string_to_int(str, required)
    bytes = str.unpack('C*')

    case required
    when 1
      bytes[0]
    when 2
      bytes[0] << 8 | bytes[1]
    when 3
      bytes[0] << 16 | bytes[1] << 8 | bytes[2]
    when 4
      bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
    when 7
      bytes[0] << 48 | bytes[1] << 40 | bytes[2] << 32 |
        bytes[3] << 24 | bytes[4] << 16 | bytes[5] << 8 | bytes[6]
    else
      raise "Invalid required bytes: #{required}"
    end
  end

  def read_object
    value = read_byte

    if value % 2 == 1
      return (value - 1) / 2
    end

    if value % 4 == 2
      typ = (value - 2) / 4
      count = (typ - typ % 4) / 4
      typ = typ % 4
      return embedded_reader(typ, count)
    end

    if value % 8 == 4
      packed = read_byte * 256 + value
      return value % 16 == 12 ? -(packed - 12) / 16 : (packed - 4) / 16
    end

    reader_table(value / 8)
  end

  def read_table(entry_count, value = nil)
    value ||= {}
    add_reference(@table_refs, value)

    entry_count.times do
      k, v = read_pair(method(:read_object))
      value[k] = v
    end

    value
  end

  def read_array(entry_count, value = nil)
    value ||= []
    add_reference(@table_refs, value)

    entry_count.times do |i|
      value[i] = read_object
    end

    value
  end

  def read_mixed(array_count, map_count)
    value = {}
    add_reference(@table_refs, value)

    array_values = read_array(array_count)
    value.merge!(Hash[array_values.map.with_index(1) { |v, i| [i, v] }])

    read_table(map_count, value)

    value
  end

  def read_string(length)
    value = read_bytes(length)
    add_reference(@string_refs, value) if length > 2
    value
  end

  def read_byte
    read_int(1)
  end

  def read_int(required)
    string_to_int(read_bytes(required), required)
  end

  def read_pair(fn, *args)
    first = fn.call(*args)
    second = fn.call(*args)
    [first, second]
  end

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
      read_mixed(*read_pair(method(:read_byte)))
    when READER_INDEX[:MIXED_16]
      read_mixed(*read_pair(method(:read_int), 2))
    when READER_INDEX[:MIXED_24]
      read_mixed(*read_pair(method(:read_int), 3))
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

  def add_reference(refs, value)
    refs << value
  end
end

class LibSerializeSerialize < LibSerialize
  def initialize(data)
    @string_refs = {}
    @object_refs = {}
    @data = data
    @buffer = []
  end

  def self.serialize(data)
    new(data).serialize
  end

  def write_byte(byte)
    @buffer << byte.chr
  end

  def write_string(string)
    @buffer << string
  end

  alias_method :write_bytes, :write_string

  def int_to_string(n, required)
    case required
    when 1
      [n].pack('C')
    when 2
      [n].pack('n')
    when 3
      [n >> 16 & 0xFF, n >> 8 & 0xFF, n & 0xFF].pack('C3')
    when 4
      [n].pack('N')
    when 7
      [
        n >> 48 & 0xFF,
        n >> 40 & 0xFF,
        n >> 32 & 0xFF,
        n >> 24 & 0xFF,
        n >> 16 & 0xFF,
        n >> 8 & 0xFF,
        n & 0xFF,
      ].pack('C7')
    else
      raise "Invalid required bytes: #{required}"
    end
  end

  def float_to_string(n)
    [n].pack('G')
  end

  def serialize
    write_int(1, 1)
    write_object(@data)
    @buffer.join
  end

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

  def write_nil
    write_byte(READER_INDEX[:NIL])
  end

  alias_method :serialize_nil, :write_nil

  def write_int(num, required)
    write_string(int_to_string(num, required))
  end

  def serialize_number(number)
    if number.is_a?(Float)
      serialize_float(number)
    elsif number > -4096 && number < 4096
      serialize_small_integer(number)
    else
      serialize_large_integer(number)
    end
  end

  def serialize_float(num)
    num_abs = num.abs
    as_string = num_abs.to_s
    if as_string.length < 7 && as_string.to_f == num_abs && num_abs.finite?
      sign = num < 0 ? 1 : 0
      write_byte((READER_INDEX[:NUM_FLOATSTR_POS] + sign) << 3)
      write_byte(as_string.length)
      write_string(as_string)
    else
      write_byte(READER_INDEX[:NUM_FLOAT] << 3)
      write_string([num].pack('G'))
    end
  end

  def serialize_small_integer(num)
    if num >= 0 && num < 128
      write_byte(num * 2 + 1)
    else
      sign = num < 0 ? 8 : 0
      num = num.abs * 16 + sign + 4
      upper, lower = (num / 256).floor, num % 256
      write_byte(lower)
      write_byte(upper)
    end
  end

  def serialize_large_integer(num)
    sign = num < 0 ? 1 : 0
    num = num.abs
    required_bytes = get_required_bytes_number(num)
    required_bytes = 2 if required_bytes == 1
    write_byte((NUMBER_INDICES[required_bytes] + sign) << 3)
    write_int(num, required_bytes)
  end

  def serialize_boolean(bool)
    write_byte((bool ? READER_INDEX[:BOOL_T] : READER_INDEX[:BOOL_F]) << 3)
  end

  def serialize_string(str)
    ref = @string_refs[str]
    if ref
      required_bytes = get_required_bytes(ref)
      ref_type = STRING_REF_INDICES[required_bytes]
      write_byte(ref_type << 3)
      write_int(ref, required_bytes)
    else
      len = str.bytesize
      write_type_with_count(:STRING, len)
      write_string(str)
      @string_refs[str] = @string_refs.count + 1 if len > 2
    end
  end

  def serialize_array(data)
    ref = @object_refs[data.object_id]
    if ref
      required_bytes = get_required_bytes(ref)
      ref_type = TABLE_REF_INDICES[required_bytes]
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

  def serialize_table(data)
    ref = @object_refs[data.object_id]
    if ref
      required_bytes = get_required_bytes(ref)
      ref_type = TABLE_REF_INDICES[required_bytes]
      write_byte(ref_type << 3)
      write_int(ref, required_bytes)
    else
      len = data.length
      write_type_with_count(:TABLE, len)
      data.each do |key, value|
        write_object(key)
        write_object(value)
      end
      @object_refs[data.object_id] = @object_refs.count + 1 if len > 2
    end
  end

  def write_type_with_count(type_name, count)
    if count < 16
      embedded_type = EMBEDDED_INDEX[type_name]
      write_byte(embedded_type << EMBEDDED_INDEX_SHIFT | count << EMBEDDED_COUNT_SHIFT | 2)
    else
      required = get_required_bytes(count)
      type = TYPE_INDICES[type_name][required]
      write_byte(type << 3)
      write_int(count, required)
    end
  end
end
