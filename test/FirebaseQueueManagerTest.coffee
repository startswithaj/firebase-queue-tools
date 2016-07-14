FirebaseQueuesManager = require.main.require 'src/FirebaseQueuesManager'
EventEmitter = require 'events'

key = 'randomkey12323'

describe.only 'FirebaseQueuesManager', ->
  mockTasksRef = null
  firebaseQueueManager = null
  beforeEach ->
    mockTasksRef = new EventEmitter()
    firebaseQueueManager = new FirebaseQueuesManager()

  it 'canSupportAnotherWorker', ->
    # (cpuUsed, memUsed, totalWorkers)
    console.log firebaseQueueManager.canSupportAnotherWorker(0.8, 0.7, 9)
    console.log firebaseQueueManager.canSupportAnotherWorker(0.92, 0.92, 9)
    console.log firebaseQueueManager.canSupportAnotherWorker(0.8, 0.7, 9)
    console.log firebaseQueueManager.canSupportAnotherWorker(0.3, 0.52, 9)
