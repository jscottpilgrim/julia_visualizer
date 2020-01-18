#jscottpilgrim
#J.P.Scott 2019

unless defined?(Propane::App)
	#need to change to current dir before loading propane to properly set SKETCH_ROOT
	Dir.chdir __dir__

	require "#{$src_path}/propane"
end

require "#{$src_path}/json" unless defined?(JSON)

require 'thread'
require 'matrix'

class JuliaVisualizer < Propane::App

	# Load minim and import the packages
	load_library "minim"
	import "ddf.minim"
	import "ddf.minim.analysis"

	def settings
		#load settings from json file
		@fullscreen = true
		@window_width = 800
		@window_height = 800
		if File.file?('jv_settings.json')
			h = JSON.parse(File.read('jv_settings.json'), :symbolize_names => true)
			@fullscreen = h[:fullscreen]
			@window_width = h[:window_width]
			@window_height = h[:window_height]
		end

		if @fullscreen
			full_screen P2D, SPAN #span fixes fullscreen on windows for some unknown reason
			@width = displayWidth
			@height = displayHeight
		else
			size @window_width, @window_height, P2D
			@width = width
			@height = height
		end
		
		@frame_rate = 20

		@center = [0.0, 0.0]

		@range_default = 2.5

		@zoom_default = @range_default / ([@width, @height].min)
		@zoom = @zoom_default

		@range = @range_default

		#@julia_param = [0.0, 0.0]
		@julia_param = [-0.4265354142468627, 0.6555118856295816]
		#@julia_param = [0.1994, -0.613]

		@exponent = 6
		@min_exponent = 2
		@max_exponent = 11

		@enable_random_exponent = true
		@random_exponent_chance = 0.05

		#low:
		@iterations = 300
		@escape_radius_square = 100.0
		#medium:
		#@iterations = 500
		#@escape_radius_square = 400.0
		#high:
		#@iterations = 800
		#@escape_radius_square = 784.0
		#very high
		#kinda breaks higher exponents
		#@iterations = 1000
		#@escape_radius_square = 1024.0

		#settings for random julia seed generation
		@seed_gen_range = (-2.0..2.0)
		@seed_de_min = 0.2
		@seed_de_max = 0.6

		#settings for random zoom point generation
		#@zoom_point_range = (-2.0..2.0)
		@zoom_de_min = 0.0
		@zoom_de_max = 0.1

		@enable_beat_zoom = true
		@zoom_chance = 0.07
		@zoom_in_depth = 0.0000004
		@zoom_out_depth = @zoom_default
		@zoom_divisor = 15
		@zoom_move_duration = 40

		#length of julia loop in frames
		@loop_length = 8

		@color_palette = [[0.8, 0.0, 0.0],
					[1.0, 0.0, 0.0],
					[1.0, 0.0, 0.0],
					[0.6, 0.0, 0.4],
					[0.2, 0.0, 0.8],
					[0.0, 0.0, 1.0],
					[0.0, 0.4, 0.6],
					[0.0, 0.8, 0.2],
					[0.2, 0.8, 0.2],
					[0.4, 0.4, 0.4]]

		@colors = @color_palette.clone

		@rotating_colors = true
		@color_rotate_chance = 0.08

		#reset max sound settings every x updates, 0 to never reset
		@sound_reset_thresh = 12000
		@beat_history_count = 120

		#enable or disable effects on beat
		@beat_bounce = true

		#show details in top left
		#toggle with d
		@show_details = false
	end

	def setup
		sketch_title 'JuliaVisualizer'

		if !@fullscreen
			surface.set_location 50, 50
		end

		frame_rate @frame_rate
		@frames_per_min = @frame_rate * 60

		#initialize some parameters
		@mode = 'julia'

		@julia_loop_begin = [0, 0]
		@julia_loop_end = [0, 0]
		@loop_time = 0

		@exponent_transition = 0
		@zooming = 0
		@zoom_move_time = 0
		@old_center = @center
		@new_center = @center
		@center_adjust_flag = 0
		@zoom_in_step_count = 0
		@zoom_out_step_count = 0

		@color_offset = rand(0...@colors.size)

		#load shaders
		@julia_shader = load_shader data_path('jvShader.glsl')
		@julia_shader.set 'resolution', @width.to_f, @height.to_f

		#normalize colors
		for i in 0...@colors.size
			v = Vector.elements(@colors[i], copy = true)
			v = v.normalize
			@colors[i] = v.to_a
		end

		#initialize sound visualizer components
		setup_sound

		#set main thread to higher priority
		Thread.current.priority = 1

		#start second thread for calculating next julia seed
		@seed_thread = Thread.new{ @seed_thread["seed"] = gen_julia_seed }

		#start with black background
		background 0
	end

	# *******************
	#*music visualization*
	# *******************

	def setup_sound
		# Create Minim object
		@minim = Minim.new(self)
		# Lets Minim grab sound data from mic/recording
		# set recording device to sound/stereo monitor in linux, sound/stereo mix in windows
		@input = @minim.get_line_in

		# Gets FFT values from sound data
		@fft = FFT.new(@input.left.size, 44100)
		# beat detector object
		@beat = BeatDetect.new
		#@beat.detect_mode 0
		@beat.set_sensitivity 50
		@beats = []
		@bpm = 0.0

		# Set an array of frequencies to get FFT data for 
		#   -- these numbers from VLC's equalizer
		@freqs = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]

		# Create arrays to store the current FFT values, 
		#   previous FFT values, highest FFT values seen, 
		#   and scaled/normalized FFT values (which are easier to work with)
		@current_ffts   = Array.new(@freqs.size, 0.001)
		@previous_ffts  = Array.new(@freqs.size, 0.001)
		@max_ffts       = Array.new(@freqs.size, 2.0)
		@scaled_ffts    = Array.new(@freqs.size, 0.001)

		#adjust the "smoothness" factor of sound responsiveness
		@fft_smoothing = 0.6

		#count times sound has updated (should be every frame)
		@sound_update_count = 0
	end
  
	def update_sound
		@fft.forward @input.left

		@previous_ffts = @current_ffts
	    
		# Iterate over the frequencies of interest and get FFT values
		@freqs.each_with_index do |freq, i|
			# The FFT value for this frequency
			new_fft = @fft.get_freq(freq)

			# Set it as the frequncy max if it's larger than the previous max
			#@max_ffts[i] = new_fft if new_fft > @max_ffts[i]
			if new_fft > @max_ffts[i]
				if @max_ffts[i] < 25
					@max_ffts[i] = new_fft * 0.75
				else
					@max_ffts[i] = (@max_ffts[i] + new_fft) / 2
				end
			end

			# Use "smoothness" factor and the previous FFT to set a current FFT value 
			@current_ffts[i] = ((1 - @fft_smoothing) * new_fft) + (@fft_smoothing * @previous_ffts[i])

			# Set a scaled/normalized FFT value that will be 
			#   easier to work with for this frequency
			divisor = [@current_ffts[i], (@max_ffts[i] * 0.5)].max
			@scaled_ffts[i] = @current_ffts[i] / divisor
		end

		# Check if there's a beat, will be stored in @beat.is_onset
		update_beats

		#count updates
		unless @sound_reset_thresh == 0
			@sound_update_count += 1
			if @sound_update_count > @sound_reset_thresh
				@max_ffts = Array.new(@freqs.size, 0.001)
				@sound_update_count = 0
			end
		end
	end

	def update_beats
		# Check if there's a beat, will be stored in @beat.is_onset
		@beat.detect(@input.left)

		update_bpm @beat.is_onset
	end

	def update_bpm(beat)
		if beat
			@beats << 1
		else
			@beats << 0
		end

		over = @beats.size - @beat_history_count
		if over > 0
			@beats = @beats[over...@beats.size]
		end

		total = 0
		for i in @beats
			total += i
		end

		@bpm = total * (@frames_per_min / @beat_history_count)
	end

	def update_colors
		for i in 0...@colors.size
			j = (i - @color_offset).abs
			r = @color_palette[j][0] * @scaled_ffts[j]
			g = @color_palette[j][1] * @scaled_ffts[j]
			b = @color_palette[j][2] * @scaled_ffts[j]
			@colors[i] = [r, g, b]
		end
	end

	# *****************
	#*fractal rendering*
	# *****************

	def julia_draw
		#set colors
		@julia_shader.set 'color0', @colors[0][0], @colors[0][1], @colors[0][2]
		@julia_shader.set 'color1', @colors[1][0], @colors[1][1], @colors[1][2]
		@julia_shader.set 'color2', @colors[2][0], @colors[2][1], @colors[2][2]
		@julia_shader.set 'color3', @colors[3][0], @colors[3][1], @colors[3][2]
		@julia_shader.set 'color4', @colors[4][0], @colors[4][1], @colors[4][2]
		@julia_shader.set 'color5', @colors[5][0], @colors[5][1], @colors[5][2]
		@julia_shader.set 'color6', @colors[6][0], @colors[6][1], @colors[6][2]
		@julia_shader.set 'color7', @colors[7][0], @colors[7][1], @colors[7][2]
		@julia_shader.set 'color8', @colors[8][0], @colors[8][1], @colors[8][2]
		@julia_shader.set 'color9', @colors[9][0], @colors[9][1], @colors[9][2]

		@julia_shader.set 'center', @center[0], @center[1]
		@julia_shader.set 'zoom', @zoom
		@julia_shader.set 'juliaParam', @julia_param[0], @julia_param[1]
		@julia_shader.set 'exponent', @exponent
		@julia_shader.set 'maxIterations', @iterations
		@julia_shader.set 'escapeRadius', @escape_radius_square

		shader @julia_shader

		rect 0, 0, @width, @height

		reset_shader
	end

	def julia_loop_draw
		#calculate julia param with interpolation from julia_loop_begin to julia_loop_end using loop_time
		real_dif = @julia_loop_end[0] - @julia_loop_begin[0]
		imag_dif = @julia_loop_end[1] - @julia_loop_begin[1]

		m = 1.0 * @loop_time / @loop_length
		real_offset = m * real_dif
		imag_offset = m * imag_dif

		r = @julia_loop_begin[0] + real_offset
		i = @julia_loop_begin[1] + imag_offset
		@julia_param = [r, i]

		#increment time for next frame
		@loop_time += 1

		#reset loop time when cycle is complete
		if @loop_time > @loop_length
			#@loop_time = 0
			#@julia_param = @julia_loop_end

			if @exponent_transition == 0
				@loop_time = 0
				#being slightly off the projection can lead to some interesting complexities, I believe, so for now this correction is off
				#@julia_param = @julia_loop_end
				@mode = 'julia'
			else
				if @exponent_transition == 1
					r = rand(@min_exponent..@max_exponent)
					@exponent = r
					@exponent_transition = 2
					julia_seed_transition
				else
					@loop_length = @loop_length * 2
					@exponent_transition = 0
					@loop_time = 0
					#being slightly off the projection can lead to some interesting complexities, I believe, so for now this correction is off
					#@julia_param = @julia_loop_end
					@mode = 'julia'
				end
			end
			
		end

		julia_draw
	end

	def mandelbrot_distance_estimate(real, imag)
		c = Complex(real, imag)
		z = Complex(0.0, 0.0)
		dz = Complex(0.0, 0.0)
		escape = false

		for i in 0...@iterations
			#dz = 2 * z * z' + 1
			#dz = 3 * z * z * dz + 1
			n = z.clone
			countdown = @exponent - 2
			while countdown > 0
				n = n * z
				countdown = countdown - 1
			end
			dz = @exponent * n * dz + 1

			#mandelbrot function
			#z = c + (z * z)
			#z = c + (z * z * z)
			n = n * z
			z = c + n

			#escape radius
			if ((z.real * z.real) + (z.imag * z.imag)) > @escape_radius_square
				escape = true
				break
			end
		end

		#initialize distance estimate to 0, within M
		d = 0.0

		#calculate distance estimate if z escapes, or is not within M
		if escape
			#d(c) = (|z|*log|z|)/|z'|
			d = z.abs
			d *= Math.log(d)
			d /= dz.abs

			#scale distance estimate and limit to range 0..1
			d = ((4 * d) ** 0.1).clamp(0, 1)
		end

		return d
	end

	def julia_distance_estimate(real, imag)
		c = Complex(@julia_param[0], @julia_param[1])
		z = Complex(real, imag)
		dz = Complex(1.0, 0.0)
		escape = false

		for i in 0...@iterations
			#dz = 2 * z * z'
			#dz = 3 * z * z * dz
			n = z.clone
			countdown = @exponent - 2
			while countdown > 0
				n = n * z
				countdown = countdown - 1
			end
			dz = @exponent * n * dz

			#mandelbrot function
			#z = c + (z * z)
			#z = c + (z * z * z)
			n = n * z
			z = c + n

			#escape radius
			if ((z.real * z.real) + (z.imag * z.imag)) > @escape_radius_square
				escape = true
				break
			end
		end

		#initialize distance estimate to 0, within M
		d = 0.0

		#calculate distance estimate if z escapes, or is not within M
		if escape
			#d(c) = (|z|*log|z|)/|z'|
			d = z.abs
			d *= Math.log(d)
			d /= dz.abs

			#scale distance estimate and limit to range 0..1
			d = ((4 * d) ** 0.1).clamp(0, 1)
		end

		return d
	end

	def gen_julia_seed
		while true
			#get point within ranges
			r = rand(@seed_gen_range)
			i = rand(@seed_gen_range)

			#calc distance estimate of point
			de = mandelbrot_distance_estimate(r, i)

			if ((de > @seed_de_min) and (de <= @seed_de_max))
				break
			end
		end

		return [r, i]
	end

	def gen_zoom_point
		attempts = 0
		while true
			attempts += 1

			#get point within ranges
			r = rand(0.25..1.5)
			sign = rand
			if sign < 0.5
				r *= -1
			end
			i = rand(0.25..1.5)
			sign = rand
			if sign < 0.5
				i *= -1
			end

			#calc distance estimate of point
			de = julia_distance_estimate(r, i)

			if ((de > @zoom_de_min) and (de <= @zoom_de_max))
				#puts "Found zoom point in #{attempts} attempts.\nDE: #{de}\nZoom Point: #{[r, i]}"
				break
			elsif attempts > 10000
				#puts 'Failed to find zoom point.'
				return false
			end
		end

		return [r, i]
	end

	def julia_seed_transition
		#begin transition to new julia set using randomly generated seed, if one is available
		if @seed_thread.status == false
			s = @seed_thread["seed"]
			if s
				julia_seed_transition_to(s)
			end

			@seed_thread["seed"] = gen_julia_seed
		end
	end

	def julia_seed_transition_to(next_seed)
		#begin transition to julia set with given seed
		@julia_loop_begin = @julia_param
		@julia_loop_end = next_seed
		@mode = 'julia_loop'
		@loop_time = 0
	end

	def update_zoom
		# Four values for @zooming: 0, 1, 2, 3
		# 0: not zooming
		# 1: zooming in
		# 2: zooming out
		# 3: waiting for julia transition to complete before beginning zoom
		unless @zooming == 0
			if @zooming == 3
				if @mode == 'julia'
					@zooming = 1
					c = gen_zoom_point
					if c == false
						@zooming = 0
						return
					end
					@center_adjust_flag = 0
					@new_center = c
					@old_center = @center
					@zoom_move_time = 0
					@zoom_in_step_count = 0
					@zoom_out_step_count = 0
				end
			elsif @zooming == 1
				@range -= @range / @zoom_divisor
				@zoom = @range / ([@width, @height].min)
				@zoom_in_step_count += 1

				if @zoom_move_time < @zoom_move_duration
					#smooth movement to zoom center
					# y = 1.5 + (-1.5 / (1 + 2 * x))
					x = (1.0 * @zoom_move_time + 1) / @zoom_move_duration
					step_multiplier = 1.5 + (-1.5 / (1 + 2 * x))
					move_step = [(@new_center[0] - @old_center[0]) * step_multiplier, (@new_center[1] - @old_center[1]) * step_multiplier]
					@center = [@old_center[0] + move_step[0], @old_center[1] + move_step[1]]
					@zoom_move_time += 1
				elsif @center_adjust_flag == 0
					@center = @new_center
					@center_adjust_flag = 1
				end

				if @zoom <= @zoom_in_depth
					#stop, zoom back out, or otherwise transition
					@zooming = 2
					@new_center = [0.0, 0.0]
					@old_center = @center
					@zoom_move_time = 0
				end
			elsif @zooming == 2
				if @zoom <= @zoom_out_depth
					@range += @range / @zoom_divisor
					@zoom = @range / ([@width, @height].min)
					@zoom_out_step_count += 1
					if (@zoom_in_step_count - @zoom_out_step_count <= @zoom_move_duration) and (@zoom_move_time < @zoom_move_duration)
						#smooth movement to zoom center
						# y = 844341.9 + (-844341.9 / (1 + ((x / 443.9) ** 2.25)))
						x = (1.0 * @zoom_move_time + 1) / @zoom_move_duration
						step_multiplier = 844341.9 + (-844341.9 / (1 + ((x / 443.9) ** 2.25)))
						move_step = [(@new_center[0] - @old_center[0]) * step_multiplier, (@new_center[1] - @old_center[1]) * step_multiplier]
						@center = [@old_center[0] + move_step[0], @old_center[1] + move_step[1]]
						@zoom_move_time += 1
					elsif @zoom_move_time >= @zoom_move_duration
						@center = [0.0, 0.0]
					end
				else
					#stop or otherwise transition
					if @zoom_move_time < @zoom_move_duration
						#smooth movement to zoom center
						# y = 844341.9 + (-844341.9 / (1 + ((x / 443.9) ** 2.25)))
						x = (1.0 * @zoom_move_time + 1) / @zoom_move_duration
						step_multiplier = 844341.9 + (-844341.9 / (1 + ((x / 443.9) ** 2.25)))
						move_step = [(@new_center[0] - @old_center[0]) * step_multiplier, (@new_center[1] - @old_center[1]) * step_multiplier]
						@center = [@old_center[0] + move_step[0], @old_center[1] + move_step[1]]
						@zoom_move_time += 1
					else
						@center = [0.0, 0.0]
						@zooming = 0
					end
				end
			end
		end
	end

	# *********
	#*main loop*
	# *********

	def draw
		update_sound
		update_colors

		if @beat.is_onset

			if @beat_bounce
				if @exponent_transition == 0 and @zooming == 0
					r = rand

					#random chance to change exponent if enabled
					if @enable_random_exponent and r <= @random_exponent_chance
							# Three values for @exponent transition: 0, 1, 2
							# 0: off
							# 1: transition to [0.0, 0.0]
							# 2: new exponent and transition to new seed
							# @loop_length is divided by 2 so that stages 1 and 2 combined will take the same length of time as a normal transition
								@exponent_transition = 1
								@loop_length = @loop_length / 2.0
								julia_seed_transition_to([0.0, 0.0])
					#random chance to zoom
					elsif @enable_beat_zoom and (r >= (1.0 - @zoom_chance))
						@zooming = 3
					#if no special events occur, change julia parameter
					else
						if @rotating_colors and (r >= 0.5 and r <= (0.5 + @color_rotate_chance))
							o = rand(0...@colors.size)
							@color_offset = o
						end
						julia_seed_transition
					end
				end
			end

		end

		if @zooming != 0
			update_zoom
		end

		case @mode
		when 'julia'
			julia_draw
		when 'julia_loop'
			julia_loop_draw
		end

		#show fractal details if enabled
		if @show_details
			fill 0
			rect 8, 8, 420, 115

			fill 240
			text_align LEFT, TOP
			fps = frame_rate
			text "FPS: #{fps}", 10, 10
			text "Center: #{@center}", 10, 25
			text "Zoom: #{@zoom}", 10, 40
			text "Range: #{@range}", 10, 55
			text "Julia Seed: #{@julia_param}", 10, 70
			text "Exponent: #{@exponent}", 10, 85
			pt = @beat_bounce ? "Active" : "Paused"
			text "Beat Effects: #{pt}", 10, 100
		end

		#**
		#main loop controls

		if !@beat_bounce and key_pressed?
			#pan with arrow keys
			#zoom in with z, zoom out with x
			if key == CODED
				if key_code == UP and @center[1] < 3.0
					@center[1] += @range / 60
				elsif key_code == DOWN and @center[1] > -3.0
					@center[1] -= @range / 60
				elsif key_code == LEFT and @center[0] > -3.0
					@center[0] -= @range / 60
				elsif key_code == RIGHT and @center[0] < 3.0
					@center[0] += @range / 60
				end
			else
				if (key == 'z' or key == 'Z') and (@range > 0.00005)
					@range -= @range / @zoom_divisor
					@zoom = @range / ([@width, @height].min)
				elsif (key == 'x' or key =='X') and (@range < 10)
					@range += @range / @zoom_divisor
					@zoom = @range / ([@width, @height].min)
				end
			end
		end
	end

	# ********
	#*controls*
	# ********

	def reset
		#reset all parameters
		@center = [0.0, 0.0]
		@range = @range_default
		@zoom = @zoom_default
		@mode = 'julia'
		@julia_loop_begin = [0, 0]
		@julia_loop_end = [0, 0]
		@loop_time = 0
		@exponent_transition = 0
		@zooming = 0
		@zoom_move_time = 0
		@old_center = @center
		@new_center = @center
		@center_adjust_flag = 0
		@zoom_in_step_count = 0
		@zoom_out_step_count = 0
		#reset sound history
		@max_ffts = Array.new(@freqs.size, 0.001)
		@sound_update_count = 0
		#kill and reset sub threads
		if @seed_thread.alive? then @seed_thread.exit end
		@seed_thread = Thread.new{ @seed_thread["seed"] = gen_julia_seed }
		@seed_thread.priority = 0
	end

	def key_released
		if key == 'r' or key == 'R'
			#reset program with r key
			reset
		elsif key == 'p' or key == 'P'
			#play or pause beat effects
			@beat_bounce = !@beat_bounce
		elsif key == ',' or key == '<'
			if @exponent > 2
				@exponent = @exponent - 1
			end
			puts "Exponent: #{@exponent}"
		elsif key == '.' or key == '>'
			@exponent = @exponent + 1
			puts "Exponent: #{@exponent}"
		elsif key == 'd' or key == 'D'
			#turn on or off on screen parameters
			@show_details = !@show_details

			#clear details if turned off
			if !@show_details
				fill 0
				rect 8, 8, 420, 115
			end
		elsif key == 'y' or key == 'Y'
			#print state
			fps = frame_rate
			puts "FPS: #{fps}"
			puts "BPM: #{@bpm}"
			puts "Mode: #{@mode}"
			puts "Center: #{@center}"
			puts "Zoom: #{@zoom}"
			puts "Range: #{@range}"
			puts "Zooming: #{@zooming}"
			puts "Julia Seed: #{@julia_param}"
			puts "Exponent: #{@exponent}"
			puts "Current Seed DE: #{mandelbrot_distance_estimate(@julia_param[0], @julia_param[1])}"
			if @mode == 'julia_loop'
				puts "Julia Seed Start: #{@julia_loop_begin}"
				puts "Julia Seed End: #{@julia_loop_end}"
				puts "Loop Time: #{@loop_time}"
			end
		end
	end

end

#JuliaVisualizer.new unless $gui_launch