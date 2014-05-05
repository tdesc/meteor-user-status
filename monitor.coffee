###
  The idle monitor watches for mouse, keyboard, and blur events,
  and reports idle status to the server.

  It uses TimeSync to report accurate time.

  Everything is reactive, of course!
###

# These settings are exported for test only
MonitorInternals = {
  idleThreshold: null
  idleOnBlur: false
}

# This is the function that needs tests
MonitorInternals.computeState = (lastActiveTime, currentTime, isWindowFocused) ->
  inactiveTime = currentTime - lastActiveTime
  return true if MonitorInternals.idleOnBlur and not isWindowFocused
  return if (inactiveTime > MonitorInternals.idleThreshold) then true else false

# State variables
monitorId = null
idle = false
lastActivityTime = undefined

monitorDep = new Deps.Dependency
idleDep = new Deps.Dependency
activityDep = new Deps.Dependency

focused = true
url = ''

getUrl = ->
  c=window.location.pathname
  console.log c
  b=c.slice(0,-1)
  a=c.slice(-1)
  if b=="" then return "/" else if a=="/" then return b else return c;

start = (settings) ->
  throw new Error("Can't start idle monitor until synced to server") unless TimeSync.isSynced()
  throw new Error("Idle monitor is already active. Stop it first.") if monitorId

  settings = settings || {}

  # The amount of time before a user is marked idle
  MonitorInternals.idleThreshold = settings.threshold || 60000

  # Don't check too quickly; it doesn't matter anyway: http://stackoverflow.com/q/15871942/586086
  interval = Math.max(settings.interval || 1000, 1000)

  # Whether blurring the window should immediately cause the user to go idle
  MonitorInternals.idleOnBlur = if ("idleOnBlur" of settings) then settings.idleOnBlur else false

  # Set new monitoring interval
  monitorId = Meteor.setInterval(monitor, interval)
  monitorDep.changed()

  # Reset last activity; can't count inactivity from some arbitrary time
  unless lastActivityTime?
    lastActivityTime = Deps.nonreactive -> TimeSync.serverTime()
    activityDep.changed()

  monitor()
  return

stop = ->
  throw new Error("Idle monitor is not running.") unless monitorId

  Meteor.clearInterval(monitorId)
  monitorId = null
  monitorDep.changed()

  if idle # Un-set any idleness
    idle = false
    idleDep.changed()
    # need to run this because the Deps below won't re-run when monitor is off
    Meteor.call "user-status-active", Deps.nonreactive -> TimeSync.serverTime()

  return

monitor = (setAction) ->
  # Ignore focus/blur events when we aren't monitoring
  return unless monitorId

  # We use setAction here to not have to call serverTime twice. Premature optimization?
  currentTime = Deps.nonreactive -> TimeSync.serverTime()
  return unless currentTime? # Can't monitor if we haven't synced with server yet.

  # Update action as long as we're not blurred and idling on blur
  # We ignore actions that happen while a client is blurred, if idleOnBlur is set.
  if setAction and (focused or !MonitorInternals.idleOnBlur)
    lastActivityTime = currentTime
    activityDep.changed()

  newIdle = MonitorInternals.computeState(lastActivityTime, currentTime, focused)

  if newIdle isnt idle
    idle = newIdle
    idleDep.changed()
  return

touch = ->
  unless monitorId
    Meteor._debug("Cannot touch as idle monitor is not running.")
    return
  monitor(true) # Check for an idle state change right now

isIdle = ->
  idleDep.depend()
  return idle

isMonitoring = ->
  monitorDep.depend()
  return monitorId?

lastActivity = ->
  return unless isMonitoring()
  activityDep.depend()
  return lastActivityTime

Meteor.startup ->
  url = getUrl()
  # Listen for mouse and keyboard events on window
  $(window).on "click keydown", -> monitor(true)

  # catch window blur events when requested and where supported
  # We'll use jQuery here instead of window.blur so that other code can attach blur events:
  # http://stackoverflow.com/q/22415296/586086
  $(window).blur ->
    focused = false
    monitor()

  $(window).focus ->
    focused = true
    monitor() # Does this count as an action?

  # First check initial state if window loaded while blurred
  # Some browsers don't fire focus on load: http://stackoverflow.com/a/10325169/586086
  focused = document.hasFocus()

# Report idle status whenever connection changes
Deps.autorun ->
  # Don't report idle state unless we're logged and we're monitoring
  return unless Meteor.userId() and isMonitoring()

  # XXX These will buffer across a disconnection - do we want that?
  # The idle report will result in a duplicate message (with below)
  # The active report will result in a null op.
  if isIdle()
    Meteor.call "user-status-idle", lastActivityTime
  else
    # If we were inactive, report that we are active again to the server
    Meteor.call "user-status-active", url, lastActivityTime
  return

# If we reconnect and we were idle, make sure we send that upstream
wasConnected = Meteor.status().connected
Deps.autorun ->
  connected = Meteor.status().connected
  # We only need to do something if we reconnect and we are idle
  # Don't get idle status reactively, as this function only
  # takes care of reconnect status and doesn't care if it changes.

  # Note that userId does not change during a resume login, as designed by Meteor.
  # However, a not logged in user will just have this method ignored by the server.
  # TODO when we support anonymous sessions, make sure this still works
  if connected and !wasConnected and idle
    Meteor.call "user-status-idle", lastActivityTime

  wasConnected = connected
  return

# export functions for starting and stopping idle monitor
UserStatus = {
  startMonitor: start
  stopMonitor: stop
  pingMonitor: touch
  isIdle: isIdle
  isMonitoring: isMonitoring
  lastActivity: lastActivity
}
