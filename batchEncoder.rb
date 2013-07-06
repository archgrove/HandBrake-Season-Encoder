#!/usr/bin/ruby

require 'optparse'

def extractTracksAndLengths(file)
  command = "HandBrakeCLI -t 0 -i '#{file}' 2>&1"
  tracksAndLengths = Array.new

  currentTrack = 0
  currentBlocks = 0

  process = IO.popen(command)
  
  process.each_line { |line|
    cleanLine = line.strip

    return nil if cleanLine == "No title found."

    # Tracks have format "+ title X:"
    if /\+ title (\d+):/ =~ cleanLine
      currentTrack = $~[1]
    # Blocks are + vts 2, ttn 3, cells 0->7 (962954 blocks)
    elsif /\+ vts (\d+), ttn (\d+), cells (\d+)->(\d+) \((\d+) blocks\)/ =~ cleanLine
      currentBlocks = $~[5].to_i
    # Durations have format "  + duration: XX:YY:ZZ"
    elsif /\+ duration: (\d+):(\d+):(\d+)/ =~ cleanLine
      hours = $~[1].to_i
      mins = $~[2].to_i
      secs = $~[3].to_i
      totalSecs = (hours * 60 * 60) + (mins * 60) + secs

      tracksAndLengths << { :index => currentTrack, :length => totalSecs,
                            :blocks => currentBlocks }
    end
  }

  process.close()

  return tracksAndLengths
end


def selectTracks(tracksAndLengths, targetLengths, delta)
  # Reject anything with identical blocks length, then anything 
  # that is more than delta from every target length
  
  # Ruby 1.8.7 has no uniq(block) call for filtering, so we fake it
  blockUniqTracks = Array.new
  tracksAndLengths.each do |val|
    if blockUniqTracks.index { |uniq| uniq[:blocks] == val[:blocks] } == nil
      blockUniqTracks << val
    end
  end

  return blockUniqTracks.reject do |val|
    targetLengths.map do |targetLength|
      (val[:length] - targetLength).abs > delta 
    end.each.reduce(:&)
  end
end

def processDiscs(discs, perDisc, total, length, allowDouble)
  allTracks = Array.new
  foundDoubles = 0

  discs.each do |disc|
    discTracks = extractTracksAndLengths(disc)
    lengths = allowDouble ? [length, length * 2] : [length]
    delta = length / 10

    if discTracks == nil
      print "File \"#{disc}\" is not a media disc \n"
    elsif
      selectedTracks = selectTracks(discTracks, lengths, delta)

      foundEpisodes = 0
      i = 0

      while (i < selectedTracks.length) && (foundEpisodes < perDisc) do
        isDouble = (selectedTracks[i][:length] > length + delta)

        allTracks << { :disc => disc, :track => selectedTracks[i][:index], 
                       :length => selectedTracks[i][:length],
                       :isDouble => isDouble }

        # Allow for double episodes
        if (isDouble) then
          foundEpisodes += 2
          foundDoubles += 1
        else
          foundEpisodes += 1
        end

        i += 1
      end
    end
  end

  return allTracks.slice(0, total - foundDoubles)
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
  options[:doubleNamingScheme] = "Episodes %i and %i.m4v"
  options[:episodeLength] = 45 * 60
  options[:episodesPerDisc] = 4
  options[:episodesTotal] = 24
  options[:audioTrack] = 1
  options[:startAt] = 1
  options[:allowDouble] = false

  opts.banner = "Usage: batchEncoder.rb [options]"

  opts.on('-o', "--output-dir O", "Target directory for output") do |p|
    options[:outputDir] = p
  end

  opts.on('-n', "--naming-scheme N", "Naming scheme for episodes") do |p|
    options[:namingScheme] = p
  end

  opts.on('-nn', "--double-naming-scheme N", "Naming scheme for double episodes") do |p|
    options[:doubleNamingScheme] = p
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

  opts.on('-a', "--audio-track A", Integer, "Audio track to use") do |p|
    options[:audioTrack] = p
  end

  opts.on('-s', "--start-at S", Integer, "Episode index to begin at") do |p|
    options[:startAt] = p
  end

  opts.on('-m', "--allow-double", "Allow double-length episodes") do |p|
    options[:allowDouble] = true
  end
end

optParser.parse!
options[:discs] = ARGV

toEncode = processDiscs(options[:discs], options[:episodesPerDisc],
                        options[:episodesTotal], options[:episodeLength],
                        options[:allowDouble])

print <<END
#!/bin/bash

trap "{ killall HandBrakeCLI; exit 0 }" SIGTSTP

encodeFile() {
  if [ -e "$1.encoding" ]; then
    echo "Resuming encoding for $1"

    rm "$1.encoding"
    rm "$1"
  fi

  if [ ! -e "$1" ]; then
    echo "Encoding $1: "

    touch "$1.encoding"
    HandbrakeCLI -o "$1" -i "$2" -t $3 -a $4 -Z "AppleTV 3" -m 2>/dev/null
    rm "$1.encoding"
  else
    echo "Skipping $1"
  fi
}

END

episodeNum = options[:startAt]
toEncode.drop(options[:startAt] - 1).each do |encodeSource|
  if (encodeSource[:isDouble]) then
    outputName = options[:doubleNamingScheme] % [episodeNum, episodeNum + 1]
    episodeNum = episodeNum + 2
  else
    outputName = options[:namingScheme] % episodeNum
    episodeNum = episodeNum + 1
  end


  print   "encodeFile '#{outputName}' '#{encodeSource[:disc]}' " + "#{encodeSource[:track]} #{options[:audioTrack]}\n"
end
