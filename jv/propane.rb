# frozen_string_literal: true
require 'java'
unless defined? PROPANE_ROOT
  $LOAD_PATH << $src_path #File.dirname(__dir__)
  $LOAD_PATH << $lib_path
  $LOAD_PATH << "#{$lib_path}/propane_jars"
  PROPANE_ROOT = $src_path #File.dirname(__dir__)
end
Dir["#{PROPANE_ROOT}/lib/propane_jars/*.jar"].each do |jar|
  require jar
end
require_relative 'propane/app'
