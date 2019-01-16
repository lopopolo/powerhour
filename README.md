# powerhour

A [power hour](https://en.wikipedia.org/wiki/Power_hour) is a (drinking) game.
During each 60-second round, a song is played. A change in music marks each new
round.

I enjoy implementing power hour apps as a way to learn a language or a design
pattern because the game is simple and well-specified.

## Design

All of my implementations of a power hour app play music from some _source_ via
an _audio backend_ with some form of a _UI_. I aspire to structure the apps with
MVC and message passing, with the audio backend working off the main thread.

## Implementations

| Language                                     | Source                                                                                  | Audio Backend                                                                                                                    | UI                 |
| :------------------------------------------- | :-------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------- | :----------------- |
| JavaScript                                   | PHP search backend with [GData API](https://developers.google.com/gdata/docs/directory) | YouTube embed                                                                                                                    | HTML               |
| [ActionScript](/as-powerhour)                | PHP search backend with [GData API](https://developers.google.com/gdata/docs/directory) | YouTube embed                                                                                                                    | Flex + SWF         |
| [Ruby](/WINning-power-hour)                  | Windows Media Player/iTunes                                                             | [WIN32OLE](https://ruby-doc.org/stdlib-1.8.7/libdoc/win32ole/rdoc/WIN32OLE.html)                                                 | wxWidgets          |
| [Ruby](/pwrhr)                               | Local directory of MP3s                                                                 | [Audite](https://github.com/georgi/audite)                                                                                       | Curses             |
| [Rust](https://github.com/lopopolo/punchtop) | Local directory of MP3s                                                                 | [Local via rodio](https://docs.rs/rodio/0.8.1/rodio/)/[Chromecast](https://github.com/lopopolo/punchtop/tree/master/cast-client) | Cocoa/Web view/CLI |

The JS implementation and the PHP search backend are lost to the sands of time.
