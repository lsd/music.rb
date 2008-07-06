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

class Object
  def blank?; false end
end

class Array
  def rand
    self[(Music.rand * size).floor]
  end
  
  def blank?; size.zero? end
end

class Hash
  def blank?; size.zero? end
end

class NilClass
  def blank?; true end
end

class False
  def blank?; true end
end

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
    ]
  end
  
  # A MusicStructure is a computation that produces a Surface. Individual
  # MusicStructure instances are compositional building blocks, responsible for
  # both generating individual events and determining the future of the
  # performance.
  class MusicStructure
    # Sequencing operator: the structure on the rhs will be activated when the
    # current structure has finished.
    def >>(structure)
      @next = structure
    end
    
    # Predicate for whether a future event has been sequenced.
    def has_next?
      !@next.nil?
    end
    
    # Return the next MusicStructure in the sequence, if any.
    def next_structure; @next end
    
    # Return the next MusicEvent in its activated state.
    def next
      @next.activate if @next
    end
    
    # Activate the structure before generating an event.
    def activate; self end
    
    # Generate a MusicEvent. This should only be called after preparing the
    # structure. This is usually taken care of for you by MusicStructure#next.
    def generate(surface)
      raise NotImplementedError, "Subclass responsibility"
    end
    
    # Generate a musical surface from the current structure.
    def surface
      Surface.new(self)
    end
    
    # Iterate through the structures reachable from the current structure.
    def structure
      StructureIterator.new(self)
    end
        
    def include?(structure)
      self == structure || has_next? && next_structure.include?(structure)
    end
    
    def splice(structure)
      if has_next?
        next_structure.splice(structure)
      else
        self >> structure
      end
    end
    
    # Convenient access to the RNG
    def rand
      Music::rng.rand
    end
  end
  
  class MusicEvent
    # Call +MusicEvent#perform+ with a performance visitor.
    def perform(performance)
      raise NotImplementedError, "Subclass responsibility"
    end
    
    def blank?; @duration.zero? end
  end
  
  class Surface < Array
    def initialize(head)
      @head = head
      generate
    end
    
    def <<(ev)
      super unless ev.blank?
    end
    
    private
      def generate
        return if @head.nil?
        cursor = @head.activate
        begin
          self << cursor.generate(self)
        end while cursor = cursor.next
      end
  end
  
  class StructureIterator
    include Enumerable
    
    def initialize(head)
      @head = head
    end
    
    def first; @head end
    
    def last; map { |s| s }[-1] end
    
    def include?(structure)
      detect { |s| s == structure } ? true : false
    end
    
    def each
      return if @head.nil?
      cursor = @head
      
      begin
        yield cursor
      end while cursor = cursor.next_structure
    end
  end
  
  # Remain silent for the duration.
  class Silence < MusicEvent
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
    
    def perform(performance)
      performance.play_silence(self)
    end
  end
  
  # A note has a steady pitch and a duration.
  class Note < MusicEvent
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
    
    def perform(performance)
      performance.play_note(self)
    end
    
    def pitch_class
      PitchClass.for(@pitch)
    end
    
    def transpose(hsteps, dur=self.duration, eff=self.effort)
      self.class.new(pitch+hsteps, dur, eff)
    end
  end
  
  class Chord < MusicEvent
    attr_reader :pitches, :duration, :effort
    
    def initialize(pitches, duration, effort)
      @pitches, @duration, @effort = pitches, duration, effort
    end
    
    def ==(other)
      case other
        when Chord
          [@pitches, @duration, @effort] == [other.pitches, other.duration, other.effort]
        else false
      end
    end
    
    # Iterate over each pitch in the chord, with its corresponding effort value.
    def pitch_with_effort
      e = Array(effort)
      @pitches.each_with_index { |p, i| yield([p, e[i % e.size]]) }
    end
    
    def perform(performance)
      performance.play_chord(self)
    end
    
    def pitch_class
      @pitches.map { |pitch| PitchClass.for(pitch) }
    end
    
    def transpose(hsteps, dur=self.duration, eff=self.effort)
      self.class.new(pitches.map { |p| p+hsteps }, dur, eff)
    end
  end
  
  class Constant < MusicStructure
    def initialize(event)
      @event = event
    end
    
    def generate(surface) @event.dup end
  end
  
  class Interval < MusicStructure
    def initialize(*args) # pitch, duration, effort
      @args = args
    end
    
    def generate(surface)
      # Scan backwards for a transposable event.
      if ev = surface.to_a.reverse.detect { |e| e.respond_to?(:transpose) }
        ev.transpose(*@args)
      else
        Silence.new(0)
      end
    end
  end
  
  # Choose randomly from given structures, then proceed.
  class Choice < MusicStructure
    def initialize(*choices)
      @choices = choices
    end
    
    def activate
      choice = @choices.rand
      unless choice.has_next?
        choice = choice.dup
        choice >> @next
      end
      choice.activate
    end
    
    def include?(structure)
      self == structure || @choices.any? { |c| c.include?(structure) } || (has_next? && next_structure.include?(structure))
    end
    
    def splice(structure)
      @choices.each { |c| c.splice(structure) unless c.include?(structure) }
    end
  end
  
  class Cycle < MusicStructure
    def initialize(*structures)
      @structures, @pos = structures, structures.size-1
    end
    
    def activate
      structure = @structures[next_index]
      if has_next?
        structure.splice(@next) unless structure.include?(@next)
      end
      structure.activate
    end
    
    def include?(structure)
      self == structure || @structures.any? { |c| c.include?(structure) } || (has_next? && next_structure.include?(structure))
    end
    
    def splice(structure)
      @structures.each { |c| c.splice(structure) unless c.include?(structure) }
    end
    
    private
      def next_index
        @pos = (@pos + 1) % @structures.size
      end
  end
  
  # Repeats the given MusicStructure a specified number of times, before
  # proceeding.
  class Repeat < MusicStructure
    def initialize(repititions, structure)
      @repititions, @structure = repititions, structure
    end
    
    def activate
      if @repititions.zero?
        @next.activate if has_next?
      else
        @repititions -= 1
        @structure.splice(self) unless @structure.include?(self)
        @structure.activate
      end
    end
    
    def include?(structure)
      self == structure || @structure.include?(structure) || (has_next? && next_structure.include?(structure))
    end
    
    def splice(structure)
      @structure.splice(structure) unless @structure.include?(structure)
    end
  end
  
  # Lifts a Proc into a MusicStructure.
  class Fun < MusicStructure
    def initialize(&proc)
      @proc = proc
    end
    
    def generate(surface)
      @proc[surface]
    end
  end
  
  ::Kernel.module_eval do
    
    def silence(duration=1)
      Constant.new(Silence.new(duration))
    end
    alias :rest :silence
    
    def note(pitch, duration=1, effort=64)
      Constant.new(Note.new(pitch, duration, effort))
    end
    
    def chord(pitches, duration=1, effort=64)
      Constant.new(Chord.new(pitches, duration, effort))
    end
    
    def interval(*args)
      Interval.new(*args)
    end
    
    def choice(*structures)
      Choice.new(*structures)
    end
    
    def cycle(*structures)
      Cycle.new(*structures)
    end
    
    def repeat(rep, structure)
      Repeat.new(rep, structure)
    end
    
    def fun(&proc)
      Fun.new(&proc)
    end
    
    def dupe; Dup.new end
    
    def seq(*structures)
      hd, *tl = structures
      tl.inject(hd) { |s, k| s.structure.last >> k }
      hd
    end    
  end
  
  class MidiTime
    attr :resolution
    
    def initialize(res)
      @resolution = res
    end
    
    def divisions(val)
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
      @time = MidiTime.new(options.fetch(:resolution, 96))
      @seq  = Sequence.new(1, @time.resolution)
    end
    
    def perform(surface, options={})
      @track = Track.new
      seq_name = options.fetch(:name, gen_seq_name)
      @track << SequenceName.new(0, seq_name)
      @channel = options.fetch(:channel, 1)
      @offset = 0
      surface.each { |event| event.perform(self) }
      @seq << @track
      self
    end
    
    def save(basename)
      filename = basename + '.mid'
      @seq.save(filename)
    end
    
    def play_silence(ev)
      advance(ev)
    end
    
    def play_note(ev)
      @track << NoteOn.new(@offset, @channel, Music.MidiPitch(ev.pitch), ev.effort)
      advance(ev)
      @track << NoteOff.new(@offset, @channel, Music.MidiPitch(ev.pitch), ev.effort)
    end
    
    def play_chord(ev)
      ev.pitch_with_effort do |pitch, effort|
        @track << NoteOn.new(@offset, @channel, Music.MidiPitch(pitch), effort)
      end
      advance(ev)
      ev.pitch_with_effort do |pitch, effort|
        @track << NoteOff.new(@offset, @channel, Music.MidiPitch(pitch), effort)
      end
    end
    
    private
      def advance(ev)
        @offset += @time.divisions(ev.duration)
      end
      
      def gen_seq_name
        @seqn ||= 0
        @seqn  += 1
        "Untitled #@seqn"
      end
  end
end

if __FILE__ == $0
  include Music
  
  def example
    (lbl=note(60)) >>
      fun { |s| Note.new(62, 1, 64) } >>
      cycle(interval(2), interval(9)) >>
      choice(lbl,
        repeat(3, lbl) >>
        chord([60, 67, 72], 2, [127, 72, 96]))
    lbl
  end
  
  sur = example.surface
  puts sur.map { |note| 
    Music::Chord === note ? "<#{note.pitch_class * ', '}>" : note.pitch_class
  } * ', '
  
  Music::SMFTranscription.new.perform(sur, :name => "Example").save('example')
end
