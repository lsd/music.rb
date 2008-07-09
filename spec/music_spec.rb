require File.join( File.dirname(__FILE__), 'spec_helper')
require 'rational'

describe Music do
  
  describe "functions of pitch" do
    it "mtof should convert midi pitch numbers to Hz" do
      { 60  => 261,
        69  => 440,
        0   => 8,
        127 => 12543 }.each do |m, hz|
        Music.mtof(m).floor.should == hz
      end
    end
    
    it "mtof should be the inverse of ftom" do
      (0..127).each do |m|
        Music.ftom(Music.mtof(m)).should == m
      end
    end
    
    it "should convert any Integer or Float to a midi pitch" do
      { 69    => 69,
        440.0 => 69 }.each do |arg, m|
        Music.MidiPitch(arg).should == m
      end
      
      proc { Music.MidiPitch(1.quo(1)) }.should raise_error(ArgumentError)
    end
    
    it "should convert any Integer or Float to Hz" do
      { 69    => 440.0,
        440.0 => 440.0 }.each do |arg, hz|
        Music.Hertz(arg).should == hz
      end
      
      proc { Music.Hertz(1.quo(1)) }.should raise_error(ArgumentError)
    end
  end
  
  describe "helper functions" do
    it "should construct a note" do
      note(60).should      == Note.new(60,1,100)
      note(60,2).should    == Note.new(60,2,100)
      note(60,3,80).should == Note.new(60,3,80)
    end
    
    it "should construct a rest" do
      rest().should  == Silence.new(1)
      rest(2).should == Silence.new(2)
    end
    
    it "should compose lists of music objects sequentially" do
      line(note(60), note(64), note(67)).should == note(60) & note(64) & note(67)
    end
    
    it "should compose lists of music objects in parallel" do
      chord(note(60), note(64), note(67)).should == note(60) | note(64) | note(67)
    end
    
    it "should delay music objects with silence" do
      delay(3, note(60)).should == silence(3) & note(60)
    end
  end
  
  describe Pitch do
    before(:all) do
      @pitch = Pitch.new(
      @pc    =   PitchClass.for(60),
      @oct   =   4)
    end
    
    it "should have a PitchClass" do
      @pitch.pitch_class.should == @pc
    end
    
    it "should have an Octave" do
      @pitch.octave.should == @oct
    end
  end
  
  describe PitchClass do
    it "should return an instance of PitchClass given any midi pitch number" do
      (60..71).zip([
          :c, :cis,
          :d, :dis,
          :e,
          :f, :fis,
          :g, :gis,
          :a, :ais,
          :b
      ]).each do |m, n|
        PitchClass.for(m).name.should == n
      end
    end
  end
end
