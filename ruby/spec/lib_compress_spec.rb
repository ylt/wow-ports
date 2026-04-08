# frozen_string_literal: true

require_relative '../lib/azerite/lib_compress'

LibCompress = Azerite::LibCompress unless defined?(LibCompress)

RSpec.describe 'LibCompress' do
  describe 'method 0x01 (uncompressed)' do
    it 'passes through raw bytes' do
      wire = "\x01hello".b
      expect(LibCompress.decompress(wire)).to eq('hello')
    end

    it 'handles empty payload' do
      wire = "\x01".b
      expect(LibCompress.decompress(wire)).to eq('')
    end
  end

  describe 'method 0x02 (LZW)' do
    it 'decompresses single-byte codes' do
      # Codes: 104,101,108,108,111 → "hello"
      wire = [0x02, 104, 101, 108, 108, 111].pack('C*')
      expect(LibCompress.decompress(wire)).to eq('hello')
    end

    it 'decompresses with dictionary hits' do
      # Codes: 65('A'), 66('B'), 256('AB'), 258('ABA'), 66('B') → "ABABABAB"
      # 256 encoded as: 0xFE 0x02 0x02
      # 258 encoded as: 0xFE 0x04 0x02
      wire = [0x02, 65, 66, 0xFE, 2, 2, 0xFE, 4, 2, 66].pack('C*')
      expect(LibCompress.decompress(wire)).to eq('ABABABAB')
    end

    it 'decompresses single char' do
      wire = [0x02, 65].pack('C*')
      expect(LibCompress.decompress(wire)).to eq('A')
    end
  end

  describe 'method 0x03 (Huffman)' do
    it 'decompresses a minimal Huffman stream' do
      # Build a minimal Huffman-compressed blob:
      # 1 symbol ('A'=65), orig_size=3 → output "AAA"
      # Symbol map: symbol=65, code=0 (1-bit), escaped as "0" + stop bits "11" = "011"
      # Data: three 1-bit codes (0,0,0) = "000"
      #
      # Header: 03 00 03 00 00 (method=3, num_symbols=0+1=1, orig_size=3)
      # Bitstream byte 5: symbol 65 = 0x41 (8 bits)
      # Bitstream byte 6: escaped code "011" + data "000" = 011000_xx
      #   bits: 0,1,1,0,0,0 → byte = 0b00000110 = 0x06 (LSB first)
      wire = [0x03, 0x00, 0x03, 0x00, 0x00, 0x41, 0x06].pack('C*')
      expect(LibCompress.decompress(wire)).to eq('AAA')
    end
  end

  describe 'error handling' do
    it 'raises on empty input' do
      expect { LibCompress.decompress('') }.to raise_error(LibCompress::Error)
    end

    it 'raises on nil input' do
      expect { LibCompress.decompress(nil) }.to raise_error(TypeError)
    end

    it 'raises on unknown method' do
      expect { LibCompress.decompress("\x05data") }.to raise_error(LibCompress::Error, /Unknown compression method/)
    end
  end
end
