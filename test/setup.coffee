global.chai = require 'chai'
spies = require 'chai-spies'
# global.Promise = require 'bluebird'
# global.Promise.onPossiblyUnhandledRejection (error) ->
#   console.error(error)
#   throw error

global.expect = chai.expect

chai.use(spies)


# mocha --reporter html-cov > coverage.html && open coverage.html
# require("coffee-coverage").register
#   path: "relative" # sets the amouth of patgsh you see in output none = user.coffee, abbr = s/c/m/user.coffe, full = src/client/model/user.coffee
#   basePath: __dirname + "/../src" #go up to webclient root directory
#   # initAll: true #uncomment if you want to see all files no just files required() in tests
