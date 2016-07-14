FirebaseQueueMonitor = require.main.require 'src/FirebaseQueueMonitor'
EventEmitter = require 'events'

key = 'randomkey12323'

describe 'FirebaseQueueMonitor', ->
  mockTasksRef = null
  firebaseQueueMonitor = null
  beforeEach ->
    mockTasksRef = new EventEmitter()
    firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})

  describe 'contructor', ->
    describe 'assert params', ->
      it 'queueTasksRef', ->
        expect(-> new FirebaseQueueMonitor()).to.throw(
          'AssertionError: FirebaseQueueMonitor requires queueTasksRef'
        )
      it 'config', ->
        expect(-> new FirebaseQueueMonitor(null, {})).to.throw(
          'AssertionError: FirebaseQueueMonitor requires config obj'
        )

    it 'adds default config properties', ->
      config = {}
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, config)
      expect(config.startStates).not.to.be.undefined
      expect(config.errorStates).not.to.be.undefined
      expect(config.finishedStates).not.to.be.undefined

    describe 'adds listeners', ->

      it 'child_added', ->
        spy = chai.spy.on(mockTasksRef, 'on')
        firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})
        expect(spy).to.have.been.called.with('child_added')
        mockTasksRef.on.reset()

      it 'child_removed', ->
        spy = chai.spy.on(mockTasksRef, 'on')
        firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})
        expect(spy).to.have.been.called.with('child_removed')
        mockTasksRef.on.reset()

      it 'child_changed', ->
        spy = chai.spy.on(mockTasksRef, 'on')
        firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})
        expect(spy).to.have.been.called.with('child_changed')
        mockTasksRef.on.reset()

    it 'starts snapshot interval', (done) =>
      config = {interval: 200}
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, config)
      this.timeout = config.interval + 200
      setTimeout ->
        expect(firebaseQueueMonitor.snapshots.length).to.equal 1
        firebaseQueueMonitor.stopTakingSnapshots()
        done()
      , 205

  describe 'listener logic', ->
    describe 'child_added', ->
      it 'state in startStates', ->
        firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})
        spy = chai.spy.on(firebaseQueueMonitor, 'added')
        mockSnapshot = {
          key: key
          child: ->
            val: -> null #null is a start state
        }
        mockTasksRef.emit 'child_added', mockSnapshot
        expect(spy).to.have.been.called()

      it 'state in progressStates', ->
        firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})
        spy = chai.spy.on(firebaseQueueMonitor, 'started')
        mockSnapshot = {
          key: key
          child: ->
            val: -> 'in_progress' #null is a start state
        }
        mockTasksRef.emit 'child_added', mockSnapshot
        expect(spy).to.have.been.called()

      it 'state in finishedStates', ->
        firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {finishedStates: ['finished']})
        spy = chai.spy.on(firebaseQueueMonitor, 'finished')
        mockSnapshot = {
          key: key
          child: ->
            val: -> 'finished' #null is a start state
        }
        mockTasksRef.emit 'child_added', mockSnapshot
        expect(spy).to.have.been.called()

      it 'state in errorStates', ->
        firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {finishedStates: ['finished']})
        spy = chai.spy.on(firebaseQueueMonitor, 'errored')
        mockSnapshot = {
          key: key
          child: ->
            val: -> 'error' #null is a start state
        }
        mockTasksRef.emit 'child_added', mockSnapshot
        expect(spy).to.have.been.called()

    it 'child_removed', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {finishedStates: ['finished']})
      spy = chai.spy.on(firebaseQueueMonitor, 'finished')
      mockSnapshot = {
        key: key
      }
      mockTasksRef.emit 'child_removed', mockSnapshot
      expect(spy).to.have.been.called()

    # uses same logic as child added just test wiring
    it 'child_changed', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {finishedStates: ['finished']})
      spy = chai.spy.on(firebaseQueueMonitor, 'errored')
      mockSnapshot = {
        key: key
        child: ->
          val: -> 'error' #null is a start state
      }
      mockTasksRef.emit 'child_changed', mockSnapshot
      expect(spy).to.have.been.called()

  describe 'functions', ->

    it 'added', ->
      firebaseQueueMonitor.added(key)
      expect(firebaseQueueMonitor.addedTotal).to.equal 1
      expect(firebaseQueueMonitor.pendingTasks[key]).to.be.Number
      firebaseQueueMonitor.added('anotherkey')
      expect(firebaseQueueMonitor.addedTotal).to.equal 2

    it 'started', (done) ->
      firebaseQueueMonitor.added(key)
      setTimeout ->
        firebaseQueueMonitor.started(key)
        expect(firebaseQueueMonitor.averageWaitTime).to.be.above 100
        expect(firebaseQueueMonitor.pendingTasks[key]).to.be.undefined
        expect(firebaseQueueMonitor.inProgressTasks[key]).to.be.Number
        done()
      , 101

    it 'errored', ->
      firebaseQueueMonitor.added(key)
      firebaseQueueMonitor.started(key)
      firebaseQueueMonitor.errored(key)
      expect(firebaseQueueMonitor.erroredTasks[key]).to.be.Number
      expect(firebaseQueueMonitor.pendingTasks[key]).to.be.undefined

    it 'finished', (done) ->
      firebaseQueueMonitor.added(key)
      firebaseQueueMonitor.started(key)
      setTimeout ->
        firebaseQueueMonitor.finished(key)
        expect(firebaseQueueMonitor.averageRunTime).to.be.above 104
        expect(firebaseQueueMonitor.inProgressTasks[key]).to.be.undefined
        done()
      , 105

    it 'getPending', ->
      firebaseQueueMonitor.added(key)
      expect(firebaseQueueMonitor.getPending()).to.equal 1
      firebaseQueueMonitor.added('anotherkey')
      expect(firebaseQueueMonitor.getPending()).to.equal 2
      firebaseQueueMonitor.started(key)
      expect(firebaseQueueMonitor.getPending()).to.equal 1

    it 'getInProgress', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})
      firebaseQueueMonitor.added(key)
      firebaseQueueMonitor.started(key)
      expect(firebaseQueueMonitor.getInProgress()).to.equal 1
      firebaseQueueMonitor.finished(key)
      expect(firebaseQueueMonitor.getInProgress()).to.equal 0

    it 'takeSnapshot', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})
      expect(firebaseQueueMonitor.addedTotal).to.equal 0
      firebaseQueueMonitor.added(1)
      expect(firebaseQueueMonitor.addedTotal).to.equal 1
      firebaseQueueMonitor.takeSnapshot()
      expect(firebaseQueueMonitor.addedIntervalSnapshot).to.equal 1
      expect(firebaseQueueMonitor.snapshots[0].tasksAdded).to.equal 1
      firebaseQueueMonitor.added(2)
      firebaseQueueMonitor.added(3)
      firebaseQueueMonitor.takeSnapshot()
      expect(firebaseQueueMonitor.snapshots[1].tasksAdded).to.equal 2
      expect(firebaseQueueMonitor.addedIntervalSnapshot).to.equal 3

    it 'startQueue', ->
      spy = chai.spy()
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {}, spy)
      firebaseQueueMonitor.addOneQueue()
      expect(spy).to.have.been.called()
      expect(firebaseQueueMonitor.workers.length).to.equal 1

    it 'startQueue', ->
      spy = chai.spy()
      queueFactory = ->
        {shutdown: spy}
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {}, queueFactory)
      firebaseQueueMonitor.addOneQueue()
      firebaseQueueMonitor.removeOneQueue()
      expect(spy).to.have.been.called()
      expect(firebaseQueueMonitor.workers.length).to.equal 0

    it 'getStats', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor(null, mockTasksRef, {})
      stats = firebaseQueueMonitor.getStats()
      expect(stats.averageWaitTime).to.equal null
      expect(stats.averageRunTime).to.equal null
      expect(stats.loadSnapshots).to.be.Array
      expect(stats.workerCount).to.equal 0
      expect(stats.pendingCount).to.equal 0
      expect(stats.inProgressCount).to.equal 0

