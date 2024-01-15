class LuaDeflate
  # Define a custom base64 character set.
  BYTE_TO_BIT = [
    *'a'..'z',
    *'A'..'Z',
    *'0'..'9',
    '(',
    ')'
  ].freeze

  # Create a reverse lookup hash from the custom base64 character set.
  BIT_TO_BYTE = BYTE_TO_BIT.each.with_index.to_a.to_h.freeze

  class << self
    def decode_for_print(encoded_str)
      return unless encoded_str.is_a?(String)

      # Strip leading and trailing whitespace.
      encoded_str = encoded_str.strip
      return if encoded_str.length <= 1

      decoded_bytes = encoded_str.chars.each_slice(4).flat_map do |char_group|
        # Convert each character in the chunk to its corresponding base64 index.
        indices = char_group.map { |char| BIT_TO_BYTE[char] }
        return nil if indices.include?(nil)

        # Calculate the 24-bit number represented by the chunk.
        value = indices.each_with_index.sum { |index, idx| index * (64**idx) }

        # Determine the number of bytes this chunk should produce.
        bytes_to_take = char_group.length == 4 ? 3 : char_group.length - 1

        # Extract bytes from the 24-bit number.
        bytes_to_take.times.map { |shift| ((value >> (8 * shift)) & 0xFF).chr }
      end

      decoded_bytes.join
    end

    def encode_for_print(str)
      raise ArgumentError, "Expected 'str' to be a string, got #{str.class}" unless str.is_a?(String)

      encoded_chunks = str.chars.each_slice(3).map do |byte_group|
        # Convert characters to their ASCII byte values.
        bytes = byte_group.map(&:ord)

        # Calculate the 24-bit number represented by the 3 bytes.
        value = bytes.each_with_index.sum { |byte, idx| byte * (256**idx) }

        # Determine the number of chunks this group should produce.
        chunks_to_take = byte_group.length + 1

        # Extract 6-bit chunks from the 24-bit number and convert them to characters.
        chunks_to_take.times.map { |idx| BYTE_TO_BIT[(value >> (6 * idx)) & 0x3F] }
      end

      encoded_chunks.flatten.join
    end
  end
end
