# typed: strict
# frozen_string_literal: true

require 'cbor'
require 'sorbet-runtime'

# WowCbor wraps the CBOR library with WoW-specific post-processing:
# - CBOR byte strings (binary Ruby strings) are decoded to UTF-8 text
# - Sequential 1-based integer-keyed maps are converted to arrays (Lua table convention)
module Azerite
  class WowCbor
    extend T::Sig

    class << self
      extend T::Sig

      # Decode CBOR bytes to a Ruby value with WoW-specific post-processing.
      sig { params(bytes: String).returns(T.untyped) }
      def decode(bytes)
        raw = CBOR.decode(bytes)
        post_process(raw)
      end

      # Encode a Ruby value to CBOR bytes.
      sig { params(data: T.untyped).returns(String) }
      def encode(data)
        data.to_cbor
      end

      private

      sig { params(val: T.untyped).returns(T.untyped) }
      def post_process(val)
        case val
        when String
          # CBOR byte strings come back as binary-encoded Ruby strings
          if [Encoding::BINARY, Encoding::ASCII_8BIT].include?(val.encoding)
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

      sig { params(hash: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
      def apply_array_detection(hash)
        keys = hash.keys
        return hash if keys.empty?
        return hash unless keys.all? { |k| k.is_a?(Integer) && k.positive? }

        sorted = keys.sort
        return hash unless sorted == (1..keys.size).to_a

        sorted.map { |k| hash[k] }
      end
    end
  end
end
