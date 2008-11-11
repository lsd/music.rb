module Music
  module Csound
    
    class ScoreWriter
      attr_reader :instruments, :path
      
      def initialize(options = {})
        @path        = options[:path]
        @instruments = options.fetch(:instruments, {})
      end
      
      def write(timeline_or_score)
        timeline = timeline_or_score.to_timeline
        File.open(path, 'w') do |f|
          write_instruments(f, timeline)
        end
      end
      
      private
        def write_instruments(file, timeline)
          timeline.each_with_time do |obj, time|
            inst = obj.read(:instrument)
            raise "Instrument #{inst} is undefined!" unless @instruments[inst]
            file.write("i %i\t%i\t%i%s\n" % [
              inst,
              time.to_csound,
              obj.duration.to_csound,
              format_attributes(inst, obj)
            ])
          end
        end
        
        def format_attributes(inst, obj)
          if attrs = instruments[inst]
            attrs.inject("") do |out, attr|
              out + "\t" + obj.read(attr).to_csound
            end
          end
        end
    end
    
    class ::Numeric
      def to_csound; round.to_s end
    end
    
    class ::Float
      alias to_csound round
    end
    
    class ::Music::Pitch
      def to_csound
        int = to_i
        oct = int.div(12) + 3
        pc  = int % 12
        "%i.%02i" % [oct, pc]
      end
    end
  end
end
