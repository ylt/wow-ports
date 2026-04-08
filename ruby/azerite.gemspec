# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "azerite"
  spec.version = "0.1.0"
  spec.authors = ["Joe Carter"]
  spec.email = ["theupperquartile@gmail.com"]

  spec.summary = "Decode and encode WoW addon export strings (WeakAuras, ElvUI, Plater, MDT, VuhDo, and more)"
  spec.description = "Decode and encode World of Warcraft addon export strings (WeakAuras, ElvUI, Plater, MDT, VuhDo, and more). Handles base64, zlib, LibCompress, AceSerializer, LibSerialize, and CBOR."
  spec.homepage = "https://github.com/ylt/azerite"
  spec.license = "ISC"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ylt/azerite"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "cbor", "~> 0.5"
  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "sorbet-runtime", "~> 0.5"
end
