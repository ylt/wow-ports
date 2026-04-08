# typed: strict
# frozen_string_literal: true

# VuhDo custom serializer -- decode/encode VuhDo's type-length-value format.
#
# Wire format:
#   <key><value> pairs concatenated, no top-level container marker.
#
#   Keys:   N<digits>=   (numeric key)
#           S<string>=   (string key, may use abbreviations)
#
#   Values: S<len>+<string>    string with byte count
#           N<len>+<number>    number as %.4f with byte count
#           T<len>+<nested>    nested table with byte count
#           1                  boolean true
#           0                  boolean false
#
# Key abbreviations: short keys like *c expand to full names (color, etc.)

require 'sorbet-runtime'

module Azerite
  module VuhDoSerializer
    extend T::Sig

    ABBREV_TO_KEY = T.let({
      '*a' => 'isFullDuration',
      '*b' => 'useBackground',
      '*c' => 'color',
      '*d' => 'isStacks',
      '*e' => 'isIcon',
      '*f' => 'isColor',
      '*g' => 'bright',
      '*h' => 'others',
      '*i' => 'icon',
      '*j' => 'timer',
      '*k' => 'animate',
      '*l' => 'isClock',
      '*m' => 'mine',
      '*n' => 'name',
      '*o' => 'useOpacity',
      '*p' => 'countdownMode',
      '*r' => 'radio',
      '*s' => 'isManuallySet',
      '*t' => 'useText',
      '*u' => 'custom'
    }.freeze, T::Hash[String, String])

    KEY_TO_ABBREV = T.let(ABBREV_TO_KEY.invert.freeze, T::Hash[String, String])

    class << self
      extend T::Sig

      sig { params(str: String).returns(T::Hash[T.any(Integer, String), T.untyped]) }
      def deserialize(str)
        table = T.let({}, T::Hash[T.any(Integer, String), T.untyped])
        i = 0

        while i < str.length
          # Read key: N<digits>= or S<string>=
          eq = str.index('=', i + 1)
          break unless eq

          key_type = str[i]
          key_raw = T.must(str[(i + 1)...eq])

          key = T.let(if key_type == 'N'
                        key_raw.to_i
                      else
                        ABBREV_TO_KEY[key_raw] || key_raw
                      end, T.any(Integer, String))

          # Read value
          vt = str[eq + 1]
          value = T.let(nil, T.untyped)
          case vt
          when 'S'
            i, value = read_length_value(str, eq + 1)
          when 'N'
            i, raw = read_length_value(str, eq + 1)
            value = T.must(raw).include?('.') ? T.must(raw).to_f : T.must(raw).to_i
          when 'T'
            i, raw = read_length_value(str, eq + 1)
            value = deserialize(T.must(raw))
          when '1'
            value = true
            i = eq + 2
          when '0'
            value = false
            i = eq + 2
          else
            break
          end

          table[key] = value unless value.nil?
        end

        table
      end

      sig { params(table: T::Hash[T.any(Integer, String), T.untyped]).returns(String) }
      def serialize(table)
        result = +''

        table.each do |key, value|
          result << if key.is_a?(Integer)
                      "N#{key}="
                    else
                      "S#{KEY_TO_ABBREV[key] || key}="
                    end

          case value
          when String
            result << "S#{value.length}+#{value}"
          when Integer
            s = format('%0.4f', value)
            result << "N#{s.length}+#{s}"
          when Float
            s = format('%0.4f', value)
            result << "N#{s.length}+#{s}"
          when TrueClass
            result << '1'
          when FalseClass
            result << '0'
          when Hash
            nested = serialize(value)
            result << "T#{nested.length}+#{nested}"
          end
        end

        result
      end

      private

      sig { params(str: String, pos: Integer).returns([Integer, T.nilable(String)]) }
      def read_length_value(str, pos)
        # pos points to type char (S/N/T), next is length digits, then +, then value
        plus = str.index('+', pos + 1)
        return [str.length, nil] unless plus

        len = T.must(str[(pos + 1)...plus]).to_i
        value = str[plus + 1, len]
        [plus + 1 + len, value]
      end
    end
  end
end
