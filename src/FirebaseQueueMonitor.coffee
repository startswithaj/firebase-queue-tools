assert = require 'assert'
START_TIME = Date.now()

module.exports = class FirebaseQueueManager

  constructor: ({tasksRef}, @config, @logger) ->
    assert tasksRef, 'FirebaseQueueManager requires object with fb tasksRef'

    @logger ?= console
    @config ?= {}

    @config.startStates    ?= [null, undefined]
    @config.progressStates ?= ['in_progress']
    @config.errorStates    ?= ['error']
    @config.finishedStates ?= []
    @config.interval       ?= 10000 # ten seconds

    @pendingTasks   = {}
    @inProgressTasks = {}
    @erroredTasks = {}

    @averageWaitTime = null
    @averageRunTime = null

    @addedTotal = 0
    @addedIntervalSnapshot = 0
    @snapshots = []
    @startTakingSnapShot(@config.interval)

    queueTasksRef.on 'child_added', (snapshot) =>
      @taskAddedOrChanged(snapshot)
    queueTasksRef.on 'child_changed', (snapshot) =>
      @taskAddedOrChanged(snapshot)
    queueTasksRef.on 'child_removed', @taskRemoved

  taskRemoved: (snapshot) =>
    @logger.log "Task #{key} removed"
    key = snapshot.key
    return @finished(key)

  taskAddedOrChanged: (snapshot) =>
    key = snapshot.key
    state = snapshot.child('_state').val()

    if state in @config.startStates
      return @added(key)

    if state in @config.progressStates
      return @started(key)

    if state in @config.finishedStates
      return @finished(key)

    if state in @config.errorStates
      return @errored(key)

    throw new Error("Task state is not recognised #{state}")

  startTakingSnapShot: (interval) ->
    @interval = setInterval @takeSnapshot, interval

  stopTakingSnapshots: ->
    clearInterval @interval

  added: (key) ->
    @logger.log "Task #{key} added"
    unless @pendingTasks[key]
      @addedTotal++
      @pendingTasks[key] = Date.now()

  started: (key) ->
    @logger.log "Task #{key} started"
    if time = @pendingTasks[key]
      taskWaitTime = Date.now() - time

      @logger.log 'task wait time', taskWaitTime
      @logger.log 'average wait time', @averageWaitTime

      @averageWaitTime = if @averageWaitTime then (@averageWaitTime + taskWaitTime) / 2 else taskWaitTime
      delete @pendingTasks[key]

    @inProgressTasks[key] = Date.now()

  errored: (key) ->
    @logger.log "Task #{key} errored"
    delete @pendingTasks[key]
    @erroredTasks[key] = Date.now()

  finished: (key) ->
    @logger.log "Task #{key} finished"
    if time = @inProgressTasks[key]
      taskRunTime = Date.now() - time

      @logger.log 'task run time', taskRunTime
      @logger.log 'average run time', @averageRunTime

      @averageRunTime = if @averageRunTime then (@averageRunTime + taskRunTime) / 2 else taskRunTime
      delete @inProgressTasks[key]

  getPendingCount: ->
    Object.keys(@pendingTasks).length

  getInProgressCount: ->
    Object.keys(@inProgressTasks).length

  takeSnapshot: =>
    addedSinceLastInterval = @addedTotal - @addedIntervalSnapshot
    @addedIntervalSnapshot = @addedTotal
    snapshot = {
      time: Date.now(),
      intervalTasksAdded: addedSinceLastInterval
      averageRunTime: @averageRunTime
      averageWaitTime: @averageWaitTime
      pendingCount: @getPendingCount()
      inProgressCount: @getInProgressCount()
    }

    @snapshots.push snapshot
    @logger.log snapshot

    if @snapshots.length > 200
      @snapshots.shift()

  averageTasksPerSecond: ->
    time = (Date.now() - START_TIME) / 1000
    return @addedTotal / time

  lastSnapShot: ->
    @snapshots[@snapshots.length-1]
