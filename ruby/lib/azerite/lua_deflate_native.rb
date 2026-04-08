# typed: strict
# frozen_string_literal: true

require 'base64'
require 'sorbet-runtime'

module Azerite
  class LuaDeflateNative
    extend T::Sig

    # LuaDeflate custom alphabet: abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()
    LUA_ALPHABET = T.let('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()', String)

    # Standard base64 alphabet (matches strict_encode64 output, no padding)
    B64_ALPHABET = T.let('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', String)

    class << self
      extend T::Sig

      sig { params(str: String).returns(String) }
      def encode_for_print(str)
        original_length = str.bytesize

        # Step 1: Pad input to multiple of 3 bytes
        remainder = original_length % 3
        padded = remainder.zero? ? str : str + ("\0" * (3 - remainder))

        # Step 2: Reverse each 3-byte group
        reversed_input = padded.gsub(/.{3}/m, &:reverse)

        # Step 3: Standard base64 encode (no newlines, no padding chars)
        b64 = Base64.strict_encode64(reversed_input)

        # Step 4: Reverse each 4-char group
        reversed_b64 = b64.gsub(/.{4}/, &:reverse)

        # Step 5: Translate standard base64 alphabet -> LuaDeflate alphabet
        translated = reversed_b64.tr(B64_ALPHABET, LUA_ALPHABET)

        # Step 6: Trim to correct output length
        output_length = ((original_length * 4.0) / 3).ceil
        T.must(translated[0, output_length])
      end

      sig { params(encoded_str: String).returns(T.nilable(String)) }
      def decode_for_print(encoded_str)
        return unless encoded_str.is_a?(String)

        # Step 1: Strip whitespace, validate length
        encoded_str = encoded_str.strip
        return '' if encoded_str.empty?
        return nil if encoded_str.length == 1

        # Validate all chars are in the WoW alphabet
        return nil unless encoded_str.match?(/\A[a-zA-Z0-9()]+\z/)

        pre_padding_length = encoded_str.length

        # Step 2: Translate LuaDeflate alphabet -> standard base64 alphabet
        b64 = encoded_str.tr(LUA_ALPHABET, B64_ALPHABET)

        # Step 3: Reverse each 4-char group
        # First pad to multiple of 4 so groups align, then reverse, then we'll re-pad
        # We must reverse on the pre-padded chunks, so pad first
        remainder = pre_padding_length % 4
        padded_b64 = remainder.zero? ? b64 : b64 + ('A' * (4 - remainder))

        reversed_b64 = padded_b64.gsub(/.{4}/, &:reverse)

        # Step 4: Pad to multiple of 4 with '=' for strict_decode64
        eq_remainder = reversed_b64.length % 4
        padded_for_decode = eq_remainder.zero? ? reversed_b64 : reversed_b64 + ('=' * (4 - eq_remainder))

        # Step 5: Decode base64
        begin
          decoded = Base64.strict_decode64(padded_for_decode)
        rescue ArgumentError
          return nil
        end

        # Step 6: Reverse each 3-byte group
        unreversed = decoded.gsub(/.{3}/m, &:reverse)

        # Step 7: Trim to correct byte count based on pre-padding encoded length
        # Each 4 encoded chars = 3 bytes; partial group: (n chars - 1) bytes
        full_groups, leftover = pre_padding_length.divmod(4)
        byte_count = (full_groups * 3) + (leftover.zero? ? 0 : leftover - 1)

        unreversed[0, byte_count]
      end
    end
  end
end
