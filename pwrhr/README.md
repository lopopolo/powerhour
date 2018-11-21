# pwrhr.rb

A small ruby script designed to run a power hour from the command line.
It is decently configurable. These are the options `pwrhr.rb` supports:

```console
$ ./pwrhr.rb -h
Usage: ./pwrhr.rb [options]

OPTIONS
    -c, --count NUMBER               Number of songs in the power hour
    -d, --duration SECONDS           Duration to play each song in seconds
    -s, --source DIR                 Scan DIR for music files
    -h, --help                       Display this screen

DEFAULTS
    count: 60
    duration: 60
    source: ~/Music/iTunes/iTunes Media/Music
```

By default, the macOS iTunes music folder is scanned for music files
(mp3 only). You may supply an alternate directory via the `-s` switch.

To prevent your Mac from sleeping or turning off the display during a
power hour, invoke pwrhr.rb like this:

```bash
caffeinate -i -d ./pwrhr.rb
```
