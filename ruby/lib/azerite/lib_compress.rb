# typed: strict
# frozen_string_literal: true

# Clean-room implementation of LibCompress decompression.
#
# Written from the wire format specification only -- NOT derived from
# the GPL-licensed LibCompress.lua source code.
#
# Wire format (determined by binary analysis of real export strings):
#
# BYTE 0: Method marker
#   0x01 = Uncompressed (remaining bytes are the raw payload)
#   0x02 = LZW compressed
#   0x03 = Huffman compressed
#
# -- LZW Format (method 0x02) --
#
# Standard LZW with a 256-entry initial dictionary (one per byte value).
# Dictionary codes are encoded as variable-length byte sequences:
#
#   If byte < 250: the code is the byte value itself (1 byte consumed).
#   If byte >= 250: multi-byte encoding.
#     count = 256 - byte (number of following value bytes)
#     value = big-endian-ish base-255+1 reconstruction:
#       reading the `count` following bytes in reverse order,
#       accumulate: result = result * 255 + (byte - 1)
#
# The LZW algorithm is standard: initialize 256 single-byte entries,
# read codes, build dictionary entries as prefix + first char of current.
#
# -- Huffman Format (method 0x03) --
#
# Header (5 bytes after method byte):
#   Byte 1: num_symbols - 1 (so actual count = byte + 1)
#   Bytes 2-4: original uncompressed size as LE 24-bit integer
#              (byte2 + byte3*256 + byte4*65536)
#
# Symbol-to-code map (starts at byte 5):
#   Read as a bitstream (LSB-first within each byte).
#   For each symbol:
#     1. Read 8 bits -> symbol value
#     2. Read escaped Huffman code (variable length):
#        - Bits are read until two consecutive 1-bits are found ("stop bits")
#        - The code is everything before the second-to-last bit of the stop pair
#        - The code length is (position of first stop bit - 1)
#        - Then unescape: in the escaped form, a 1-bit is represented as "11"
#          and a 0-bit as "0". Unescape by: for each bit, if it's 1, consume
#          the next bit too (which is also 1), output a 1. If 0, output 0.
#
# Compressed data (follows immediately after the symbol map in the same bitstream):
#   Read codes of increasing length starting from min_code_len.
#   Look up code in map[code_len][code] -> symbol byte.
#   If found, emit symbol, reset code length to min.
#   If not found, try code_len + 1.
#   Feed more bytes into the bitstream as needed.
#   Stop when orig_size bytes have been emitted.

require 'sorbet-runtime'

module Azerite
  module LibCompress
    extend T::Sig

    class Error < StandardError; end

    class << self
      extend T::Sig

      sig { params(data: String).returns(String) }
      def decompress(data)
        raise Error, 'Cannot decompress empty data' if data.empty?

        method = data.getbyte(0)
        case method
        when 1 then T.must(data[1..])
        when 2 then decompress_lzw(data)
        when 3 then decompress_huffman(data)
        else raise Error, "Unknown compression method (#{method})"
        end
      end

      private

      # -- LZW --

      sig { params(data: String).returns(String) }
      def decompress_lzw(data)
        buf = data.b
        pos = 1 # skip method byte

        # Initialize dictionary with single-byte entries
        dict = Array.new(256) { |i| i.chr.b }
        dict_size = 256

        code, delta = read_code(buf, pos)
        pos += delta
        w = dict[code]
        result = [w]

        while pos < buf.bytesize
          code, delta = read_code(buf, pos)
          pos += delta

          entry = if code < dict_size
                    dict[code]
                  else
                    w + w[0] # special case: code not yet in dict
                  end

          result << entry
          dict[dict_size] = w + entry[0]
          dict_size += 1
          w = entry
        end

        result.join
      end

      # Read a variable-length LZW code from the byte stream.
      sig { params(buf: String, pos: Integer).returns([Integer, Integer]) }
      def read_code(buf, pos)
        a = T.must(buf.getbyte(pos))
        if a < 250
          [a, 1]
        else
          count = 256 - a
          r = 0
          (pos + count).downto(pos + 1) do |n|
            r = (r * 255) + T.must(buf.getbyte(n)) - 1
          end
          [r, count + 1]
        end
      end

      # -- Huffman --

      sig { params(data: String).returns(String) }
      def decompress_huffman(data)
        buf = data.b
        buf_size = buf.bytesize

        # Parse header
        num_symbols = T.must(buf.getbyte(1)) + 1
        orig_size = T.must(buf.getbyte(2)) | (T.must(buf.getbyte(3)) << 8) | (T.must(buf.getbyte(4)) << 16)
        return ''.b if orig_size.zero?

        # Read the symbol->code map from the bitstream
        bitfield = 0
        bitfield_len = 0
        byte_pos = 5 # first byte after header

        map = T.let({}, T::Hash[Integer, T::Hash[Integer, String]])
        min_code_len = T.let(nil, T.nilable(Integer))
        max_code_len = 0
        symbols_read = 0
        state = T.let(:symbol, Symbol) # :symbol = read 8-bit symbol, :code = read escaped code
        symbol = T.let(0, Integer)

        while symbols_read < num_symbols
          raise Error, 'Truncated Huffman map' if byte_pos >= buf_size

          bitfield |= (T.must(buf.getbyte(byte_pos)) << bitfield_len)
          bitfield_len += 8

          if state == :symbol
            symbol = bitfield & 0xFF
            bitfield >>= 8
            bitfield_len -= 8
            state = :code
          else
            code_result = extract_escaped_code(bitfield, bitfield_len)
            if code_result
              code, code_len, bitfield, bitfield_len = code_result
              unescaped, ul = unescape(code, code_len)

              map[ul] ||= {}
              T.must(map[ul])[unescaped] = symbol.chr.b
              min_code_len = ul if min_code_len.nil? || ul < min_code_len
              max_code_len = ul if ul > max_code_len
              symbols_read += 1
              state = :symbol
            end
          end

          byte_pos += 1
        end

        # Decode compressed data from the continuing bitstream
        result = T.let([], T::Array[String])
        dec_size = 0
        test_len = T.must(min_code_len)

        loop do
          if test_len <= bitfield_len
            test_code = bitfield & ((1 << test_len) - 1)
            sym = map.dig(test_len, test_code)
            if sym
              result << sym
              dec_size += 1
              break if dec_size >= orig_size

              bitfield >>= test_len
              bitfield_len -= test_len
              test_len = T.must(min_code_len)
            else
              test_len += 1
              raise Error, 'Huffman decode error: code too long' if test_len > max_code_len
            end
          else
            c = byte_pos < buf_size ? T.must(buf.getbyte(byte_pos)) : 0
            bitfield |= (c << bitfield_len)
            bitfield_len += 8
            break if byte_pos > buf_size

            byte_pos += 1
          end
        end

        result.join
      end

      # Find an escaped Huffman code in a bitfield.
      # The code is terminated by two consecutive set bits.
      # Returns [code, code_len, remaining_bitfield, remaining_len] or nil.
      sig { params(bitfield: Integer, field_len: Integer).returns(T.nilable([Integer, Integer, Integer, Integer])) }
      def extract_escaped_code(bitfield, field_len)
        return nil if field_len < 2

        prev = 0
        (0...field_len).each do |i|
          bit = bitfield & (1 << i)
          if prev != 0 && bit != 0
            # Two consecutive 1-bits found -- this is the stop marker
            code = bitfield & ((1 << (i - 1)) - 1)
            remaining = bitfield >> (i + 1)
            remaining_len = field_len - i - 1
            return [code, i - 1, remaining, remaining_len]
          end
          prev = bit
        end

        nil
      end

      # Remove escape encoding from a Huffman code.
      # Escaped: 1-bit is encoded as "11", 0-bit as "0".
      # So we walk the escaped bits: if we see a 1, skip the next bit (also 1).
      sig { params(code: Integer, code_len: Integer).returns([Integer, Integer]) }
      def unescape(code, code_len)
        unescaped = 0
        out_pos = 0
        i = 0
        while i < code_len
          bit = code & (1 << i)
          if bit != 0
            unescaped |= (1 << out_pos)
            i += 1 # skip the paired 1-bit
          end
          i += 1
          out_pos += 1
        end
        [unescaped, out_pos]
      end
    end
  end
end
