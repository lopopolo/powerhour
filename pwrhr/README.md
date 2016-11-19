pwrhr.rb
===========

A small ruby script designed to run a powerhour from the command line.
It is decently configurable. These are the options `pwrhr.rb` supports

```console
$ ./pwrhr.rb -h
Usage: ./pwrhr.rb [options]

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

By default, the Mac iTunes music folder is scanned for music files
(mp3 only). You may supply an alternate directory via the
`-D` switch.

To prevent your mac from sleeping or turning off the display during a
power hour, invoke pwrhr.rb like this:

```bash
caffeinate -i -d ./pwrhr.rb
```
