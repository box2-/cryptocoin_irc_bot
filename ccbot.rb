#!/usr/bin/env ruby
################################################################################
# ruby >= 2.0
#
# This bot requires:
# -- apt-get install ruby ruby-dev
# -- gem install eventmachine string-irc
#
# This bot will pull stock information for irc
#
# This bot uses Alpha Vantage service, so you have to sign up for an API key
# https://www.alphavantage.co/
#
################################################################################
require 'socket'
require 'openssl'
require 'thread'
require 'eventmachine'
require 'net/http'
require 'json'
require 'string-irc'

# Pull connection information from our config file
conf = JSON.parse(File.read("config.json"))

############################################################
# socket connection and irc side commands                  #
############################################################
class IRC
  def initialize(server, port, channel, nick, api)
    @bot = { :server => server, :port => port, :channel => channel, :nick => nick, :api => api }
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

############################################################
# Get stocks
############################################################
      if msg.match(/\:!s /)
        # Here we are breaking the regex into a hash table
        regexp = %r{
          (?<command> :!s ) {0}
          (?<args> (.*) ) {0}
          \g<command> \g<args>
        }x
        recv = regexp.match(msg)
        args = recv['args'].split(" ")
        if (args.count > 0)
          args.each do |arg|
            if(arg.match(/^[A-z0-9\.]+$/))
              uri = URI.parse("https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=#{arg}&apikey=#{@bot[:api]}")
              response = Net::HTTP.get_response(uri)

              data = JSON.parse(response.body)
              today = Time.now.strftime("%Y-%m-%d")
              begin
                last = data["Time Series (Daily)"][today]["4. close"].chop.chop
                open = data["Time Series (Daily)"][today]["1. open"].chop.chop
                gain = "(#{CryptoPull.gainz(open, last)})"
                gain = gain.match(/\+/) ? StringIrc.new(gain).green.to_s : StringIrc.new(gain).maroon.to_s
                high = data["Time Series (Daily)"][today]["2. high"].chop.chop
                low = data["Time Series (Daily)"][today]["3. low"].chop.chop

                say_to_chan("#{arg.upcase}: Open: $#{open} Last: $#{last} #{gain} High: $#{high} Low: $#{low}", chan)
              rescue => error
                p error
              end
            end
          end
        end
      end
      
############################################################
# Calculate gain % of 2 inputs
############################################################
      if msg.match(/\:!gainz /)
        # Here we are breaking the regex into a hash table
        regexp = %r{
          (?<command> :!gainz ) {0}
          (?<args> (.*) ) {0}
          \g<command> \g<args>
        }x
        recv = regexp.match(msg)
        args = recv['args'].split(" ")

        if(args.count == 2)
          say_to_chan(CryptoPull.gainz(args[0], args[1]))
        end
      end

      if msg.match(/\:!return /)
        # Here we are breaking the regex into a hash table
        regexp = %r{
          (?<command> :!return ) {0}
          (?<args> (.*) ) {0}
          \g<command> \g<args>
        }x
        recv = regexp.match(msg)
        args = recv['args'].split(" ")

        if(args.count == 2)
          say_to_chan(CryptoPull.gainz(args[0], args[1]))
        end
      end


############################################################
# Get cryptos
############################################################
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

        if(args.empty?)
          say_to_chan(CryptoPull.dailyStats, chan)
        elsif(args[0] == "-h")
            toSay = "CryptoCurrency bot use: !cc [options]   Valid switches are: -h (this help), -l to list supported coins, or a space seperated list of coin symbols.  Open price is the first price of the UTC day."
            say_to_chan(toSay, chan)
          elsif(args[0] == "-l")
            toSay = "Currently supported symbols: BTC, LTC, ETH, XRP"
            say_to_chan(toSay, chan)
          elsif(args.count > 4)
            say_to_chan("Too many arguments", chan)
          else
            args.each do |x|
              if(x.upcase == "BTC" || x.upcase == "LTC" || x.upcase == "ETH" || x.upcase == "XRP")
                say_to_chan(CryptoPull.dailyStats(x), chan)
            end
          end
        end
      end

    end  
  end
  
  def get_history
    return @history
  end

  def quit(msg = nil)
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
      # right now this only works for the first channel in our list by default
      # for other channals use: /msg #channel message
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

      # % Change from todays open price (first order of the UTC day) and current price
      begin
        pChange = (((body['last'].to_f - body['open'].to_f) / body['open'].to_f * 100) * 1000).floor / 1000.0
        pChange = (pChange > 0) ? pChange.to_s.prepend("+") : pChange.to_s
        pChange = pChange.match(/\+/) ? StringIrc.new(pChange + "%").green.to_s : StringIrc.new(pChange + "%").maroon.to_s
      rescue => error
        p error
        pChange = "Error"
      end

      # Beautify our values
      high = CryptoPull.commas(body['high'])
      low = CryptoPull.commas(body['low'])
      open = CryptoPull.commas(body['open'])
      last = CryptoPull.commas(body['last'])
      volume = CryptoPull.commas(body['volume'])

      msg = "#{coin.upcase} Daily:  "
      msg += "High: #{high} Low: #{low} Open: #{open} Last: #{last} (#{pChange}) Volume: #{volume}"
      return msg
    else
      return "Error: #{coin} not a valid cryptocurrency token."
    end
  end

  # Jesus christ why doesn't ruby have a function to add commas to a number already
  def self.commas(num)
    first, *rest = num.split(".")
    return first.reverse.gsub(/(\d+\.)?(\d{3})(?=\d)/, '\\1\\2,').reverse + "." + rest[0]
  end

  # Calculate % return of two arbitrary numbers
  def self.gainz(num1, num2)
    begin
      start = num1.delete(",").to_f
      fin = num2.delete(",").to_f
      pChange = ((((fin - start) / start) * 100) * 1000).floor / 1000.0
      (pChange > 0) ? pChange = "+" + pChange.to_s : ""
      return pChange.to_s + "%"
    rescue
      return "An error occured"
    end
  end
end

########
# Main #
########
# initialize our irc bot
irc = IRC.new(conf["server"], conf["port"], conf["channel"], conf["nick"], conf["api-key"]) 

# trap ^C signal from keyboard and gracefully shutdown the bot
# quit messages are only heard by IRCD's if you have been connected long enough(!)
trap("INT"){ irc.quit("Console Quit") }

# spawn console input handling thread
console = Thread.new{ ConsoleThread.new(irc) }

# connect to irc server
irc.connect
# run main irc bot execution loop (ping/pong, communication etc)
irc_thread = Thread.new{ irc.run }
# this locks until irc.run is finished, but we now see incoming irc traffic in terminal
irc_thread.join   

puts 'this wont appear'
