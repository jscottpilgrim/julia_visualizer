#jscottpilgrim
#J.P.Scott 2019

unless defined?(Propane::App)
	#need to change to current dir before loading propane to properly set SKETCH_ROOT
	Dir.chdir __dir__

	require "#{$src_path}/propane"
end

require "#{$src_path}/json" unless defined?(JSON)

require_relative 'julia_visualizer.rb'
require_relative 'sound_check.rb'

class ButtonsAndStuff 

	include Propane::Proxy

	#add buttons and dropdown list and toggle and textbox
	attr_accessor :size, :position, :border_thickness, :bg_color, :label, :label_color

	def initialize
		@size = [10, 10]
		@position = [0, 0]
		@border_thickness = 1
		@bg_color = color(100, 100, 210)
		@label = ""
		@label_color = color(255, 255, 255)
	end

	def draw_button
		#abstract
	end

	def in_button? (x, y)
		#abstract
	end

end

class Button < ButtonsAndStuff

	def initialize
		super
	end

	def draw_button
		stroke 0
		stroke_weight @border_thickness
		fill @bg_color
		rect @position[0], @position[1], @size[0], @size[1]
		unless @label == ""
			#draw text over rectangle
			text_align CENTER, CENTER
			fill @label_color
			text(@label, @position[0] + @size[0] / 2.0, @position[1] + @size[1] / 2.0)
		end
	end

	def in_button? (x, y)
		if (x.between?(@position[0], (@position[0] + @size[0]))) and (y.between?(@position[1], (@position[1] + @size[1])))
			return true
		else
			return false
		end
	end

end

class ToggleButton < ButtonsAndStuff

	attr_accessor :label_width, :value

	def initialize
		super
		@label_width = 50
		@value = false
	end

	def draw_button
		stroke 0
		stroke_weight @border_thickness

		if @label == ""
			l_size = 0
		else
			#write label to left of toggle
			l_size = @label_width
			fill @label_color
			text_align LEFT, CENTER
			text(@label, @position[0], @position[1] + @size[1] / 2.0)
		end

		#draw back ellipse
		if @value
			fill @bg_color
		else
			fill 10
		end
		ellipse_mode CORNER
		ellipse @position[0] + l_size, @position[1], @size[0], @size[1]

		#draw indicator ellipse
		if @value
			fill 230
			ellipse @position[0] + @size[1] + l_size, @position[1], @size[1], @size[1]
		else
			fill 150
			ellipse @position[0] + l_size, @position[1], @size[1], @size[1]
		end
	end

	def in_button? (x, y)
		if (x .between?(@position[0], (@position[0] + @size[0] + @label_width))) and (y.between?(@position[1], (@position[1] + @size[1])))
			return true
		else
			return false
		end
	end

	def toggle
		@value = !@value
	end

end

class NumberBox < ButtonsAndStuff

	attr_accessor :label_width, :value, :value_color, :active, :active_color, :valid, :invalid_color

	def initialize
		super
		@bg_color = color(255, 255, 255)
		@label_width = 30
		@value = "0"
		@value_color = color(0, 0, 0)
		@active = false
		@active_color = color(0, 160, 0)
		@valid = true
		@invalid_color = color(180, 0, 0)
	end

	def draw_button
		stroke 0
		stroke_weight @border_thickness

		if @label == ""
			l_size = 0
		else
			#write label to left of toggle
			l_size = @label_width
			fill @label_color
			text_align LEFT, CENTER
			text(@label, @position[0], @position[1] + size[1] / 2.0)
		end

		is_valid?

		if !@valid
			fill @invalid_color
		elsif @active
			fill @active_color
		else
			fill @bg_color
		end
		rect(@position[0] + @label_width, @position[1], @size[0], @size[1])

		fill @value_color
		text_align CENTER, CENTER
		text(@value, @position[0] + @label_width + (@size[0] / 2.0), @position[1] + (@size[1] / 2.0))
	end

	def in_button?(x, y)
		if (x .between?(@position[0], (@position[0] + @size[0] + @label_width))) and (y.between?(@position[1], (@position[1] + @size[1])))
			return true
		else
			return false
		end
	end

	#check if value is a number
	def is_valid?
		@valid = !!(@value.match(/^(\d)+$/))
		return @valid
	end

end

class JvGui < Propane::App

	def settings
		size 200, 400, P2D
	end

	def setup
		sketch_title "JV Launcher"

		window_x = (displayWidth / 2.0) - (width / 2.0)
		window_y = (displayHeight / 2.0) - (height / 2.0)
		surface.set_location window_x, window_y

		@fullscreen = true
		@window_width = 800
		@window_height = 800
		if File.file?('jv_settings.json')
			h = load_settings
			@fullscreen = h[:fullscreen]
			@window_width = h[:window_width]
			@window_height = h[:window_height]
		end

		create_gui
	end

	def draw
		background 160

		draw_buttons

		fill 0
		note = "For best results, set default recording device to stereo mix in sound control panel. (This is required for use with headphones.)"
		text_align CENTER, TOP
		text(note, 10, 10, 180, 400)
	end

	def mouse_clicked
		@w_box.active = false
		@h_box.active = false

		for button in @buttons
			if button.in_button?(mouse_x, mouse_y)

				case button.label
				when "Start Visualizer"
					save_settings

					background 0
					fill 240
					text_align CENTER, CENTER
					text "Running Visualizer...", 0, 0, width, height

					surface.stop_thread

					JuliaVisualizer.new
				when "Fullscreen"
					@fs_toggle.toggle
					if @fs_toggle.value
						@w_box.bg_color = color(80)
						@h_box.bg_color = color(80)
					else
						@w_box.bg_color = color(255)
						@h_box.bg_color = color(255)
					end
				when "Window Width:"
					@h_box.active = false
					@w_box.active = true
				when "Window Height:"
					@w_box.active = false
					@h_box.active = true
				when "Sound Check"
					save_settings

					background 0
					fill 240
					text_align CENTER, CENTER
					text "Running Sound Check...", 0, 0, width, height

					surface.stop_thread

					SoundCheck.new
				end

				return
			end
		end
	end

	def key_released
		#recognize numbers for numberbox
		if key.match(/^(\d)+$/)
			if @w_box.active
				@w_box.value = @w_box.value + key
			elsif @h_box.active
				@h_box.value = @h_box.value + key
			end
		elsif key_code == BACKSPACE
			if @w_box.active and @w_box.value.size > 0
				@w_box.value = @w_box.value[0...@w_box.value.size-1]
			elsif @h_box.active and @h_box.value.size > 0
				@h_box.value = @h_box.value[0...@h_box.value.size-1]
			end
		end
	end

	def create_gui
		@buttons = []

		@start_button = Button.new
		@start_button.position = [40, 300]
		@start_button.size = [120, 80]
		@start_button.border_thickness = 3
		@start_button.label = "Start Visualizer"
		@buttons << @start_button

		@fs_toggle = ToggleButton.new
		@fs_toggle.position = [25, 175]
		@fs_toggle.size = [60, 30]
		@fs_toggle.label = "Fullscreen"
		@fs_toggle.label_color = color(0)
		@fs_toggle.label_width = 90
		@fs_toggle.value = @fullscreen
		@buttons << @fs_toggle

		@w_box = NumberBox.new
		@w_box.position = [20, 215]
		@w_box.size = [60, 30]
		@w_box.bg_color = color(80) if @fullscreen
		@w_box.label = "Window Width:"
		@w_box.label_color = color(0)
		@w_box.label_width = 100
		@w_box.value = @window_width.to_s
		@buttons << @w_box

		@h_box = NumberBox.new
		@h_box.position = [20, 250]
		@h_box.size = [60, 30]
		@h_box.bg_color = color(80) if @fullscreen
		@h_box.label = "Window Height:"
		@h_box.label_color = color(0)
		@h_box.label_width = 100
		@h_box.value = @window_height.to_s
		@buttons << @h_box

		@check_button = Button.new
		@check_button.position = [50, 85]
		@check_button.size = [100, 60]
		@check_button.label = "Sound Check"
		@buttons << @check_button
	end

	def draw_buttons
		for button in @buttons
			button.draw_button
		end
	end

	def save_settings
		@fullscreen = @fs_toggle.value
		@window_width = @w_box.value if @w_box.is_valid?
		@window_height = @h_box.value if @h_box.is_valid?
		h = { fullscreen: @fullscreen, window_width: @window_width.to_i, window_height: @window_height.to_i }
		File.open('jv_settings.json', 'w'){ |f| f << JSON.pretty_generate(h) }
	end

	def load_settings
		JSON.parse(File.read('jv_settings.json'), :symbolize_names => true)
	end

end
