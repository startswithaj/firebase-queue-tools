FirebaseQueueMonitor = require './FirebaseQueueMonitor'

module.exports = class FirebaseQueuesManager

  ###*
   * @param  {Logger}    logger - logger object defaults to console
   * @param  {osMonitor} osMonitor - Monitors and reports cpu and memory usuage
   * @param  {Float}  cpuThreshold - will stop creating workers once this is reached (0.9 = 90%)
   * @return {Float}  memThreshold - will stop creating workers once this is reached (0.7 = 70%)
   * @return {FirebaseQueuesManager}
  ###
  constructor: (@logger, @osMonitor, @cpuThreshold = 0.9, @memThreshold = 0.9) ->
    @logger ?= console
    @managedQueues = {}

  addQueue: (queue, queueMonitor, minWorkers) ->
    queuePath = queue.tasksRef?.toString()

    unless queuePath
      throw new Error('Invalid Queue')
    if @queues[queuePath]
      throw new Error('Already Managing that queue')

    queueMonitor ?= new QueueMonitor(queue)
    @managedQueues[queueRef.toString()] = {
      queue
      queueMonitor
      minWorkers
    }

  # This is run on an interval
  checkQueues: ->
    @osMonitor.getStats().then (stats) =>
      usedCpuPercent = stats.cpu.percent
      usedMemPercent = stats.memory.percent
      freeWorkerSlots = @freeWorkerSlots(usedCpuPercent, usedMemPercent, @getTotalWorkers())

      neededWorkers = @getTotalNeededWorkers()
      if neededWorkers > freeWorkerSlots
        shutdownWorkers = @freeUpWorkers(neededWorkers-freeWorkerSlots)
        for shutdownWorker in shutdownWorkers
          shutdownWorker.then =>
            @checkQueues()

      # Allocate what we can
      if freeWorkerSlots > 0
        @allocateNewWorkers(freeWorkerSlots)

  getTotalWorkers: ->
    totWorkers = 0
    for managedQueue in @managedQueues
      totWorkers += managedQueue.queue.getWorkerCount()

  getTotalNeededWorkers: ->
    nWorkers = 0
    for managedQueue in @managedQueues
      pendingTasks = managedQueue.queueMonitor.getPendingTasksCount()
      totWorkers = managedQueue.queue.getWorkerCount()
      prtps = managedQueue.queueMonitor.peakRcdTasksPS()
      aptps = managedQueue.queueMonitor.avgProcTimePerTask()
      minWorkers = managedQueue.minWorkers

      nWorker += @shouldIncreaseWorkers(pendingTasks, totWorkers, prtps, aptps, minWorkers)
    return nWorkers

  freeUpWorkers: (neededWorkerCount) ->
    shutdownWorkers = []
    for managedQueue in @managedQueues
      pendingTasks = managedQueue.queueMonitor.getPendingTasksCount()
      totWorkers = managedQueue.getWorkerCount()
      prtps = managedQueue.queueMonitor.peakRcdTasksPS()
      aptps = managedQueue.queueMonitor.avgProcTimePerTask()
      minWorkers = managedQueue.minWorkers

      removableWorkers = @canReduceWorkers(pendingTasks, totWorkers, prtps, aptps, minWorkers)
      i = 0
      while i < removableWorkers
        if neededWorkerCount > 0
          shutdownWorkers.push managedQueue.removeWorker()
          neededWorkerCount--

    return shutdownWorkers

  allocateNewWorkers: (freeWorkerSlots) ->
    for managedQueue in @managedQueues
      unless freeWorkerSlots > 0
        break

      pendingTasks = managedQueue.queueMonitor.getPendingTasksCount()
      totWorkers = managedQueue.getWorkerCount()
      prtps = managedQueue.queueMonitor.peakRcdTasksPS()
      aptps = managedQueue.queueMonitor.avgProcTimePerTask()
      minWorkers = managedQueue.minWorkers

      neededWorkers = @shouldIncreaseWorkers(pendingTasks, totWorkers, prtps, aptps, minWorkers)
      i = 0
      while i < neededWorkers
        if freeWorkerSlots > 0
          managedQueue.addWorker()
          freeWorkerSlots--

  canReduceWorkers: (pendingTasks, totWorkers, peakRcdTasksPS, avgProcTimePerTask, minWorkers) ->
    if totWorkers <= minWorkers
      return 0

    if totWorkers > (pendingTasks*avgProcTimePerTask)
      return Math.floor(pendingTasks*avgProcTimePerTask)

    return 0

  shouldIncreaseWorkers:  (pendingTasks, totWorkers, peakRcdTasksPS, avgProcTimePerTask, minWorkers) ->
    peakNeededWorkers = Math.floor(avgProcTimePerTask * peakRcdTasksPS)
    nowNeededWorkers = Math.floor(pendingTasks * avgProcTimePerTask)
    if nowNeededWorkers > totWorkers
      return Math.floor(nowNeededWorkers)

    if peakNeededWorkers > totWorkers
      return peakNeededWorkers

    return 0

  # aka free system resounces can support another ~x workers
  freeWorkerSlots: (cpuUsed, memUsed, totWorkers) ->
    if cpuUsed > @cpuThreshold or memUsed > @memThreshold
      @resourceThresholdReachedCB({cpuUsed, memUsed})
      return -1

    mostUsedResource = Math.max(cpuUsed, memUsed)
    perWorkerUse = mostUsedResource / totWorkers

    freeResource = 1 - mostUsedResource
    freeSlots = freeResource / perWorkerUse
    return Math.floor(freeSlots)


