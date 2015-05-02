HandBrake-Season-Encoder
========================

The HandBrake Season Encoder takes a set of DVD images comprising a number of episodes, and produces a shell script that will encode the episodes into h.264 M4V files (whilst ignoring the non-episode tracks on the disc). The intended use is for encoding TV seasons that you own for archival.

# Usage

    batchEncoder.rb pathToDISC1 pathToDISC2 ... pathToDISCn

That is,

    batchEncoder.rb pathToFolderContainingImages/*

There are a number of useful command line flags:

- `-help` : Explains each command line option.
- `-l N` : States that episodes are `N` minutes long. Defaults to 45 minutes.
- `-d N` : States that the system should expect `N` episodes per disc (though might not find them, especially on the last disc). Defaults to 4.
- `-j N` : Accepts tracks as episodes if they are within `N` percent of the expected episode length. Defaults to 15%.
- `-m` : Allow double length episodes.

There are a number of further useful flags; see `--help` for more.
