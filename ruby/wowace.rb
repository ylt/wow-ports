# frozen_string_literal: true

module WowAceSerialization
  def serialize(obj)
    "^1#{serialize_internal(obj)}^^"
  end

  private

  def serialize_internal(obj)
    case obj
    when String then serialize_string(obj)
    when Integer, Float then serialize_number(obj)
    when Hash then serialize_table(obj)
    when Array then serialize_array(obj)
    when TrueClass then '^B'
    when FalseClass then '^b'
    when NilClass then '^Z'
    else raise "Unsupported data type: #{obj.class}"
    end
  end

  def serialize_string(str)
    escaped = str.gsub(/[\x00-\x20]/) { |m| "~#{(m.ord + 64).chr}" }
                 .gsub('^', '~U')
                 .gsub('~', '~T')
                 .gsub("\x7F", '~S')
    "^S#{escaped}"
  end

  def serialize_number(num)
    if num.infinite? == 1 # Positive Infinity
      '^N1.#INF'
    elsif num.infinite? == -1 # Negative Infinity
      '^N-1.#INF'
    elsif num.is_a?(Integer) || num.to_s == num.to_f.to_s
      "^N#{num}"
    else
      mantissa, exponent = Math.frexp(num)
      "^F#{(mantissa * (2**53)).to_i}^f#{exponent}"
    end
  end

  def serialize_table(table)
    serialized = table.map do |key, value|
      serialize_internal(key) + serialize_internal(value)
    end.join
    "^T#{serialized}^t"
  end

  def serialize_array(array)
    indexed_table = {}
    array.each_with_index do |value, index|
      indexed_table[index + 1] = value
    end
    serialize_table(indexed_table)
  end
end

module WowAceDeserialization
  def deserialize(str)
    str = str.strip.gsub(/[\x00-\x20]/, '') # remove control characters and whitespace
    raise 'Invalid prefix' unless str.start_with?('^1')

    data = str[2..-3] # remove prefix and ending ^^
    deserialize_internal(data)
  end

  private

  def deserialize_internal(data)
    prefix = data.slice!(0, 2)
    case prefix[1]
    when 'S'
      deserialize_string(data)
    when 'N'
      deserialize_number(data)
    when 'F'
      deserialize_float(data)
    when 'T'
      deserialize_table(data)
    when 'B'
      true
    when 'b'
      false
    when 'Z'
      nil
    else
      raise "Unsupported data type: #{prefix}"
    end
  end

  def deserialize_string(data)
    string_end = data.index(/(?=\^[\wZbt])/) || data.length
    string_data = data.slice!(0, string_end)
    string_data.gsub!(/~(.)/) do
      case ::Regexp.last_match(1)
      when 'U' then '^'
      when 'T' then '~'
      when 'S' then "\x7F"
      else (::Regexp.last_match(1).ord - 64).chr
      end
    end
    string_data
  end

  def deserialize_number(data)
    number_end = data.index(/(?=\^[\wZbtFf])/) || data.length
    number = data.slice!(0, number_end)
    if ['1.#INF', 'inf'].include?(number)
      Float::INFINITY
    elsif ['-1.#INF', '-inf'].include?(number)
      -Float::INFINITY
    elsif number =~ /^[-0-9]+$/
      number.to_i
    else
      number.to_f
    end
  end

  def deserialize_float(data)
    mantissa = data.slice!(/^-?\d+/).to_i
    data.slice!(0, 2) # remove ^f
    exponent = data.slice!(/^-?\d+/).to_i
    Math.ldexp(mantissa, exponent - 53).to_f
  end

  def deserialize_table(data)
    table = {}
    until data[0..1] == '^t'
      key = deserialize_internal(data)
      value = deserialize_internal(data)
      table[key] = value
    end
    data.slice!(0, 2) # remove ^t

    keys = table.keys.sort
    if keys == (1..keys.size).to_a
      table.values
    else
      table
    end
  end
end

class WowAceSerializer
  include WowAceSerialization
  include WowAceDeserialization

  # Any common methods or attributes for both serialization and deserialization can remain in the main class.
end

serializer = WowAceSerializer.new
serialized_data = serializer.serialize({ 'hello' => 'world', 'test' => 123, 'float' => 123.456,
                                         'nested' => [nil, nil, nil, 'test'] })
puts serialized_data
puts serializer.deserialize(serialized_data).inspect

# Check positive infinity
serialized_inf = serializer.serialize(Float::INFINITY)
puts "Serialized Positive Infinity: #{serialized_inf}"
puts "Deserialized: #{serializer.deserialize(serialized_inf).inspect}"

# Check negative infinity
serialized_neg_inf = serializer.serialize(-Float::INFINITY)
puts "\nSerialized Negative Infinity: #{serialized_neg_inf}"
puts "Deserialized: #{serializer.deserialize(serialized_neg_inf).inspect}"