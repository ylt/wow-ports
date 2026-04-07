# frozen_string_literal: true

# VuhDo custom serializer — decode/encode VuhDo's type-length-value format.
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

module VuhDoSerializer
  ABBREV_TO_KEY = {
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
    '*u' => 'custom',
  }.freeze

  KEY_TO_ABBREV = ABBREV_TO_KEY.invert.freeze

  def self.deserialize(str)
    table = {}
    i = 0

    while i < str.length
      # Read key: N<digits>= or S<string>=
      eq = str.index('=', i + 1)
      break unless eq

      key_type = str[i]
      key_raw = str[i + 1...eq]

      key = if key_type == 'N'
              key_raw.to_i
            else
              ABBREV_TO_KEY[key_raw] || key_raw
            end

      # Read value
      vt = str[eq + 1]
      case vt
      when 'S'
        i, value = read_length_value(str, eq + 1)
      when 'N'
        i, raw = read_length_value(str, eq + 1)
        value = raw.include?('.') ? raw.to_f : raw.to_i
      when 'T'
        i, raw = read_length_value(str, eq + 1)
        value = deserialize(raw)
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

  def self.serialize(table)
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

  def self.read_length_value(str, pos)
    # pos points to type char (S/N/T), next is length digits, then +, then value
    plus = str.index('+', pos + 1)
    return [str.length, nil] unless plus

    len = str[pos + 1...plus].to_i
    value = str[plus + 1, len]
    [plus + 1 + len, value]
  end

  private_class_method :read_length_value
end
