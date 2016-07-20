FirebaseQueueTools = require.main.require 'src'
Logger = FirebaseQueueTools.Logger
logger = new Logger(Logger.ERROR)

FirebaseQueueMonitor = FirebaseQueueTools.FirebaseQueueMonitor
FirebaseQueuesManager = FirebaseQueueTools.FirebaseQueuesManager
EventEmitter = require 'events'
# key = 'randomkey12323'
getMockQueue = (name, workerCount) ->
  tasksRef = new EventEmitter()
  tasksRef.toString = -> return name or 'mockQueuePath'

  tasksRef: tasksRef
  getWorkerCount: -> return workerCount



describe.only 'FirebaseQueuesManager', ->
  it 'Constructor', ->
    fbqm = new FirebaseQueuesManager()
    expect(fbqm.logger).not.to.be.undefined
    expect(fbqm.managedQueues).not.to.be.undefined

  describe 'Methods', ->

    describe 'addQueue', ->
      it 'throw when no queue', ->
        fbqm = new FirebaseQueuesManager()
        expect(-> fbqm.addQueue()).to.throw('AssertionError: FirebaseQueuesManager.addQueue requires Queue param')

      it 'throw invalid when no tasksRef', ->
        fbqm = new FirebaseQueuesManager(logger)
        expect(-> fbqm.addQueue({})).to.throw(
          'AssertionError: FirebaseQueuesManager.addQueue must have tasksRef on queue'
        )

      it 'rejects duplicate queues', ->
        mockQueue = getMockQueue()
        fbqm = new FirebaseQueuesManager(logger)
        fbqm.addQueue(mockQueue)
        expect(-> fbqm.addQueue(mockQueue)).to.throw('
          AssertionError: FirebaseQueuesManager.addQueue Already Managing that queue'
        )

      it 'adds a managedQueue', ->
        mockQueue = getMockQueue()
        fbqm = new FirebaseQueuesManager(logger)
        fbqm.addQueue(mockQueue)

        expect(fbqm.managedQueues['mockQueuePath']).not.to.be.undefined
        managedQueue = fbqm.managedQueues['mockQueuePath']
        expect(managedQueue.queue).to.equal mockQueue
        expect(managedQueue.queueMonitor).to.be.instanceof FirebaseQueueMonitor
        expect(managedQueue.minWorkers).to.equal 1

      it 'uses queueMonitor param if it exists', ->
        mockQueue = getMockQueue()
        mockMonitor = {}
        fbqm = new FirebaseQueuesManager(logger)
        fbqm.addQueue(mockQueue, mockMonitor)
        expect(fbqm.managedQueues['mockQueuePath']).not.to.be.undefined
        managedQueue = fbqm.managedQueues['mockQueuePath']
        expect(managedQueue.queue).to.equal mockQueue
        expect(managedQueue.queueMonitor).to.equal mockMonitor
        expect(managedQueue.minWorkers).to.equal 1

      it '_getTotalWorkers', ->
        fbqm = new FirebaseQueuesManager(logger)
        fbqm.addQueue mockQueue1 = getMockQueue('1', 1)
        fbqm.addQueue mockQueue2 = getMockQueue('2', 2)
        expect(mockQueue1.getWorkerCount()).to.equal 1
        expect(fbqm._getTotalWorkers()).to.equal 3
        fbqm.addQueue mockQueue2 = getMockQueue('3', 3)
        expect(fbqm._getTotalWorkers()).to.equal 6

      describe '_canReduceWorkers', ->

        it 'wont allow less than minWorkers', ->
          fbqm = new FirebaseQueuesManager(logger)
          result = fbqm._canReduceWorkers(null, 3, null, null, 3)
          expect(result).to.equal 0
          result = fbqm._canReduceWorkers(null, 2, null, null, 3)
          expect(result).to.equal 0

        it 'returns difference between currently needed workers and totWorkers', ->
          fbqm = new FirebaseQueuesManager(logger)
          # 3 tasks pending * averageSpeed of 3 seconds per tasks means we need 9 workers if thats the current rate
          result = fbqm._canReduceWorkers(3, 12, null, 3, null)
          expect(result).to.equal 3

        it 'returns 0 if tot workers < needed workers', ->
          fbqm = new FirebaseQueuesManager(logger)
          # 3 tasks pending * averageSpeed of 3 seconds per tasks means we need 9 workers if thats the current rate
          result = fbqm._canReduceWorkers(3, 5, null, 3, null)
          expect(result).to.equal 0

      describe '_shouldIncreaseWorkers', ->

        it 'returns number or workers to handle current load', ->
          fbqm = new FirebaseQueuesManager(logger)
          result = fbqm._shouldIncreaseWorkers(3, 6, null, 3, null)
          expect(result).to.equal 3


#   _shouldIncreaseWorkers:  (pendingTasks, totWorkers, peakRcdTasksPS, avgProcTimePerTask, minWorkers) ->
#     peakNeededWorkers = Math.floor(avgProcTimePerTask * peakRcdTasksPS)
#     nowNeededWorkers = Math.floor(pendingTasks * avgProcTimePerTask)
#     if nowNeededWorkers > totWorkers
#       return Math.floor(nowNeededWorkers)

#     if peakNeededWorkers > totWorkers
#       return peakNeededWorkers

#     return 0

#   # aka free system resounces can support another ~x workers
#   _freeWorkerSlots: (cpuUsed, memUsed, totWorkers) ->
#     if cpuUsed > @cpuThreshold or memUsed > @memThreshold
#       @thresholdReachedCB?({cpuUsed, memUsed})
#       return -1

#     mostUsedResource = Math.max(cpuUsed, memUsed)
#     perWorkerUse = mostUsedResource / totWorkers

#     freeResource = 1 - mostUsedResource
#     freeSlots = freeResource / perWorkerUse
#     return Math.floor(freeSlots)


# _getTotalWorkers: ->
#     totWorkers = 0
#     for managedQueue in @managedQueues
#       totWorkers += managedQueue.queue.getWorkerCount()

#   _getTotalNeededWorkers: ->
#     nWorkers = 0
#     for managedQueue in @managedQueues
#       pendingTasks = managedQueue.queueMonitor.getPendingTasksCount()
#       totWorkers = managedQueue.queue.getWorkerCount()
#       prtps = managedQueue.queueMonitor.peakRcdTasksPS()
#       aptps = managedQueue.queueMonitor.avgProcTimePerTask()
#       minWorkers = managedQueue.minWorkers

#       nWorker += @_shouldIncreaseWorkers(pendingTasks, totWorkers, prtps, aptps, minWorkers)
#     return nWorkers

#   _freeUpWorkers: (neededWorkerCount) ->
#     shutdownWorkers = []
#     for managedQueue in @managedQueues
#       pendingTasks = managedQueue.queueMonitor.getPendingTasksCount()
#       totWorkers = managedQueue.getWorkerCount()
#       prtps = managedQueue.queueMonitor.peakRcdTasksPS()
#       aptps = managedQueue.queueMonitor.avgProcTimePerTask()
#       minWorkers = managedQueue.minWorkers

#       removableWorkers = @_canReduceWorkers(pendingTasks, totWorkers, prtps, aptps, minWorkers)
#       i = 0
#       while i < removableWorkers
#         if neededWorkerCount > 0
#           shutdownWorkers.push managedQueue.removeWorker()
#           neededWorkerCount--

#     return shutdownWorkers

#   _allocateNewWorkers: (freeWorkerSlots) ->
#     for managedQueue in @managedQueues
#       unless freeWorkerSlots > 0
#         break

#       pendingTasks = managedQueue.queueMonitor.getPendingTasksCount()
#       totWorkers = managedQueue.getWorkerCount()
#       prtps = managedQueue.queueMonitor.peakRcdTasksPS()
#       aptps = managedQueue.queueMonitor.avgProcTimePerTask()
#       minWorkers = managedQueue.minWorkers

#       neededWorkers = @_shouldIncreaseWorkers(pendingTasks, totWorkers, prtps, aptps, minWorkers)
#       i = 0
#       while i < neededWorkers
#         if freeWorkerSlots > 0
#           managedQueue.addWorker()
#           freeWorkerSlots--

