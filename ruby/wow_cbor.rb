# frozen_string_literal: true

require 'cbor'

# WowCbor wraps the CBOR library with WoW-specific post-processing:
# - CBOR byte strings (binary Ruby strings) are decoded to UTF-8 text
# - Sequential 1-based integer-keyed maps are converted to arrays (Lua table convention)
class WowCbor
  class << self
    # Decode CBOR bytes to a Ruby value with WoW-specific post-processing.
    def decode(bytes)
      raw = CBOR.decode(bytes)
      post_process(raw)
    end

    # Encode a Ruby value to CBOR bytes.
    def encode(data)
      data.to_cbor
    end

    private

    def post_process(val)
      case val
      when String
        # CBOR byte strings come back as binary-encoded Ruby strings
        if val.encoding == Encoding::BINARY || val.encoding == Encoding::ASCII_8BIT
          val.encode('UTF-8', invalid: :replace, undef: :replace)
        else
          val
        end
      when Array
        val.map { |v| post_process(v) }
      when Hash
        result = val.transform_values { |v| post_process(v) }
        apply_array_detection(result)
      else
        val
      end
    end

    def apply_array_detection(hash)
      keys = hash.keys
      return hash if keys.empty?
      return hash unless keys.all? { |k| k.is_a?(Integer) && k > 0 }

      sorted = keys.sort
      return hash unless sorted == (1..keys.size).to_a

      sorted.map { |k| hash[k] }
    end
  end
end
