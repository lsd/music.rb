# music.rb is symbolic musical computation for Ruby.
# Copyright (C) 2008 Jeremy Voorhis <jvoorhis@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

module Music
  
  def self.log2(x)
    Math.log(x) / Math.log(2)
  end 
  
  # Convert midi note numbers to hertz
  def self.mtof(pitch)
    440.0 * (2 ** ((pitch-69)/12))
  end
  
  # Convert hertz to midi note numbers
  def self.ftom(pitch)
    (69 + 12 * (log2(pitch / 440.0))).round
  end
  
  # Cast pitch value as a midi pitch number.
  def self.MidiPitch(pitch)
    case pitch
      when Integer then pitch 
      when Float then ftom(pitch)
      else raise ArgumentError, "Cannot cast #{pitch.class} to midi."
    end
  end
  
  # Cast pitch value as hertz.
  def self.Hertz(pitch)
    case pitch
      when Integer then mtof(pitch)
      when Float then pitch
      else raise ArgumentError, "Cannot cast #{pitch.class} to hertz."
    end
  end
  
  # Pluggable random number generator support. The default RNG may be
  # replaced, e.g. for deterministic unit testing.
  class RNG
    def rand; Kernel.rand end
  end
  def Music.rng; @rng end
  def Music.rng=(rng) @rng = rng end
  Music.rng = RNG.new
  
  def Music.rand; Music.rng.rand end
  
  class PitchClass
    include Comparable
    
    def self.for(pitch)
      PITCH_CLASSES.detect { |pc| pc.ord == pitch % 12 }
    end
    
    attr_reader :name, :ord
    
    def initialize(name, ord)
      @name, @ord = name, ord
    end
    
    def <=>(pc) ord <=> pc.ord end
    
    def to_s; name.to_s end
    
    # Western pitch classes. Accidental note names borrowed from LilyPond.
    PITCH_CLASSES = [
      new(:c, 0), new(:cis, 1),
      new(:d, 2), new(:dis, 3),
      new(:e, 4),
      new(:f, 5), new(:fis, 6),
      new(:g, 7), new(:gis, 8),
      new(:a, 9), new(:ais, 10),
      new(:b, 11)
    ] unless defined?(PITCH_CLASSES)
  end
  
  class MusicObject
    include Enumerable
    
    def duration; 0.0 end
    
    # Sequential composition.
    def seq(other)
      Seq.new(self, other)
    end
    
    # Parallel (concurrent) composition.
    def par(other)
      Par.new(self, other)
    end
    
    def each
      yield self
    end
    
    def each_with_offset(offset=0)
      yield self, offset
    end
    
    def perform(performer, context)
      raise NotImplementedError, "Subclass responsibility"
    end
  end
  
  class Seq < MusicObject
    attr_reader :left, :right
    
    def initialize(left, right)
      @left, @right = left, right
    end
    
    def ==(other)
      case other
        when Seq
          left == other.left && right == other.right
        else false
      end
    end
    
    def duration
      left.duration + right.duration
    end
    
    def each(&block)
      left.each(&block)
      block.call(self)
      right.each(&block)
    end
    
    def each_with_offset(offset=0, &block)
      left.each_with_offset(offset, &block)
      block.call(self, offset)
      right.each_with_offset(offset + left.duration, &block)
    end
    
    def perform(performer, context)
      performer.perform_seq(self, context)
    end
  end
  
  class Par < MusicObject
    attr_reader :top, :bottom
    
    def initialize(top, bottom)
      @top, @bottom = top, bottom
    end
    
    def ==(other)
      case other
        when Par
          top == other.top && bottom == other.bottom
        else false
      end
    end
    
    def duration
      [top.duration, bottom.duration].max
    end
    
    def each(&block)
      top.each(&block)
      block.call(self)
      bottom.each(&block)
    end
    
    def each_with_offset(offset=0, &block)
      top.each_with_offset(offset, &block)
      block.call(self, offset)
      bottom.each_with_offset(offset, &block)
    end
    
    def perform(performer, context)
      performer.perform_par(self, context)
    end
  end
  
  # Remain silent for the duration.
  class Silence < MusicObject
    attr :duration
    
    def initialize(duration)
      @duration = duration
    end
    
    def ==(other)
      case other
        when Silence: @duration == other.duration
        else false
      end
    end
    
    def perform(performer, context)
      performer.perform_silence(self, context)
    end
  end
  Rest = Silence unless defined?(Rest) # Type alias for convenience
  
  # A note has a steady pitch and a duration.
  class Note < MusicObject
    attr_reader :pitch, :duration, :effort
    
    def initialize(pitch, duration, effort)
      @pitch, @duration, @effort = pitch, duration, effort
    end
    
    def ==(other)
      case other
        when Note
          [@pitch, @duration, @effort] == [other.pitch, other.duration, other.effort]
        else false
      end
    end
    
    def pitch_class
      PitchClass.for(@pitch)
    end
    
    def transpose(hsteps, dur=self.duration, eff=self.effort)
      self.class.new(pitch+hsteps, dur, eff)
    end
    
    def perform(performer, context)
      performer.perform_note(self, context)
    end
  end
  
  class MidiTime
    attr :resolution
    
    def initialize(res)
      @resolution = res
    end
    
    def ppqn(val)
      case val
        when Numeric
          (val * resolution).round.to_i
        else
          raise ArgumentError, "Cannot convert #{val}:#{val.class} to midi time."
      end
    end
  end
  
  require 'smf'
  
  # Standard Midi File performance.
  class SMFTranscription
    include SMF
    
    def initialize(options={})
      @time = MidiTime.new(options.fetch(:resolution, 480))
      @seq  = Sequence.new(1, @time.resolution)
    end
    
    def write(score, options={})
      @track = Track.new
      seq_name = options.fetch(:name, gen_seq_name)
      @track << SequenceName.new(0, seq_name)
      @channel = options.fetch(:channel, 1)
      
      score.each_with_offset do |obj, offset|
        obj.perform(self, offset)
      end
      
      @seq << @track
      self
    end
    
    def save(basename)
      filename = basename + '.mid'
      @seq.save(filename)
    end
    
    def perform_silence(silence, context) end
    
    def perform_seq(seq, context) end
    
    def perform_par(par, context) end
    
    def perform_note(note, offset)
      attack  = @time.ppqn(offset)
      release = attack + @time.ppqn(offset)
      @track << NoteOn.new(attack, @channel, Music.MidiPitch(note.pitch), note.effort)
      @track << NoteOff.new(release, @channel, Music.MidiPitch(note.pitch), note.effort)
    end
    
    protected
      def gen_seq_name
        @seqn ||= 0
        @seqn  += 1
        "Untitled #@seqn"
      end
  end
end
