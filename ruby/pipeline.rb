# frozen_string_literal: true

require 'zlib'
require_relative 'lua_deflate'
require_relative 'wowace'
require_relative 'lib_serialize'
require_relative 'wow_cbor'

ExportResult = Struct.new(:addon, :version, :data, :metadata)

class Pipeline
  attr_reader :raw, :addon, :version, :prefix, :metadata, :compressed, :serialized, :data

  def initialize(export_str = nil)
    @raw        = export_str&.strip
    @addon      = nil
    @version    = nil
    @prefix     = nil
    @metadata   = nil
    @compressed = nil
    @serialized = nil
    @data       = nil
  end

  def self.from_result(export_result)
    p = new
    p.instance_variable_set(:@addon,    export_result.addon)
    p.instance_variable_set(:@version,  export_result.version)
    p.instance_variable_set(:@data,     export_result.data)
    p.instance_variable_set(:@metadata, export_result.metadata)
    p
  end

  # ── Decode steps ────────────────────────────────────────────────────────────

  def detect_format
    if @raw.start_with?('!PLATER:2!')
      @addon = 'plater';    @version = 2; @prefix = '!PLATER:2!'
    elsif @raw.start_with?('!WA:2!')
      @addon = 'weakauras'; @version = 2; @prefix = '!WA:2!'
    elsif @raw.start_with?('!E1!')
      @addon = 'elvui';     @version = 1; @prefix = '!E1!'
    elsif @raw.start_with?('!')
      @addon = 'weakauras'; @version = 1; @prefix = '!'
    else
      @addon = 'weakauras'; @version = 0; @prefix = ''
    end
    self
  end

  def strip_prefix
    @raw = @raw[@prefix.length..]
    self
  end

  def extract_metadata
    return self unless @addon == 'elvui'

    meta_idx = @raw.index('^^::')
    if meta_idx
      meta_part = @raw[(meta_idx + 4)..]
      parts     = meta_part.split('::')
      @metadata = { profile_type: parts[0], profile_key: parts[1] }
      @raw      = @raw[0...meta_idx]
    end
    self
  end

  def base64_decode
    @compressed = LuaDeflate.decode_for_print(@raw)
    raise 'LuaDeflate decode failed' unless @compressed
    self
  end

  def decompress
    @serialized = inflate_raw(@compressed)
    self
  end

  def deserialize
    @data = if @addon == 'plater' && @version == 2
              WowCbor.decode(@serialized)
            elsif @version == 2
              LibSerializeDeserialize.deserialize(@serialized)
            else
              WowAceSerializer.new.deserialize(@serialized.force_encoding('UTF-8'))
            end
    self
  end

  def result
    ExportResult.new(@addon, @version, @data, @metadata)
  end

  # ── Encode steps ────────────────────────────────────────────────────────────

  def serialize
    @serialized = if @addon == 'plater' && @version == 2
                    WowCbor.encode(@data)
                  elsif @version == 2
                    LibSerializeSerialize.serialize(@data)
                  else
                    WowAceSerializer.new.serialize(@data)
                  end
    self
  end

  def compress
    @compressed = deflate_raw(@serialized.b)
    self
  end

  def base64_encode
    @raw = LuaDeflate.encode_for_print(@compressed)
    self
  end

  def prepend_prefix
    @raw = prefix_for(@addon, @version) + @raw
    self
  end

  def append_metadata
    return self unless @addon == 'elvui' && @metadata

    @raw += "^^::#{@metadata[:profile_type]}::#{@metadata[:profile_key]}"
    self
  end

  def to_string
    @raw
  end

  # ── Class method wrappers ──────────────────────────────────────────────────

  def self.decode(export_str)
    p = new(export_str)
    p.detect_format
    p.strip_prefix
    p.extract_metadata
    p.base64_decode
    p.decompress
    p.deserialize
    p.result
  end

  def self.encode(export_result)
    p = from_result(export_result)
    p.serialize
    p.compress
    p.base64_encode
    p.prepend_prefix
    p.append_metadata
    p.to_string
  end

  private

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
