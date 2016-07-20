assert = require 'assert'
Bluebird = require 'bluebird'
FirebaseQueueMonitor = require './FirebaseQueueMonitor'
checkQueueCount = 0
module.exports = class FirebaseQueuesManager

  ###*
   * @param  {Logger}    logger - logger object defaults to console
   * @param  {osMonitor} osMonitor - Monitors and reports cpu and memory usuage
   * @param  {funcition} thresholdReachedCB - Callback that will be called if we hit the cpu or memory thresholds
   * @param  {Float}  cpuThreshold - will stop creating workers once this is reached (0.9 = 90%)
   * @return {Float}  memThreshold - will stop creating workers once this is reached (0.7 = 70%)
   * @return {FirebaseQueuesManager}
  ###
  constructor: (@logger, @osMonitor, @cpuThreshold = 0.9, @memThreshold = 0.9, @thresholdReachedCB) ->
    @logger ?= console

    @managedQueues = []

  addQueue: (queue, queueMonitor, minWorkers = 1, priority) ->
    assert queue, 'FirebaseQueuesManager.addQueue requires Queue param'
    assert queue.tasksRef, 'FirebaseQueuesManager.addQueue must have tasksRef on queue'

    queuePath = queue.tasksRef.toString()

    for managedQueue in @managedQueues
      if queuePath is managedQueue.queue.tasksRef.toString()
        assert false, 'FirebaseQueuesManager.addQueue Already Managing that queue'

    queueMonitor ?= new FirebaseQueueMonitor(queue, null, @logger)
    @managedQueues.push {
      queue
      queueMonitor
      minWorkers
      priority: priority or @managedQueues.length
    }

    @managedQueues.sort (a, b) ->
      a.priority - b.priority

  # This should be run on an interval
  checkQueues: (id) ->
    @logger.log 'FirebaseQueuesManager.checkQueues'
    console.log 'checkQueues', id

    stats = @osMonitor.getStats()
    console.log 'getStats resolved', id
    usedCpuPercent = stats.cpu.percent
    usedMemPercent = stats.memory.percent
    freeWorkerSlots = @_freeWorkerSlots(usedCpuPercent, usedMemPercent, @_sumTotalWorkers())

    queueStats = @_getQueueStats()
    neededWorkers = @_sumTotalNeededWorkers(queueStats)
    optimalWorkers = @_sumTotalOptimalWorkers(queueStats)

    # Allocate what we can
    if freeWorkerSlots > 0
      @logger.log("FirebaseQueuesManager.checkQueues allocating #{freeWorkerSlots} worker slots")
      @_allocateNewWorkers(queueStats, freeWorkerSlots, optimalWorkers)

    if neededWorkers > freeWorkerSlots
      @logger.log("FirebaseQueuesManager.checkQueues
        neededWorkers:#{neededWorkers}, freeWorkerSlots:#{freeWorkerSlots}")
      shutdownWorkerPromises = @_freeUpWorkers(queueStats, neededWorkers-freeWorkerSlots)
      for shutdownWorker in shutdownWorkerPromises
        shutdownWorker.then =>
          console.log 'one shutdown complete'
          @checkQueues(checkQueueCount++)

    return Bluebird.all(shutdownWorkerPromises or [])

  _getQueueStats: ->
    queueStats = []
    for managedQueue in @managedQueues
      queueStat = {}

      currentWorkerCount = managedQueue.queue.getWorkerCount()
      pendingTasks = managedQueue.queueMonitor.getPendingTasksCount()
      prtps = managedQueue.queueMonitor.peakRcdTasksPS()
      aptps = managedQueue.queueMonitor.avgProcTimePerTask()
      minWorkers = managedQueue.minWorkers

      queueStat.canReduce = @_canReduceWorkers(currentWorkerCount, pendingTasks, aptps, prtps, minWorkers)
      queueStat.needIncrease = @_needsMoreWorkers(currentWorkerCount, pendingTasks, aptps, prtps)
      queueStat.optimalIncrease = @_couldUseMoreWorkers(currentWorkerCount, pendingTasks, aptps, prtps)
      queueStat.queue = managedQueue.queue
      # console.log '^^^^^^^^^^^^^^^^^'
      # console.log queueStat.canReduce
      # console.log queueStat.needIncrease
      queueStats.push queueStat

    return queueStats

  _sumTotalWorkers: ->
    currentWorkerCount = 0

    for managedQueue in @managedQueues
      currentWorkerCount += managedQueue.queue.getWorkerCount()

    return currentWorkerCount

  _sumTotalNeededWorkers: (queueStats) ->
    nWorkers = 0
    for stats in queueStats
      nWorkers += stats.needIncrease

    return nWorkers

  _sumTotalOptimalWorkers: (queueStats) ->
    nWorkers = 0
    for stats in queueStats
      nWorkers += stats.optimalIncrease

    return nWorkers

  _freeUpWorkers: (queueStats, neededWorkerCount) ->

    shutdownWorkerPromises = []

    # queue stats are ordered by priority highest to lowest
    # free up from the lowest priotriy first clone/reverse
    for queueStat in queueStats.slice().reverse()
      workersToRemove = queueStat.canReduce
      i = 0
      while i < workersToRemove and neededWorkerCount > 0
        console.log 'shutting down 1 worker'
        shutdownWorkerPromises.push queueStat.queue.shutdownWorker()
        neededWorkerCount--
        i++

    return shutdownWorkerPromises

  _allocateNewWorkers: (queueStats, freeWorkerSlots, optimalWorkers) ->
    for stats in queueStats
      if freeWorkerSlots >= optimalWorkers
        stats.allocatedWorkers = stats.optimalIncrease
      else
        stats.allocatedWorkers = stats.needIncrease

    for stats in queueStats
      i = 0
      while i < stats.allocatedWorkers and freeWorkerSlots > 0
        console.log 'adding 1 worker'
        stats.queue.addWorker()
        freeWorkerSlots--
        i++

  # aka free system resounces can support another ~x workers
  _freeWorkerSlots: (cpuUsed, memUsed, currentWorkerCount) ->
    if cpuUsed > @cpuThreshold or memUsed > @memThreshold
      @thresholdReachedCB?({cpuUsed, memUsed})
      return 0

    mostUsedResource = Math.max(cpuUsed, memUsed)
    mostUsedResourceThreshold = if mostUsedResource is cpuUsed then @cpuThreshold else @memThreshold
    perWorkerUse = mostUsedResource / currentWorkerCount
    # js retarded floating point substraction let 0.9 - 0.8 == 0.0999999998
    freeResource = (mostUsedResourceThreshold * 10 - mostUsedResource * 10) / 10
    freeSlots = Math.round(freeResource / perWorkerUse)

    if freeSlots < 1
      @thresholdReachedCB?({cpuUsed, memUsed})
      return 0
    console.log 'freeslot:', freeSlots
    debugger
    return freeSlots

  _canReduceWorkers: (currentWorkerCount, pendingTasks, avgProcTimePerTask, peakRcdTasksPS, minWorkers) ->
    if currentWorkerCount <= minWorkers
      return 0

    if currentWorkerCount > (pendingTasks*avgProcTimePerTask)
      return (currentWorkerCount - Math.floor(pendingTasks*avgProcTimePerTask)) - minWorkers

    return 0

  _needsMoreWorkers:  (currentWorkerCount, pendingTasks, avgProcTimePerTask, peakRcdTasksPS) ->
    nowNeededWorkers = Math.floor(pendingTasks * avgProcTimePerTask)

    if nowNeededWorkers > currentWorkerCount
      return nowNeededWorkers - currentWorkerCount

    return 0

  _couldUseMoreWorkers: (currentWorkerCount, pendingTasks, avgProcTimePerTask, peakRcdTasksPS) ->
    max = Math.max(pendingTasks, peakRcdTasksPS)
    peakNeededWorkers = Math.floor(avgProcTimePerTask * max)

    if peakNeededWorkers > currentWorkerCount
      return peakNeededWorkers - currentWorkerCount

    return 0

