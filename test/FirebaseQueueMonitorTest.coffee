FirebaseQueueTools = require.main.require 'src'
FirebaseQueueMonitor = FirebaseQueueTools.FirebaseQueueMonitor
Logger = FirebaseQueueTools.Logger
EventEmitter = require 'events'

logger = new Logger(Logger.ERROR)

key = 'randomkey12323'

describe 'FirebaseQueueMonitor', ->
  tasksRef = null
  firebaseQueueMonitor = null
  beforeEach ->
    tasksRef = new EventEmitter()

  describe 'contructor', ->
    describe 'assert params', ->
      it 'tasksRef', ->
        expect(-> new FirebaseQueueMonitor()).to.throw(
          'AssertionError: FirebaseQueueMonitor requires Queue or object with .tasksRef'
        )

    it 'adds default config properties', ->
      config = {}
      firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, config, logger)
      expect(config.startStates).not.to.be.undefined
      expect(config.errorStates).not.to.be.undefined
      expect(config.finishedStates).not.to.be.undefined

    describe 'adds listeners', ->

      it 'child_added', ->
        spy = chai.spy.on(tasksRef, 'on')
        firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
        expect(spy).to.have.been.called.with('child_added')
        tasksRef.on.reset()

      it 'child_removed', ->
        spy = chai.spy.on(tasksRef, 'on')
        firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
        expect(spy).to.have.been.called.with('child_removed')
        tasksRef.on.reset()

      it 'child_changed', ->
        spy = chai.spy.on(tasksRef, 'on')
        firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
        expect(spy).to.have.been.called.with('child_changed')
        tasksRef.on.reset()

    it 'starts snapshot interval', (done) =>
      config = {interval: 200}
      firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, config, logger)
      this.timeout = config.interval + 200
      setTimeout ->
        expect(firebaseQueueMonitor.snapshots.length).to.equal 1
        firebaseQueueMonitor.stopTakingSnapshots()
        done()
      , 205

  describe 'listener logic', ->
    describe 'child_added', ->
      it 'state in startStates', ->
        firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
        spy = chai.spy.on(firebaseQueueMonitor, 'added')
        mockSnapshot = {
          key: key
          child: ->
            val: -> null #null is a start state
        }
        tasksRef.emit 'child_added', mockSnapshot
        expect(spy).to.have.been.called()

      it 'state in progressStates', ->
        firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
        spy = chai.spy.on(firebaseQueueMonitor, 'started')
        mockSnapshot = {
          key: key
          child: ->
            val: -> 'in_progress' #null is a start state
        }
        tasksRef.emit 'child_added', mockSnapshot
        expect(spy).to.have.been.called()

      it 'state in finishedStates', ->
        config = {finishedStates: ['finished']}
        firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, config, logger)
        spy = chai.spy.on(firebaseQueueMonitor, 'finished')
        mockSnapshot = {
          key: key
          child: ->
            val: -> 'finished' #null is a start state
        }
        tasksRef.emit 'child_added', mockSnapshot
        expect(spy).to.have.been.called()

      it 'state in errorStates', ->
        firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
        spy = chai.spy.on(firebaseQueueMonitor, 'errored')
        mockSnapshot = {
          key: key
          child: ->
            val: -> 'error' #null is a start state
        }
        tasksRef.emit 'child_added', mockSnapshot
        expect(spy).to.have.been.called()

    it 'child_removed', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
      spy = chai.spy.on(firebaseQueueMonitor, 'finished')
      mockSnapshot = {
        key: key
      }
      tasksRef.emit 'child_removed', mockSnapshot
      expect(spy).to.have.been.called()

    # uses same logic as child added just test wiring
    it 'child_changed', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
      spy = chai.spy.on(firebaseQueueMonitor, 'errored')
      mockSnapshot = {
        key: key
        child: ->
          val: -> 'error' #null is a start state
      }
      tasksRef.emit 'child_changed', mockSnapshot
      expect(spy).to.have.been.called()

  describe 'functions', ->

    beforeEach ->
      tasksRef = new EventEmitter()
      firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)

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

    it 'getPendingCount', ->
      firebaseQueueMonitor.added(key)
      expect(firebaseQueueMonitor.getPendingCount()).to.equal 1
      firebaseQueueMonitor.added('anotherkey')
      expect(firebaseQueueMonitor.getPendingCount()).to.equal 2
      firebaseQueueMonitor.started(key)
      expect(firebaseQueueMonitor.getPendingCount()).to.equal 1

    it 'getInProgressCount', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
      firebaseQueueMonitor.added(key)
      firebaseQueueMonitor.started(key)
      expect(firebaseQueueMonitor.getInProgressCount()).to.equal 1
      firebaseQueueMonitor.finished(key)
      expect(firebaseQueueMonitor.getInProgressCount()).to.equal 0

    it 'takeSnapshot', ->
      firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, null, logger)
      expect(firebaseQueueMonitor.addedTotal).to.equal 0
      firebaseQueueMonitor.added(1)
      expect(firebaseQueueMonitor.addedTotal).to.equal 1
      firebaseQueueMonitor.takeSnapshot()
      expect(firebaseQueueMonitor.addedIntervalSnapshot).to.equal 1
      expect(firebaseQueueMonitor.snapshots[0].intervalTasksAdded).to.equal 1
      firebaseQueueMonitor.added(2)
      firebaseQueueMonitor.added(3)
      firebaseQueueMonitor.takeSnapshot()
      expect(firebaseQueueMonitor.snapshots[1].intervalTasksAdded).to.equal 2
      expect(firebaseQueueMonitor.addedIntervalSnapshot).to.equal 3

    it.only 'snapshotToString', ->
      snap = {
        time: 1469261748906,
        intervalTasksAdded: 10
        averageRunTime: 4000
        averageWaitTime: 300
        pendingCount: 5
        inProgressCount: 5
      }
      firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, {}, null, logger)
      console.log firebaseQueueMonitor.snapshotToString(snap)


    # it 'startQueue', ->
    #   spy = chai.spy()
    #   queueFactory = ->
    #     {shutdown: spy}
    #   firebaseQueueMonitor = new FirebaseQueueMonitor({tasksRef}, {}, queueFactory, logger)
    #   firebaseQueueMonitor.addOneQueue()
    #   firebaseQueueMonitor.removeOneQueue()
    #   expect(spy).to.have.been.called()
    #   expect(firebaseQueueMonitor.workers.length).to.equal 0


