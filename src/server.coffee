Http        = require 'http'
io          = require 'socket.io-client'
SerialPort  = require('serialport').SerialPort
logger      = require './logger'
FS          = require 'fs'
serial_port = undefined
buffer      = ''
class Server
  constructor: (@host, @port, @options = {}) ->

  #
  # connect to tty and socket.io
  #
  run: (callback) ->
    @_setup_serialport()

  #
  # @return [String] URL based on config
  #
  _url: ->
    "http://#{ @host }#{ if @port? then ":#{@port}" else '' }/#{ @options.namespace }"

  #
  # connect socket.io client to url, bind to socket.io events and our custom events
  #
  _setup_sio: ->
    logger.debug "Socket.io connecting to url #{@_url()}"
    socket = new io(@_url(), {})
    socket.on 'connect', =>
      console.log "connected to socket at #{@_url()}"

      # make an initial call to our recursive serialport write method
      @_write_buffer()

    socket.on 'connect_error', (obj) => console.log 'connect error', obj
    socket.on 'disconnect',          => console.log "socket at #{@_url()} disconnected"
    socket.on 'colorChanged',           @_to_buffer
    socket.on 'colorSet',               @_to_buffer

  #
  # connect to /dev/ttyO1, on success fire a call to _setup_sio()
  #
  _setup_serialport: ->
    tty = '/dev/ttyO1'
    logger.debug "Node serialport connecting to #{tty}"

    serial_port = new SerialPort(tty,
      baudrate: 115200
    )

    serial_port.on "open", =>
      logger.info "Node serialport connected to #{tty}"
      logger.debug serial_port

      @_setup_sio()

      serial_port.on 'data', (data) ->
        logger.info 'data received: ' + data

  #
  # convert halo rgba string to a UART instruction
  # @example
  #   _data_to_instruction({ color: '000,110,255,000\n' })
  #   # => '4,1,000,110,255,000;'
  #
  _data_to_instruction: (data) ->
    # break colors string into array
    colors = data.color.split '\n'
    colors.pop()

    # build our TTY instruction
    logger.debug "colors: #{colors} length: #{colors.length}"
    instruction = ''
    instruction += "4,#{i+1},#{color};" for color, i in colors

    # padding with black if necessary
    instruction_count = (instruction.match(/;/g)||[]).length
    instruction += "4,#{i+1},000,000,000,000;" for i in [instruction_count...5]
    return instruction

  #
  # write contents (UART instruction) of buffer to serial port.
  # when serial port drains, clear the buffer and recursively call the function again
  #
  _write_buffer: ->
    setTimeout (=>
      logger.info "writing buffer '#{buffer}' to serial port"
      serial_port.write buffer, (err, results) =>
        logger.info "serial port written"

        serial_port.drain((error) =>
          logger.info "serial port drained"
          @_clear_buffer()
          @_write_buffer()
        )
    ), 1000

  #
  # write socket.io color data to buffer as UART instruction
  #
  _to_buffer: (data) ->
    logger.info "writing to buffer #{data.color}"
    buffer += @_data_to_instruction(data)

  _clear_buffer: ->
    logger.info "clearing buffer"
    buffer = ''

  #
  # break our colors string into array, write each color to the appropriate address
  # @example data
  #   { color: '000,110,255,000\n000,110,255,000\n000,110,255,000\n000,110,255,000\n000,110,255,000\n' }
  #
  # _write_colors_over_tty: (data) ->
  #   logger.debug '_write_colors_over_tty'
  #   instruction = @_data_to_instruction(data)
  #
  #   # write over TTY
  #   logger.debug "writing to serial port: #{instruction}"
  #   serial_port.write instruction, (err, results) ->
  #     logger.debug 'serial_port.write err: ' + err if err
  #     logger.debug 'serial_port.write results: ' + results if results
  #     serial_port.drain( (error) ->
  #       logger.debug "serial_port drained! with error: #{error}"
  #     )


module.exports = Server
