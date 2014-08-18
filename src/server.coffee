Http        = require 'http'
io          = require 'socket.io-client'
SerialPort  = require('serialport').SerialPort
logger      = require './logger'
FS          = require 'fs'
serial_port = undefined
buffer      = ''
ws = undefined

class Server
  constructor: (@host, @port, @options = {}) ->

  #
  # connect to tty and socket.io
  #
  run: (callback) ->
    @_setup_writestream()
    @_setup_sio()

  #
  # @return [String] URL based on config
  #
  _url: ->
    "http://#{ @host }#{ if @port? then ":#{@port}" else '' }/#{ @options.namespace }"

  #
  # connect socket.io client to url, bind to socket.io events and our custom events
  #
  _setup_sio: ->
    # logger.debug "Socket.io connecting to url #{@_url()}"
    socket = new io(@_url(), {})
    socket.on 'connect', =>
      console.log "connected to socket at #{@_url()}"

      # make an initial call to our recursive serialport write method
      @_write_file()

    socket.on 'connect_error', (obj) => console.log 'connect error', obj
    socket.on 'disconnect',          => console.log "socket at #{@_url()} disconnected"
    socket.on 'colorChanged', (data) => @_to_buffer(data)
    socket.on 'colorSet',     (data) => @_to_buffer(data)

  #
  # connect to /dev/ttyO1, on success fire a call to _setup_sio()
  #
  _setup_writestream: ->
    ws = FS.createWriteStream("/dev/ttyO1", { flags: "w+" });

  _write_file: ->
    setTimeout (=>
      if buffer.length == 0
        @_write_file()
        return
      else
        console.log "writing to file"
        console.log buffer
        ws.write(buffer, (err, written) =>
          throw err if err
          buffer = ''
          @_write_file()
        )
    ), 15

  #
  # convert halo rgba string to a UART instruction
  # @example
  #   _data_to_instruction({ color: '000,110,255,000\n' })
  #   # => '4,1,000,110,255,000;'
  #
  _data_to_instruction: (data) ->
    # console.log "called _data_to_instruction"
    # console.log data

    # break colors string into array
    colors = data.color.split '\n'
    colors.pop()

    # build our TTY instruction
    # logger.debug "colors: #{colors} length: #{colors.length}"
    instruction = ''
    instruction += "4,#{i+1},#{color};" for color, i in colors

    # padding with black if necessary
    instruction_count = (instruction.match(/;/g)||[]).length
    instruction += "4,#{i+1},000,000,000,000;" for i in [instruction_count...5]
    return instruction

  #
  # write socket.io color data to buffer as UART instruction
  #
  _to_buffer: (data) ->
    # logger.info "writing to buffer #{data.color}"
    buffer = @_data_to_instruction(data)

  #
  # empty the buffer
  #
  _clear_buffer: ->
    # logger.info "clearing buffer"
    buffer = ''

module.exports = Server
