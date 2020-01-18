#jscottpilgrim
#J.P.Scott 2019

unless defined?(Propane::App)
	#need to change to current dir before loading propane to properly set SKETCH_ROOT
	Dir.chdir __dir__

	require "#{$src_path}/propane"
end

class SoundCheck < Propane::App

	# Load minim and import the packages we'll be using
	load_library "minim"
	import "ddf.minim"
	import "ddf.minim.analysis"

	def settings
		size 1280, 100
	end

	def setup
		sketch_title 'Sound Check'

		window_x = (displayWidth / 2.0) - (width / 2.0)
		window_y = (displayHeight / 2.0) - (height / 2.0)
		surface.set_location window_x, window_y

		background 10  # Pick a darker background color

		setup_sound
	end
  
	def draw
		draw_background
		update_sound
		animate_sound
	end
  
	def animate_sound
		i = 0
		@wid = width / (@scaled_ffts.size)
		numtimes = @scaled_ffts.size - 1

		for i in 0..numtimes
			@size = @scaled_ffts[i] * height
			@x = i * @wid

			if @beat.is_onset
			fill 0, 150, 0
			else
			fill 0, 0, 150
			end

			no_stroke
			rect(@x, height-@size, @wid, @size)

			i += 1
		end
	end

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
		@beat.set_sensitivity 50

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
		@beat.detect(@input.left)
	end

  def draw_background
    fill(0)
    rect 0, 0, width, height
  end
  
end
