global.chai = require 'chai'
spies = require 'chai-spies'
# global.Promise = require 'bluebird'
# global.Promise.onPossiblyUnhandledRejection (error) ->
#   console.error(error)
#   throw error

global.expect = chai.expect

chai.use(spies)


# mocha --require coffee-coverage/register --reporter html-cov > coverage.html && open coverage.html
