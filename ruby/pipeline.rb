# frozen_string_literal: true

require 'zlib'
require_relative 'lua_deflate'
require_relative 'wowace'
require_relative 'lib_serialize'
require_relative 'wow_cbor'

ExportResult = Struct.new(:addon, :version, :data, :metadata)

class Pipeline
  class << self
    # Decode a WoW addon export string.
    # Returns an ExportResult(addon, version, data, metadata).
    def decode(export_str)
      export_str = export_str.strip
      detected = detect_addon(export_str)
      addon    = detected[:addon]
      version  = detected[:version]
      encoded  = export_str[detected[:prefix].length..]

      # ElvUI: strip ^^:: metadata trailer before LuaDeflate decode
      metadata = nil
      if addon == 'elvui'
        meta_idx = encoded.index('^^::')
        if meta_idx
          meta_part = encoded[(meta_idx + 4)..]
          parts = meta_part.split('::')
          metadata = { profile_type: parts[0], profile_key: parts[1] }
          encoded = encoded[0...meta_idx]
        end
      end

      # LuaDeflate decode → binary string
      compressed = LuaDeflate.decode_for_print(encoded)
      raise 'LuaDeflate decode failed' unless compressed

      # zlib raw inflate
      inflated = inflate_raw(compressed)

      # Deserialize
      data = if addon == 'plater' && version == 2
               WowCbor.decode(inflated)
             elsif version == 2
               LibSerializeDeserialize.deserialize(inflated)
             else
               WowAceSerializer.new.deserialize(inflated.force_encoding('UTF-8'))
             end

      ExportResult.new(addon, version, data, metadata)
    end

    # Encode an ExportResult back to a WoW addon export string.
    def encode(export_result)
      addon    = export_result.addon
      version  = export_result.version
      data     = export_result.data
      metadata = export_result.metadata

      # Serialize
      serialized = if addon == 'plater' && version == 2
                     WowCbor.encode(data)
                   elsif version == 2
                     LibSerializeSerialize.serialize(data)
                   else
                     WowAceSerializer.new.serialize(data)
                   end

      # zlib raw deflate
      compressed = deflate_raw(serialized.b)

      # LuaDeflate encode
      encoded = LuaDeflate.encode_for_print(compressed)

      # ElvUI: append metadata trailer
      if addon == 'elvui' && metadata
        encoded += "^^::#{metadata[:profile_type]}::#{metadata[:profile_key]}"
      end

      prefix_for(addon, version) + encoded
    end

    private

    def detect_addon(str)
      if str.start_with?('!PLATER:2!')
        { addon: 'plater', version: 2, prefix: '!PLATER:2!' }
      elsif str.start_with?('!WA:2!')
        { addon: 'weakauras', version: 2, prefix: '!WA:2!' }
      elsif str.start_with?('!E1!')
        { addon: 'elvui', version: 1, prefix: '!E1!' }
      elsif str.start_with?('!')
        { addon: 'weakauras', version: 1, prefix: '!' }
      else
        { addon: 'weakauras', version: 0, prefix: '' }
      end
    end

    def prefix_for(addon, version)
      return '!PLATER:2!' if addon == 'plater' && version == 2
      return '!WA:2!'     if version == 2
      return '!E1!'       if addon == 'elvui'
      return '!'          if version >= 1

      ''
    end

    def inflate_raw(data)
      z = Zlib::Inflate.new(-Zlib::MAX_WBITS)
      z.inflate(data)
    ensure
      z&.close
    end

    def deflate_raw(data)
      z = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
      z.deflate(data, Zlib::FINISH)
    ensure
      z&.close
    end
  end
end
