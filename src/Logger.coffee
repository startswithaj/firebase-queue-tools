module.exports = class Logger

  @LOG:     1
  @WARN:    2
  @ERROR:   3

  constructor: (@acceptedLogLevel = Logger.LOG) ->
    console.log 'Logger: Log Level set to ', @acceptedLogLevel
    return @

  dateStamp: ->
    return "[#{new Date().toLocaleString()}]"

  log: ->
    if Logger.LOG >= @acceptedLogLevel
      console.log.apply console, [@dateStamp()].concat [].splice.call(arguments,0)

  warn: ->
    if Logger.WARN >= @acceptedLogLevel
      console.warn.apply console, [@dateStamp()].concat [].splice.call(arguments,0)

  error: ->
    if Logger.ERROR >= @acceptedLogLevel
      console.error.apply console, [@dateStamp()].concat [].splice.call(arguments,0)

  time: ->
    if Logger.LOG >= @acceptedLogLevel
      console.time.apply console, arguments

  timeEnd: ->
    if Logger.LOG >= @acceptedLogLevel
      console.timeEnd.apply console, arguments
