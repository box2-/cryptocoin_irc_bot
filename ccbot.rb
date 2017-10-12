!/usr/bin/env ruby
################################################################################
# ruby >= 2.0
#
# This bot requires:
# -- apt-get install ruby ruby-dev
# -- gem install eventmachine
#
# This bot will pull stock information for irc
#
################################################################################
require 'socket'
require 'openssl'
require 'thread'
require 'eventmachine'
require 'net/http'
require 'json'

server = 'irc.xxxx.org'
port = '6697'
nick = 'xxxxx'
channel = ['#chan1', '#chan2']

############################################################
# socket connection and irc side commands                  #
############################################################
class IRC
  def initialize(server, port, channel, nick)
    @bot = { :server => server, :port => port, :channel => channel, :nick => nick }
  end

  def connect
    conn = TCPSocket.new(@bot[:server], @bot[:port])
    @socket = OpenSSL::SSL::SSLSocket.new(conn)
    @socket.connect

    say "NICK #{@bot[:nick]}"
    say "USER #{@bot[:nick]} 0 * ."
  end

  def say(msg)
    puts msg
    @socket.puts(msg)
  end

  def say_to_chan(msg, chan=@bot[:channel][0])
    r = msg.split("\n")
    r.each{ |x| say "PRIVMSG #{chan} :#{x}" }
  end

  def run
    joined = false
    until @socket.eof? do
      msg = @socket.gets
      puts msg

      # We join our channels here
      if(!joined && msg =~ /.*NOTICE.*#{@bot[:nick]}/)
        @bot[:channel].each{ |x| say "JOIN #{x}" }
        joined = true
      end
      if msg.match(/^PING :(.*)$/)
        say "PONG #{$~[1]}"
        next
      end

############################################################
# Channel side commands start here                         #
############################################################
      # What channel did we receive this from? (Does not view private messages)
      chan = msg.match(/\#(.*?) /)

      # Here we match chat line only if it begins with !cc and is exactly just that or has a space after
      if msg.match(/\:!cc(?!\S)/)
        # Here we are breaking the regex into a hash table
        regexp = %r{
          (?<command> :!cc ) {0}
          (?<args> (.*) ) {0}
          \g<command> \g<args>
        }x
        # Perform our regex
        recv = regexp.match(msg)
        args = recv['args'].split(" ")

        if(!args.empty?)
          if(args[0] == "-h")
            toSay = "CryptoCurrency bot use: !cc [options]\n\
Valid switches are: -h (this help), -l to list supported coins, or a space seperated list of coin symbols."
            p toSay
            say_to_chan(toSay, chan)
          elsif(args[0] == "-l")
            toSay = "Currently supported symbols: BTC, LTC, ETH"
            say_to_chan(toSay, chan)
          elsif(args.count > 3)
            say_to_chan("Too many arguments", chan)
          else
            args.each do |x|
              if(x.upcase == "BTC" || x.upcase == "LTC" || x.upcase == "ETH")
                say_to_chan(CryptoPull.dailyStats(x), chan)
              end
            end
          end
        else
          say_to_chan(CryptoPull.dailyStats, chan)
        end

      end
    end

  end

  def get_history
    return @history
  end

  def quit(msg = nil)
    #say "PART ##{@channel} :SHIPOOPIE"
    say( msg ? "QUIT #{msg}" : "QUIT" )
    abort("Thank you for playing.")
  end
end

############################################################
# This thread interacts with console user intput           #
# and sends commands/chat to connected irc                 #
############################################################
class ConsoleThread
  def initialize(bot = nil)
    if bot == nil
      puts "We have no bots connected, console input is meaningless"
      exit!
    end

    while(true)
      # capture cli input
      input = gets
      ###########################
      # commands start with /   #
      # everything else is chat #
      ###########################
      case
      # check for irc graceful quit (and maybe a quit message)
      when input.match(/^\/(quit|exit|shutdown|halt|die) (.*)/)
        bot.quit( $~[2] ? $~[2] : nil )
      # private message to user (or other channel)
      when input.match(/^\/msg ([^ ]*) (.*)/)
          bot.say "PRIVMSG #{$~[1]} #{$~[2]}"
      # join new channel command
      when input.match(/^\/join (#.*)/)
          bot.say "JOIN #{$~[1]}"
      # raw irc command (e.g. "JOIN #newchannel")
      when input.match(/^\/raw (.*)/)
          bot.say $~[1]
      # doesnt begin with /, send chat to channel
      else
        bot.say_to_chan(input)
      end
    end
  end
end

############################################################
# This module controls pulling crypto API data             #
############################################################
module CryptoPull
  def self.dailyStats(coin="BTC")
    uri = URI("https://www.bitstamp.net/api/v2/ticker/#{coin}usd/")
    res = Net::HTTP.get_response(uri)
    if (res.code != "404")
      body = JSON.parse(res.body)
      pChange = (((body['last'].to_f - body['open'].to_f) / body['open'].to_f.truncate * 100) * 1000).floor / 1000.0
      (pChange > 0) ? pChange = "+" + pChange.to_s : ""

      msg = "24H #{coin} Performance:  "
      msg += "High: #{body['high']}  Low: #{body['low']}  Last: #{body['last']}  (#{pChange})  Volume: #{body['volume']}"
      return msg
    else
      return "Error: #{coin} not a valid cryptocurrency token."
    end
  end
end

########
# Main #
########
# initialize our irc bot
irc = IRC.new(server, port, channel, nick)

# trap ^C signal from keyboard and gracefully shutdown the bot
# quit messages are only heard by IRCD's if you have been connected long enough(!)
trap("INT"){ irc.quit("fucking off..") }

# spawn console input handling thread
console = Thread.new{ ConsoleThread.new(irc) }

# connect to irc server
irc.connect
# run main irc bot execution loop (ping/pong, communication etc)
irc_thread = Thread.new{ irc.run }
# this locks until irc.run is finished, but we now see incoming irc traffic in terminal
irc_thread.join

puts 'this wont appear'
