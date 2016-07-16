os = require 'os'
Bluebird = require 'bluebird'

cpuAverage = ->
  totalIdle = 0
  totalTick = 0

  cpus = os.cpus()

  for cpu in cpus
    for type of cpu.times
      totalTick += cpu.times[type]

    totalIdle += cpu.times.idle

  idle    = totalIdle / cpus.length
  total   = totalTick / cpus.length

  return {
    idle
    total
  }


###*
 * @return {Object} dif - difference of usage CPU
 * @return {Float}  dif.idle
 * @return {Float}  dif.total
 * @return {Float}  dif.percent
###
cpuLoad = ->
  start = cpuAverage()
  Bluebird.delay(100).then ->
    end = cpuAverage()
    dif = {}

    dif.idle  = end.idle  - start.idle
    dif.total = end.total - start.total

    dif.percent = 1 - dif.idle / dif.total

    start = cpuAverage()

    return dif

memory = ->
  free = os.freemem()
  total = os.totalmem()
  proc = process.memoryUsage().rss
  new Bluebird(
    (resolve) ->
      resolve {
        percent: (total-free) / total
        free: free / 1024 / 1024
        total: total / 1024 / 1024
        proc: proc / 1024 / 1024
      }
  )

getStats = ->
  Bluebird.join(
    cpuLoad()
    memory()
  ).then (cpu, memory) ->
    return {cpu, memory}

module.exports = {
  cpuAverage
  cpuLoad
  memory
  getStats
}
