# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module Azerite
  module WowAceSerialization
    extend T::Sig
    include Kernel

    sig { params(obj: T.untyped).returns(String) }
    def serialize(obj)
      "^1#{serialize_internal(obj)}^^"
    end

    private

    sig { params(obj: T.untyped).returns(String) }
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

    sig { params(str: String).returns(String) }
    def serialize_string(str)
      escaped = str.gsub(/[\x00-\x20\x5E\x7E\x7F]/) do |m|
        byte = m.ord
        case byte
        when 0x1E then '~z'
        when 0x5E then '~}'
        when 0x7E then '~|'
        when 0x7F then '~{'
        else "~#{(byte + 64).chr}"
        end
      end
      "^S#{escaped}"
    end

    sig { params(num: Numeric).returns(String) }
    def serialize_number(num)
      if num.is_a?(Float) && num.infinite? == 1 # Positive Infinity
        '^N1.#INF'
      elsif num.is_a?(Float) && num.infinite? == -1 # Negative Infinity
        '^N-1.#INF'
      elsif num.is_a?(Integer)
        "^N#{num}"
      else
        # Lua uses tonumber(tostring(v))==v -- if the float survives string round-trip, use ^N
        str_val = format('%.14g', num)
        if str_val.to_f == num
          "^N#{str_val}"
        else
          mantissa, exponent = Math.frexp(T.cast(num, Float))
          "^F#{(T.cast(mantissa, Float) * (2**53)).to_i}^f#{exponent - 53}"
        end
      end
    end

    sig { params(table: T::Hash[T.untyped, T.untyped]).returns(String) }
    def serialize_table(table)
      serialized = table.map do |key, value|
        serialize_internal(key) + serialize_internal(value)
      end.join
      "^T#{serialized}^t"
    end

    sig { params(array: T::Array[T.untyped]).returns(String) }
    def serialize_array(array)
      indexed_table = {}
      array.each_with_index do |value, index|
        indexed_table[index + 1] = value
      end
      serialize_table(indexed_table)
    end
  end

  module WowAceDeserialization
    extend T::Sig
    include Kernel

    sig { params(str: String).returns(T.untyped) }
    def deserialize(str)
      str = str.strip.gsub(/[\x00-\x20]/, '') # remove control characters and whitespace
      raise 'Invalid prefix' unless str.start_with?('^1')
      raise 'Missing terminator' unless str.end_with?('^^')

      data = T.must(str[2..-3]) # remove prefix and ending ^^
      deserialize_internal(data)
    end

    private

    sig { params(data: String).returns(T.untyped) }
    def deserialize_internal(data)
      prefix = T.must(data.slice!(0, 2))
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

    sig { params(data: String).returns(String) }
    def deserialize_string(data)
      string_end = data.index(/(?=\^[\wZbt])/) || data.length
      string_data = T.must(data.slice!(0, string_end))
      string_data.gsub!(/~(.)/) do
        c = T.must(::Regexp.last_match(1))
        case c.ord
        when 0...122 then (c.ord - 64).chr  # generic: chr(byte - 64)
        when 122 then "\x1E"                # ~z -> byte 30
        when 123 then "\x7F" # ~{ -> DEL
        when 124 then '~'                   # ~| -> ~
        when 125 then '^'                   # ~} -> ^
        end
      end
      string_data
    end

    sig { params(data: String).returns(T.any(Integer, Float)) }
    def deserialize_number(data)
      number_end = data.index(/(?=\^[\wZbtFf])/) || data.length
      number = T.must(data.slice!(0, number_end))
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

    sig { params(data: String).returns(Float) }
    def deserialize_float(data)
      mantissa = T.must(data.slice!(/^-?\d+/)).to_i
      data.slice!(0, 2) # remove ^f
      exponent = T.must(data.slice!(/^-?\d+/)).to_i
      Math.ldexp(mantissa, exponent).to_f
    end

    sig { params(data: String).returns(T::Hash[T.untyped, T.untyped]) }
    def deserialize_table(data)
      table = {}
      until data[0..1] == '^t'
        key = deserialize_internal(data)
        value = deserialize_internal(data)
        table[key] = value
      end
      data.slice!(0, 2) # remove ^t
      table
    end
  end

  class WowAceSerializer
    extend T::Sig
    include WowAceSerialization
    include WowAceDeserialization

    # Any common methods or attributes for both serialization and deserialization can remain in the main class.
  end
end
