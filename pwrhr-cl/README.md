pwrhr-cl
========

A small ruby script designed to run a powerhour from the command line.
It is decently configurable; you can get a list of all the options it
supports by running `./pwrhr-cl -h`

I originally designed it to run on a Mac because OSX 10.5+ includes the
`afplay` utility which can play any file QuickTime supports; however,
you can supply your own command with the `-c` switch. Despite this 
"portability", the default options are Mac-centric (for example, grepping
the iTunes library xml to find songs)

At the minimum, your system needs `find` and a command line tool to play
audio files.
