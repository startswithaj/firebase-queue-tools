FirebaseQueueTools = require.main.require 'src'
Logger = FirebaseQueueTools.Logger
logger = new Logger(Logger.WARN)

FirebaseQueueMonitor = FirebaseQueueTools.FirebaseQueueMonitor
FirebaseQueuesManager = FirebaseQueueTools.FirebaseQueuesManager
EventEmitter = require 'events'
# key = 'randomkey12323'
getMockQueue = (name, workerCount) ->
  tasksRef = new EventEmitter()
  tasksRef.toString = -> return name or 'mockQueuePath'

  tasksRef: tasksRef
  getWorkerCount: -> return workerCount



describe 'FirebaseQueuesManager', ->
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

        expect(fbqm.managedQueues[0]).not.to.be.undefined
        managedQueue = fbqm.managedQueues[0]
        expect(managedQueue.queue).to.equal mockQueue
        expect(managedQueue.queueMonitor).to.be.instanceof FirebaseQueueMonitor
        expect(managedQueue.minWorkers).to.equal 1

      it 'uses queueMonitor param if it exists', ->
        mockQueue = getMockQueue()
        mockMonitor = {}
        fbqm = new FirebaseQueuesManager(logger)
        fbqm.addQueue(mockQueue, mockMonitor)
        expect(fbqm.managedQueues[0]).not.to.be.undefined
        managedQueue = fbqm.managedQueues[0]
        expect(managedQueue.queue).to.equal mockQueue
        expect(managedQueue.queueMonitor).to.equal mockMonitor
        expect(managedQueue.minWorkers).to.equal 1

      describe 'priority', ->
        it 'defaults to add order', ->

          mockQueue1 = getMockQueue('one')
          mockQueue2 = getMockQueue('two')
          mockQueue3 = getMockQueue('three')

          fbqm = new FirebaseQueuesManager(logger)
          fbqm.addQueue mockQueue1
          fbqm.addQueue mockQueue2
          fbqm.addQueue mockQueue3

          expect(fbqm.managedQueues[0].priority).to.equal 0
          expect(fbqm.managedQueues[1].priority).to.equal 1
          expect(fbqm.managedQueues[2].priority).to.equal 2
          expect(fbqm.managedQueues[0].queue).to.equal mockQueue1
          expect(fbqm.managedQueues[1].queue).to.equal mockQueue2
          expect(fbqm.managedQueues[2].queue).to.equal mockQueue3

        it 'respects priority argument', ->
          mockQueue1 = getMockQueue('one')
          mockQueue2 = getMockQueue('two')
          mockQueue3 = getMockQueue('three')

          fbqm = new FirebaseQueuesManager(logger)
          fbqm.addQueue mockQueue2, null, null, 2
          fbqm.addQueue mockQueue3, null, null, 3
          fbqm.addQueue mockQueue1, null, null, 1

          expect(fbqm.managedQueues[0].priority).to.equal 1
          expect(fbqm.managedQueues[1].priority).to.equal 2
          expect(fbqm.managedQueues[2].priority).to.equal 3
          expect(fbqm.managedQueues[0].queue).to.equal mockQueue1
          expect(fbqm.managedQueues[1].queue).to.equal mockQueue2
          expect(fbqm.managedQueues[2].queue).to.equal mockQueue3

    describe '_sumTotalWorkers', ->
      it 'no queues', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._sumTotalWorkers()
        expect(result).to.equal 0

      it 'multiple queues', ->
        fbqm = new FirebaseQueuesManager(logger)
        fbqm.addQueue mockQueue1 = getMockQueue('1', 1)
        fbqm.addQueue mockQueue2 = getMockQueue('2', 2)
        expect(mockQueue1.getWorkerCount()).to.equal 1
        expect(fbqm._sumTotalWorkers()).to.equal 3
        fbqm.addQueue mockQueue2 = getMockQueue('3', 3)
        expect(fbqm._sumTotalWorkers()).to.equal 6

    describe '_canReduceWorkers', ->

      it 'wont allow less than minWorkers', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._canReduceWorkers(3, null, null, null, 3)
        expect(result).to.equal 0
        result = fbqm._canReduceWorkers(null, 2, null, null, 3)
        expect(result).to.equal 0

      it 'returns difference between currently needed workers and totWorkers', ->
        fbqm = new FirebaseQueuesManager(logger)
        # 3 tasks pending * averageSpeed of 3 seconds per tasks means we need 9 workers if thats the current rate
        # (currentWorkerCount, pendingTasks, avgProcTimePerTask, peakRcdTasksPS, minWorkers)
        result = fbqm._canReduceWorkers(12, 3, 3)
        expect(result).to.equal 3

      it 'returns 0 if tot workers < needed workers', ->
        fbqm = new FirebaseQueuesManager(logger)
        # 3 tasks pending * averageSpeed of 3 seconds per tasks means we need 9 workers if thats the current rate
        result = fbqm._canReduceWorkers(9, 4, 3)
        expect(result).to.equal 0

    describe '_needsMoreWorkers', ->

      it 'returns number or workers to handle current load', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._needsMoreWorkers(6, 3, 3)
        expect(result).to.equal 3

      it 'returns 0 if no need for more workers even', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._needsMoreWorkers(9, 3, 3)
        expect(result).to.equal 0

      it 'returns 0 if no need for more workers excess', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._needsMoreWorkers(13, 3, 3)
        expect(result).to.equal 0

    describe '_couldUseMoreWorkers', ->
      # 'returns number of workers to cover peak usage per/second or current usage which ever is highest'
      it 'returns number of workers to cover peak usage', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._couldUseMoreWorkers(5, 0, 3, 3)
        expect(result).to.equal 4

      it 'returns number of workers to current usage', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._couldUseMoreWorkers(5, 4, 3, 3)
        expect(result).to.equal 7

      it 'returns 0 if has workers to cover peak usage', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._couldUseMoreWorkers(9, 0, 3, 3)
        expect(result).to.equal 0

    describe '_freeWorkerSlots', ->

      it 'returns returns 0 when cpu threshold reached', ->
        fbqm = new FirebaseQueuesManager(logger, null, null, null)
        result = fbqm._freeWorkerSlots(0.99, null, null)
        expect(result).to.equal 0

      it 'calls thresholdReachedCB when mem threshold reached', ->
        spy = chai.spy()
        fbqm = new FirebaseQueuesManager(logger, null, null, null, spy)
        result = fbqm._freeWorkerSlots(null, 0.91, null)
        expect(spy).to.have.been.called.with({cpuUsed: null, memUsed: 0.91})
        expect(result).to.equal 0

      it 'calls thresholdReachedCB when both thresholds reached', ->
        spy = chai.spy()
        fbqm = new FirebaseQueuesManager(logger, null, null, null, spy)
        result = fbqm._freeWorkerSlots(0.99, 0.91, null)
        expect(spy).to.have.been.called.with({cpuUsed: 0.99, memUsed: 0.91})
        expect(result).to.equal 0

      it 'uses most resource (cpu) to estimate how many more workers can support', ->
        # per worker usages estimate = 0.5 / 10
        # = 0.05
        # Resouce left before overThreshold
        # 0.9 - 0.5
        # = 0.4
        # 0.4 / 0.05
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._freeWorkerSlots(0.5, 0, 10)
        expect(result).to.equal 8

      it 'uses most resource (memory) to estimate how many more workers can support', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._freeWorkerSlots(0, 0.5, 10)
        expect(result).to.equal 8

      it 'uses most resource (memory) to estimate how many more workers can support (high)', ->
        # 0.8 / 200 = .004
        # 0.9 - 0.8 = 0.1
        # 0.1 / 0.004
        # 25
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._freeWorkerSlots(0, 0.8, 200)
        expect(result).to.equal 25

      it 'to estimate how many more workers can support round up', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._freeWorkerSlots(0.5, 0, 1)
        expect(result).to.equal 1

      it 'estimate how many more workers can support round down', ->
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._freeWorkerSlots(0.8, 0, 1)
        expect(result).to.equal 0

      it 'calls thresholdReachedCB when freeslots is 0', ->
        spy = chai.spy()
        fbqm = new FirebaseQueuesManager(logger, null, null, null, spy)
        result = fbqm._freeWorkerSlots(0.8, 0, 1)
        expect(spy).to.have.been.called.with({cpuUsed: 0.8, memUsed: 0})
        expect(result).to.equal 0


    describe '_getQueueStats', ->

      it 'calls @_canReduceWorkers with correct params', ->
        mockQueue = getMockQueue(null, workerCount = 5)
        mockMonitor =
          getPendingTasksCount: -> 2
          peakRcdTasksPS: -> 3
          avgProcTimePerTask: -> 4

        fbqm = new FirebaseQueuesManager(logger)
        spy = chai.spy.on(fbqm, '_canReduceWorkers')
        fbqm.addQueue(mockQueue, mockMonitor)
        result = fbqm._getQueueStats()
        expect(spy).to.have.been.called.with.exactly(workerCount, 2, 4, 3, 1)
        expect(result[0].canReduce).to.equal fbqm._canReduceWorkers(workerCount, 2, 4, 3, 1)


      it 'calls @_needsMoreWorkers with correct params', ->
        mockQueue = getMockQueue(null, workerCount = 5)
        mockMonitor =
          getPendingTasksCount: -> 2
          peakRcdTasksPS: -> 3
          avgProcTimePerTask: -> 4

        fbqm = new FirebaseQueuesManager(logger)
        spy = chai.spy.on(fbqm, '_needsMoreWorkers')
        fbqm.addQueue(mockQueue, mockMonitor)
        result = fbqm._getQueueStats()
        expect(spy).to.have.been.called.with.exactly(workerCount, 2, 4, 3)
        expect(result[0].needIncrease).to.equal fbqm._needsMoreWorkers(workerCount, 2, 4, 3, 1)

      it 'calls @_couldUseMoreWorkers with correct params', ->
        mockQueue = getMockQueue(null, workerCount = 5)
        mockMonitor =
          getPendingTasksCount: -> 2
          peakRcdTasksPS: -> 3
          avgProcTimePerTask: -> 4

        fbqm = new FirebaseQueuesManager(logger)
        spy = chai.spy.on(fbqm, '_couldUseMoreWorkers')
        fbqm.addQueue(mockQueue, mockMonitor)
        result = fbqm._getQueueStats()
        expect(spy).to.have.been.called.with.exactly(workerCount, 2, 4, 3)
        expect(result[0].optimalIncrease).to.equal fbqm._couldUseMoreWorkers(workerCount, 2, 4, 3, 1)

      it 'returns stat obj for each queue in order of priority', ->
        mockQueue1 = getMockQueue('mockQueue1', workerCount = 5)
        mockQueue2 = getMockQueue('mockQueue2', workerCount = 5)
        mockMonitor = ->
          getPendingTasksCount: -> 2
          peakRcdTasksPS: -> 3
          avgProcTimePerTask: -> 4

        fbqm = new FirebaseQueuesManager(logger)
        fbqm.addQueue(mockQueue1, mockMonitor())
        result = fbqm._getQueueStats()
        expect(result.length).to.equal 1
        fbqm.addQueue(mockQueue2, mockMonitor())
        result = fbqm._getQueueStats()
        expect(result[0].queue).to.equal mockQueue1
        expect(result[1].queue).to.equal mockQueue2

      it 'stat obj has queue attached', ->
        mockQueue1 = getMockQueue('mockQueue1', workerCount = 5)
        mockMonitor = ->
          getPendingTasksCount: -> 2
          peakRcdTasksPS: -> 3
          avgProcTimePerTask: -> 4

        fbqm = new FirebaseQueuesManager(logger)
        fbqm.addQueue(mockQueue1, mockMonitor())
        result = fbqm._getQueueStats()
        expect(result[0].queue).to.equal mockQueue1


    describe '_sumTotalNeededWorkers', ->
      it 'empty queueStats', ->
        fbqm = new FirebaseQueuesManager(logger)
        queueStats = fbqm._getQueueStats()
        result = fbqm._sumTotalNeededWorkers(queueStats)
        expect(result).to.equal 0

      it 'single queue stat', ->
        queueStat = {needIncrease: 1}
        queueStats = [queueStat]
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._sumTotalNeededWorkers(queueStats)
        expect(result).to.equal 1

      it 'multiple queue stats', ->
        queueStat = {needIncrease: 1}
        queueStat2 = {needIncrease: 2}
        queueStat3 = {needIncrease: 3}
        queueStats = [queueStat, queueStat2, queueStat3]
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._sumTotalNeededWorkers(queueStats)
        expect(result).to.equal 6

    describe '_sumTotalOptimalWorkers', ->
      it 'empty queueStats', ->
        fbqm = new FirebaseQueuesManager(logger)
        queueStats = fbqm._getQueueStats()
        result = fbqm._sumTotalOptimalWorkers(queueStats)
        expect(result).to.equal 0

      it 'single queue stat', ->
        queueStat = {optimalIncrease: 1}
        queueStats = [queueStat]
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._sumTotalOptimalWorkers(queueStats)
        expect(result).to.equal 1

      it 'multiple queue stats', ->
        queueStat = {optimalIncrease: 1}
        queueStat2 = {optimalIncrease: 2}
        queueStat3 = {optimalIncrease: 4}
        queueStats = [queueStat, queueStat2, queueStat3]
        fbqm = new FirebaseQueuesManager(logger)
        result = fbqm._sumTotalOptimalWorkers(queueStats)
        expect(result).to.equal 7

    describe '_freeUpWorkers', ->

      it 'shuts down only neededWorkerCount', ->
        spy = chai.spy()
        mockQueue = {shutdownWorker: spy}
        queueStat = {canReduce: 100, queue: mockQueue}
        queueStats = [queueStat]
        neededWorkerCount = 10
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._freeUpWorkers(queueStats, neededWorkerCount)
        expect(spy).to.have.been.called.exactly(10)

      it 'shuts down only what each queue canReduce', ->
        spy = chai.spy()
        mockQueue = {shutdownWorker: spy}
        queueStat = {canReduce: 8, queue: mockQueue}
        queueStats = [queueStat]
        neededWorkerCount = 100
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._freeUpWorkers(queueStats, neededWorkerCount)
        expect(spy).to.have.been.called.exactly(8)

      it 'shuts down only what each queue canReduce multiple queues', ->
        spy = chai.spy()
        mockQueue = {shutdownWorker: spy}
        queueStat = {canReduce: 8, queue: mockQueue}
        queueStat2 = {canReduce: 8, queue: mockQueue}
        queueStats = [queueStat, queueStat2]
        neededWorkerCount = 100
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._freeUpWorkers(queueStats, neededWorkerCount)
        expect(spy).to.have.been.called.exactly(16)

      it 'shuts down from lowest priority first', ->
        # _freeUpWorkers expects queueStats to be ordered by priority
        # so it reverses them to remove from lowest priority queues first
        mockQueue1 = {shutdownWorker: chai.spy()}
        mockQueue2 = {shutdownWorker: chai.spy()}
        queueStat = {canReduce: 8, queue: mockQueue1}
        queueStat2 = {canReduce: 8, queue: mockQueue2}
        queueStats = [queueStat, queueStat2]
        neededWorkerCount = 10
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._freeUpWorkers(queueStats, neededWorkerCount)
        expect(mockQueue1.shutdownWorker).to.have.been.called.exactly(2)
        expect(mockQueue2.shutdownWorker).to.have.been.called.exactly(8)

      it 'returns shutdown workers', ->
                # _freeUpWorkers expects queueStats to be ordered by priority
        # so it reverses them to remove from lowest priority queues first
        i = 0
        mockQueue1 = {shutdownWorker: chai.spy(-> return 'shutdownWorker' + i++)}

        queueStat = {canReduce: 8, queue: mockQueue1}
        queueStats = [queueStat]
        neededWorkerCount = 10
        fbqm = new FirebaseQueuesManager(logger)
        results = fbqm._freeUpWorkers(queueStats, neededWorkerCount)
        expect(mockQueue1.shutdownWorker).to.have.been.called.exactly(8)
        y = 0
        for result in results
          expect(result).to.equal 'shutdownWorker' + y
          y++


    describe '_allocateNewWorkers', ->

      it 'allocates optimalIncrease if it can', ->
        queueStat = {optimalIncrease: -1}
        queueStats = [queueStat]
        fbqm = new FirebaseQueuesManager(logger)
        freeWorkerSlots = 10
        optimalWorkers = 9
        fbqm._allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)
        expect(queueStat.allocatedWorkers).to.equal -1


      it 'allocates needIncrease if it has to', ->
        queueStat = {needIncrease: -2}
        queueStats = [queueStat]
        fbqm = new FirebaseQueuesManager(logger)
        freeWorkerSlots = 9
        optimalWorkers = 10
        fbqm._allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)
        expect(queueStat.allocatedWorkers).to.equal -2

      it 'addsWorkers upto needIncrease allocation', ->
        mockQueue1 = {addWorker: chai.spy()}
        queueStat = {needIncrease: 2, queue: mockQueue1}
        queueStats = [queueStat]
        freeWorkerSlots = 5
        optimalWorkers = 10
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)
        expect(mockQueue1.addWorker).to.have.been.called.exactly(2)

      it 'addsWorkers upto needIncrease allocation', ->
        mockQueue1 = {addWorker: chai.spy()}
        queueStat = {optimalIncrease: 5, queue: mockQueue1}
        queueStats = [queueStat]
        freeWorkerSlots = 20
        optimalWorkers = 10
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)
        expect(mockQueue1.addWorker).to.have.been.called.exactly(queueStat.optimalIncrease)

      it 'only allocates up to freeWorkerSlots', ->
        mockQueue1 = {addWorker: chai.spy()}
        queueStat = {needIncrease: 10, queue: mockQueue1}
        queueStats = [queueStat]
        freeWorkerSlots = 5
        optimalWorkers = 10
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)
        expect(mockQueue1.addWorker).to.have.been.called.exactly(freeWorkerSlots)

      it 'addsWorkers upto freeWorkerSlots multiple queues', ->
        mockQueue1 = {addWorker: chai.spy()}
        mockQueue2 = {addWorker: chai.spy()}
        queueStat1 = {needIncrease: 5, queue: mockQueue1}
        queueStat2 = {needIncrease: 5, queue: mockQueue2}
        queueStats = [queueStat1, queueStat2]
        freeWorkerSlots = 8
        optimalWorkers = 10
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)
        expect(mockQueue1.addWorker).to.have.been.called.exactly(5)
        expect(mockQueue2.addWorker).to.have.been.called.exactly(3)

      it 'addsWorkers upto optimal allocation', ->
        mockQueue1 = {addWorker: chai.spy()}
        mockQueue2 = {addWorker: chai.spy()}
        queueStat1 = {needIncrease: 5, optimalIncrease: 10, queue: mockQueue1}
        queueStat2 = {needIncrease: 5, optimalIncrease: 10, queue: mockQueue2}
        queueStats = [queueStat1, queueStat2]
        freeWorkerSlots = 20
        optimalWorkers = 20
        fbqm = new FirebaseQueuesManager(logger)
        fbqm._allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)
        expect(mockQueue1.addWorker).to.have.been.called.exactly(10)
        expect(mockQueue2.addWorker).to.have.been.called.exactly(10)



    describe.only 'checkQueues', ->

      # it 'calls _freeWorkerSlots with osMonitor stats', ->
      #   stats =
      #     cpu: percent: 0.5
      #     memory: percent: 0.5
      #   osMonitorMock = {
      #     getStats: -> Promise.resolve(stats)
      #   }
      #   fbqm = new FirebaseQueuesManager(logger, osMonitorMock)
      #   expect(fbqm.osMonitor).to.equal osMonitorMock
      #   spy = chai.spy.on(fbqm, '_freeWorkerSlots')
      #   fbqm.checkQueues().then ->
      #     expect(spy).to.be.called.with.exactly(0.5, 0.5, 0)


      # it 'calls _freeUpWorkers when neededWorkers > freeWorkerSlots', ->
      #   stats = cpu: {percent: null}, memory: {percent: null}

      #   osMonitorMock = getStats: -> Promise.resolve(stats)
      #   fbqm = new FirebaseQueuesManager(logger, osMonitorMock)
      #   fbqm._freeWorkerSlots = -> return 0
      #   fbqm._sumTotalNeededWorkers = -> return 10
      #   _freeUpWorkersSpy = chai.spy(-> return [])
      #   fbqm._freeUpWorkers = _freeUpWorkersSpy
      #   fbqm.checkQueues().then ->
      #     expect(_freeUpWorkersSpy).to.be.called.with.exactly([], 10)

      # it 'calls _allocateNewWorkers when freeWorkerSlots', ->
      #   stats = cpu: {percent: null}, memory: {percent: null}

      #   osMonitorMock = getStats: -> Promise.resolve(stats)
      #   fbqm = new FirebaseQueuesManager(logger, osMonitorMock)
      #   fbqm._freeWorkerSlots = -> return 10
      #   fbqm._sumTotalNeededWorkers = -> return 10
      #   _allocateNewWorkersSpy = chai.spy(-> return [])
      #   fbqm._allocateNewWorkers = _allocateNewWorkersSpy
      #   fbqm.checkQueues().then ->
      #     expect(_allocateNewWorkersSpy).to.be.called.with.exactly([], 10, 0)

      # it 'calls checkQueues each time a worker shutsdown', ->
      #   stats = cpu: {percent: null}, memory: {percent: null}

      #   osMonitorMock = getStats: -> Promise.resolve(stats)
      #   fbqm = new FirebaseQueuesManager(logger, osMonitorMock)
      #   fbqm._freeWorkerSlots = -> return 0
      #   fbqm._sumTotalNeededWorkers = -> return 2
      #   # returns shutdownWorkerPromises
      #   first = true
      #   _freeUpWorkersSpy = chai.spy(
      #     ->
      #       if first
      #         first = false
      #         return [Promise.resolve(), Promise.resolve()]
      #       return []
      #   )

      #   checkQueuesSpy = chai.spy.on(fbqm, 'checkQueues')
      #   fbqm._freeUpWorkers = _freeUpWorkersSpy
      #   fbqm.checkQueues().then ->
      #     expect(_freeUpWorkersSpy).to.be.called.with.exactly([], 2)
      #     # 3 = first call, + then once for each worker shutdown (2)
      #     expect(checkQueuesSpy).to.be.called.exactly(3)

      # it 'allocate up until cpu threshold', ->
      #   mockQueue = (name) ->
      #     workerCount = 1
      #     tasksRef = {}
      #     tasksRef.toString = -> return name
      #     return {
      #       tasksRef
      #       getWorkerCount: -> return workerCount
      #       addWorker: ->
      #         workerCount++
      #       shutdownWorker: -> workerCount--
      #     }

      #   mockMonitor = ->
      #     getPendingTasksCount: -> 3
      #     peakRcdTasksPS: -> 3
      #     avgProcTimePerTask: -> 3

      #   mockQueue1 = mockQueue('one')
      #   mockQueue2 = mockQueue('two')

      #   osMonitorMock = getStats: ->
      #     perTaskCpu = 0.1
      #     totalWorkers = mockQueue1.getWorkerCount() + mockQueue2.getWorkerCount()
      #     stats = cpu: {percent: perTaskCpu * totalWorkers}, memory: {percent: null}
      #     console.log 'total workers:', totalWorkers
      #     console.log perTaskCpu * totalWorkers
      #     return Promise.resolve(stats)

      #   fbqm = new FirebaseQueuesManager(logger, osMonitorMock)
      #   fbqm.addQueue mockQueue1, mockMonitor()
      #   fbqm.addQueue mockQueue2, mockMonitor()
      #   fbqm.checkQueues().then ->
      #     expect(mockQueue1.getWorkerCount()).to.equal 8
      #     expect(mockQueue2.getWorkerCount()).to.equal 1

      it 're-allocate up until cpu threshold', ->
        mockQueue = (name) ->
          workerCount = 1
          tasksRef = {}
          tasksRef.toString = -> return name
          return {
            tasksRef
            getWorkerCount: -> return workerCount
            addWorker: -> workerCount++
            shutdownWorker: -> workerCount--
          }

        mockMonitor = ->
          getPendingTasksCount: -> 3
          peakRcdTasksPS: -> 3
          avgProcTimePerTask: -> 3

        mockQueueCanReduce3 = (name) ->
          workerCount = 3
          tasksRef = {}
          tasksRef.toString = -> return name
          return {
            tasksRef
            getWorkerCount: -> return workerCount
            addWorker: -> workerCount++
            shutdownWorker: ->
              workerCount--
              Promise.resolve()

          }

        mockMonitorCanReduceThree = ->
          getPendingTasksCount: -> 0
          peakRcdTasksPS: -> 3
          avgProcTimePerTask: -> 3

        mockQueue1 = mockQueue('one')
        mockQueue2 = mockQueue('two')
        mockQueue3 = mockQueueCanReduce3('three')

        osMonitorMock = getStats: ->
          console.log 'getStats called'
          perTaskCpu = 0.1
          totalWorkers = mockQueue1.getWorkerCount() + mockQueue2.getWorkerCount() + mockQueue3.getWorkerCount()
          cpuUse = (perTaskCpu * 10) * totalWorkers / 10
          stats = cpu: {percent: cpuUse}, memory: {percent: null}
          # console.log 'total workers:', totalWorkers
          # console.log 'cpuUse: ', cpuUse

          return stats

        fbqm = new FirebaseQueuesManager(logger, osMonitorMock)
        fbqm.addQueue mockQueue1, mockMonitor()
        fbqm.addQueue mockQueue2, mockMonitor()
        fbqm.addQueue mockQueue3, mockMonitorCanReduceThree()
        fbqm.checkQueues().then ->
          console.log "finished"
          expect(mockQueue1.getWorkerCount()).to.equal 7
          expect(mockQueue2.getWorkerCount()).to.equal 1
          expect(mockQueue3.getWorkerCount()).to.equal 1














  #   # This should be run on an interval
  # checkQueues: ->
  #   @osMonitor.getStats().then (stats) =>
  #     usedCpuPercent = stats.cpu.percent
  #     usedMemPercent = stats.memory.percent
  #     freeWorkerSlots = @_freeWorkerSlots(usedCpuPercent, usedMemPercent, @_sumTotalWorkers())

  #     queueStats = @_getQueueStats()
  #     neededWorkers = @_sumTotalNeededWorkers(queueStats)
  #     optimalWorkers = @_sumTotalOptimalWorkers(queueStats)

  #     if neededWorkers > freeWorkerSlots
  #       shutdownWorkerPromises = @_freeUpWorkers(neededWorkers-freeWorkerSlots)
  #       for shutdownWorker in shutdownWorkerPromises
  #         shutdownWorker.then =>
  #           @checkQueues()

  #     # Allocate what we can
  #     if freeWorkerSlots > 0
  #       @_allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)
