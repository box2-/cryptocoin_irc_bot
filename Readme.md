# Ruby IRC Bot
This bot started as a way to view current crypto currency exchange rates on irc and to practice ruby.  It's since had some features added.

## Options
!s [space seperated list of stock symbols]
* This option pulls stock information from yahoo

!gainz [arg1] [arg2]
* This is a simple gain calculator, input two numbers to see the % gain or loss between them

!cc (optional arguments)
* This trigger by itself with no arguments pulls BTC's current 24 hour performance and current value
* Other symbols can be viewed by doing: !cc [space seperated list of symbols]
* Other options include: -h for a help menu, -l to list currently support crypto symbols
