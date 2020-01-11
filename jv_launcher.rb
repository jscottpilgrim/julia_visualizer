#jscottpilgrim
#J.P.Scott 2019

$src_path = __dir__
$jv_root = File.dirname($src_path)
$lib_path = $src_path + "/lib"
$gui_launch = true

require_relative "lib/jv_gui.rb"

JvGui.new