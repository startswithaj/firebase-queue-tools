Logger = require './Logger'
logger = new Logger(Logger.LOG)

config = require './config/config'

Firebase = require 'firebase'
FBConnectionFactory = require './FBConnectionFactory'
fbConnection = FBConnectionFactory(config.fbDatabaseConfig, asUID = config.fbSubscriptionUID)


FirebaseQueueManager = require './FirebaseQueueManager'

createSubscriptionTasksRef = fbConnection.ref('user/braintree/createSubscriptionRequestQueue/tasks')

new FirebaseQueueManager(logger, createSubscriptionTasksRef, {})

monitor = require './Monitor'

setInterval ->

  cpu = Math.floor(monitor.cpuLoad().percent * 100)
  console.log "CPU: #{cpu}%"
  console.log monitor.memory()
  mem = Math.floor(monitor.memory().percent * 100)
  console.log "MEM: #{mem}%",

, 10000
