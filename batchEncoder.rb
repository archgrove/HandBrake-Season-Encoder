#!/usr/bin/ruby

require 'optparse'

def extractTracksAndLengths(file)
  command = "HandBrakeCLI -t 0 -i '#{file}' 2>&1"
  tracksAndLengths = Array.new

  currentTrack = 0

  process = IO.popen(command)
  
  process.each_line { |line|
    cleanLine = line.strip

    return nil if cleanLine == "No title found."

    # Tracks have format "+ title X:"
    if /\+ title (\d+):/ =~ cleanLine
      currentTrack = $~[1]
    # Durations have format "  + duration: XX:YY:ZZ"
    elsif /\+ duration: (\d+):(\d+):(\d+)/ =~ cleanLine
      hours = $~[1].to_i
      mins = $~[2].to_i
      secs = $~[3].to_i
      totalSecs = (hours * 60 * 60) + (mins * 60) + secs

      tracksAndLengths << { :index => currentTrack, :length => totalSecs }
    end
  }

  process.close()

  return tracksAndLengths
end


def selectTracks(tracksAndLengths, targetLength, delta)
  return tracksAndLengths.reject do |val|
    # Reject anything falling further than delta from the target
    (val[:length] - targetLength).abs > delta
  end
end

def processDiscs(discs, perDisc, total, length)
  allTracks = Array.new

  discs.each do |disc|
    discTracks = extractTracksAndLengths(disc)

    if discTracks == nil
      print "File \"#{disc}\" is not a media disc \n"
    elsif
      selectedTracks = selectTracks(discTracks, length, length / 10)

      [perDisc, selectedTracks.length].min.times do |i|
        allTracks << { :disc => disc, :track => selectedTracks[i][:index], 
                       :length => selectedTracks[i][:length] }
      end
    end
  end

  return allTracks.slice(0, total)
end

# Pull out parameters
# -o target_dir
# -n naming_scheme
# -l Length_ (minutes)
# -d Expected number of episodes (per disc)
# -e Expected number of episodes (total)
# -- List of discs

options = Hash.new

optParser = OptionParser.new do |opts|
  options[:outputDir] = "."
  options[:namingScheme] = "Episode %i.m4v"
  options[:episodeLength] = 45 * 60
  options[:episodesPerDisc] = 4
  options[:episodesTotal] = 24

  opts.banner = "Usage: batchEncoder.rb [options]"

  opts.on('-o', "--output-dir O", "Target directory for output") do |p|
    options[:outputDir] = p
  end

  opts.on('-n', "--naming-scheme N", "Naming scheme for episodes") do |p|
    options[:namingScheme] = p
  end

  opts.on('-l', "--episode-length L", Integer, "Length of episodes (minutes)") do |p|
    options[:episodeLength] = p * 60
  end
  
  opts.on('-d', "--episodes-per-disc D", Integer, "Expected episodes per disc") do |p|
    options[:episodesPerDisc] = p
  end

  opts.on('-e', "--epsiodes-total E", Integer, "Expected total episodes") do |p|
    options[:episodesTotal] = p
  end
end

optParser.parse!
options[:discs] = ARGV

toEncode = processDiscs(options[:discs], options[:episodesPerDisc],
                        options[:episodesTotal], options[:episodeLength])

print <<END
#!/bin/bash

trap { killall HandBrakeCLI; exit 0 } SIGTSTP

encodeFile() {
  if [ -e "$1.encoding" ]; then
    echo "Resuming encoding for $1"

    rm "$1.encoding"
    rm "$1"
  fi

  if [ ! -e "$1" ]; then
    echo "Encoding $1: "

    touch "$1.encoding"
    HandbrakeCLI -o "$1" -i "$2" -t $3 -Z "AppleTV 3" -m 2>/dev/null
    rm "$1.encoding"
  else
    echo "Skipping $1"
  fi
}

END

episodeNum = 1
toEncode.each do |encodeSource|
  outputName = options[:namingScheme] % episodeNum
  episodeNum = episodeNum + 1

  print   "encodeFile '#{outputName}' '#{encodeSource[:disc]}' " + "#{encodeSource[:track]}\n"
end
