pwrhr.rb
===========

A small ruby script designed to run a powerhour from the command line.
It is decently configurable. These are the options `pwrhr.rb` supports

```console
$ ./pwrhr.rb -h
Usage: ./pwrhr.rb [options]

pwrhr depends on the afplay utility.

OPTIONS
    -n, --num-songs NUMBER           Number of songs in the power hour
    -d, --duration SECONDS           Duration to play each song in seconds
    -D, --directory DIR              Use DIR of music files
    -h, --help                       Display this screen

DEFAULTS
    songs: 60
    duration: 60
    dir: ~/Music/iTunes/iTunes Media/Music
```

I designed this script to run on a Mac because OS X 10.5+ includes
the `afplay` utility which can play any file QuickTime supports.

By default, the Mac iTunes music folder is scanned for music files
(aac, m4a, mp3, mp4). You may supply an alternate directory via the
`-D` switch.
