firebase           = require 'firebase'
# firebase.database.enableLogging(console.log)

connections = {}
module.exports = (fbDatabaseConfig, asUID) ->
  unless asUID
    throw new Error('No asUID paramater passed in.')
  if connection = connections[asUID]
    return connection

  fbDatabaseConfig.databaseAuthVariableOverride.uid = asUID
  connection = firebase.initializeApp(fbDatabaseConfig, asUID)

  database = connection.database()

  if database.now
    throw new Error('Cannot override connection.now')

  database.now = ->
    firebase.database.ServerValue.TIMESTAMP

  return connections[asUID] = database
