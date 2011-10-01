pwrhr.rb
===========

A small ruby script designed to run a powerhour from the command line.
It is decently configurable. These are the options `pwrhr-cl.rb` supports

```
▶ ./pwrhr.rb --help
Usage: pwrhr.rb [options]

    -n, --number-of-songs NUMBER     Number of songs in the power hour (default 60)
    -x, --xml FILE                   Location of iTunes XML (default $HOME/Music/iTunes/iTunes Music Library.xml
    -d, --duration SECONDS           Duration of each song in seconds (default 60)
    -D, --directory DIR              Use DIR of music files instead of the iTunes XML
    -c "COMMAND --some-switch <duration> <file>"
        --command                    Use COMMAND to play files. The "<duration>" and "<file>" placeholders must be specified.
    -h, --help                       Display this screen
```

I originally designed this script to run on a Mac because OSX 10.5+ includes
the `afplay` utility which can play any file QuickTime supports; however,
you can supply your own command with the `-c` switch. Despite this 
"portability", the default options are Mac-centric (for example, grepping
the iTunes library xml to find songs).

Linux users can use `mpg321`. It doesn't quite have a duration flag, but
I believe you can use the `--frames` option to achieve a similar result.

At the minimum, your system needs `find` and a command line tool to play
audio files.

