assert = require 'assert'
FirebaseQueueMonitor = require './FirebaseQueueMonitor'

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

    assert !@managedQueues[queuePath], 'FirebaseQueuesManager.addQueue Already Managing that queue'

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
  checkQueues: ->
    @osMonitor.getStats().then (stats) =>
      usedCpuPercent = stats.cpu.percent
      usedMemPercent = stats.memory.percent
      freeWorkerSlots = @_freeWorkerSlots(usedCpuPercent, usedMemPercent, @_getTotalWorkers())

      queueStats = @_getQueueStats()
      neededWorkers = @_getTotalNeededWorkers(queueStats)
      optimalWorkers = @_getTotalOptimalWorkers(queueStats)

      if neededWorkers > freeWorkerSlots
        shutdownWorkers = @_freeUpWorkers(neededWorkers-freeWorkerSlots)
        for shutdownWorker in shutdownWorkers
          shutdownWorker.then =>
            @checkQueues()

      # Allocate what we can
      if freeWorkerSlots > 0
        @_allocateNewWorkers(queueStats, freeWorkerSlots, totalNeeded, optimalWorkers)

  _getQueueStats: ->
    queueStats = []
    for managedQueue in @managedQueues
      queueStat = {}

      pendingTasks = managedQueue.queueMonitor.getPendingTasksCount()
      currentWorkerCount = managedQueue.getWorkerCount()
      prtps = managedQueue.queueMonitor.peakRcdTasksPS()
      aptps = managedQueue.queueMonitor.avgProcTimePerTask()
      minWorkers = managedQueue.minWorkers

      queueStat.canReduce = @_canReduceWorkers(pendingTasks, currentWorkerCount, prtps, aptps, minWorkers)
      queueStat.needIncrease = @_needsMoreWorkers(pendingTasks, currentWorkerCount, prtps, aptps)
      queueStat.optimalIncrease = @_couldUseMoreWorkers(pendingTasks, currentWorkerCount, prtps, aptps)
      queueStat.queue = managedQueue.queue
      queueStats.push queueStat

    return queueStats

  _getTotalWorkers: ->
    currentWorkerCount = 0

    for queuePath, managedQueue of @managedQueues
      currentWorkerCount += managedQueue.queue.getWorkerCount()

    return currentWorkerCount

  _getTotalNeededWorkers: (queueStats) ->
    nWorkers = 0
    for stats in queueStats
      nWorker += stats.needIncrease

    return nWorkers

  _getTotalOptimalWorkers: (queueStats) ->
    nWorkers = 0
    for stats in queueStats
      nWorker += stats.optimalIncrease

    return nWorkers

  _freeUpWorkers: (queueStats, neededWorkerCount) ->
    shutdownWorkers = []
    sumRemovableWorkers = 0
    numberOfQueues = Object.keys(@managedQueues).length

    for stats in queueStats
      sumRemovableWorkers += stats.canReduce

    moreThanEnough = sumRemovableWorkers > neededWorkerCount

    for queuePath, managedQueue of @managedQueues

      workersToRemove = queueStats[queuePath]
      if workersToRemove > 0 and neededWorkerCount > 0
        if moreThanEnough
          # if this queue has 30% of the free workers take 30% of the needed workers from them
          workersToRemove = @_getShareOfRemovableWorkers(sumRemovableWorkers, workersToRemove, neededWorkerCount)

          i = 0
          while i < workersToRemove and neededWorkerCount > 0
            i++
            shutdownWorkers.push managedQueue.removeWorker()
            neededWorkerCount--

    return shutdownWorkers

  _getShareOfRemovableWorkers: (sumRemovableWorkers, removableWorkers, neededWorkerCount) ->
    shareToShutdown = (removableWorkers / sumRemovableWorkers) * neededWorkerCount
    shareToShutdown = Math.ceil(shareToShutdown)

  _allocateNewWorkers: (queueStats, freeWorkerSlots, totalNeeded, optimalWorkers) ->
    allocations = []
    allocatedSum = 0
    for queuePath, stats of queueStats
      if freeWorkerSlots > optimalWorkers
        stats.allocatedWorkers = stats.optimalIncrease
      else if freeWorkerSlots > totalNeeded
        stats.allocatedWorkers = stats.needIncrease
      else
        neededWorkers = stats.needIncrease
        stats.allocatedWorkers = @_getAllocationShare(freeWorkerSlots, neededWorkers, totalNeeded)
        allocatedSum += stats.allocatedWorkers

    # Because we Math.floor the allocation share we want to use up the remainder
    if totalNeeded > freeWorkerSlots and allocatedSum < freeWorkerSlots
      sortedQueueStatsArray = Object.values(queueStats).sort (a, b) ->
        a.needIncrease - b.needIncrease

      while allocatedSum < freeWorkerSlots
        stats = sortedQueueStatsArray.shift()
        stats.allocatedWorkers++
        allocatedSum++
        sortedQueueStatsArray.push stats

    assert allocatedSum <= freeWorkerSlots, '_allocateNewWorkers: allocatedSum must be less than freeWorkerSlots'

    for queuePath, managedQueue of @managedQueue
      allocatedWorkers = queueStats[queuePath].allocatedWorkers
      i = 0
      while i < allocatedWorkers
        managedQueue.queue.addWorker()
        i++

  _getAllocationShare: (freeWorkerSlots, qNeededWorkers, totalNeeded) ->
    Math.floor((qNeededWorkers / totalNeeded) * freeWorkerSlots)


  _canReduceWorkers: (pendingTasks, currentWorkerCount, peakRcdTasksPS, avgProcTimePerTask, minWorkers) ->
    if currentWorkerCount <= minWorkers
      return 0

    if currentWorkerCount > (pendingTasks*avgProcTimePerTask)
      return currentWorkerCount - Math.floor(pendingTasks*avgProcTimePerTask)

    return 0

  _needsMoreWorkers:  (pendingTasks, currentWorkerCount, peakRcdTasksPS, avgProcTimePerTask) ->
    nowNeededWorkers = Math.floor(pendingTasks * avgProcTimePerTask)
    if nowNeededWorkers > currentWorkerCount
      return nowNeededWorkers - currentWorkerCount

    return 0

  _couldUseMoreWorkers: (pendingTasks, currentWorkerCount, peakRcdTasksPS, avgProcTimePerTask) ->
    peakNeededWorkers = Math.floor(avgProcTimePerTask * peakRcdTasksPS)

    if peakNeededWorkers > currentWorkerCount
      return peakNeededWorkers - currentWorkerCount

    return 0

  # aka free system resounces can support another ~x workers
  _freeWorkerSlots: (cpuUsed, memUsed, currentWorkerCount) ->
    if cpuUsed > @cpuThreshold or memUsed > @memThreshold
      @thresholdReachedCB?({cpuUsed, memUsed})
      return -1

    mostUsedResource = Math.max(cpuUsed, memUsed)
    perWorkerUse = mostUsedResource / currentWorkerCount

    freeResource = 1 - mostUsedResource
    freeSlots = freeResource / perWorkerUse
    return Math.floor(freeSlots)
