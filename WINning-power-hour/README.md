# WINning power hour

This is another ruby powerhour script. I wrote this in 2008 before I knew what
version control was. It runs a powerhour using either iTunes or Windows Media
Player.

Some awesome features of this app:

- It uses wx
- It only runs on windows! (It uses COM interfaces exposed by Windows Media
  player and iTunes.)
- I packaged it as a standalone EXE. Why did I do this instead of pacakging as a
  gem? WHO KNOWS! That's part of the excitement. Similarly, I do not know the
  difference between `rubyscript2exe.rb` and `rubyscript2exe-mod.rb`
- The source is in `app`. It doesn'r run on its own without ripping out the
  stuff needed for `rubyscript2exe.rb`. AWESOME.
- The only way to stop the powerhour once you've started it is to kill the ruby
  process. Since it runs without a command window, this is non-trivial!
- This code is formatted awfully.

# In spite of all of these flaws, it does perform the task of running a powerhour.

## And it is somewhat configurable.
