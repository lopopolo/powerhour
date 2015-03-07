pwrhr.rb
===========

A small ruby script designed to run a powerhour from the command line.
It is decently configurable. These are the options `pwrhr-cl.rb` supports

```
▶ ./pwrhr.rb --help
Usage: ./pwrhr.rb [options]

pwrhr depends on afplay.
    -n, --num-songs NUMBER           Number of songs in the power hour (default 60)
    -d, --duration SECONDS           Duration of each song in seconds (default 60)
    -D, --directory DIR              Use DIR of music files (default ~/Music/iTunes/iTunes Media/Music)
    -h, --help                       Display this screen
```

I designed this script to run on a Mac because OSX 10.5+ includes
the `afplay` utility which can play any file QuickTime supports.

By default, the Mac iTunes music folder is scanned for music files
(aac, m4a, mp3, mp4). You may supply an alternate directory via the
`-D` switch.
