if Meteor.isClient
  @UserConnections = new Meteor.Collection("user_status_sessions")

  UI.registerHelper "userStatus", UserStatus

  relativeTime = (timeAgo) ->
    diff = moment.utc(TimeSync.serverTime() - timeAgo)
    time = diff.format("H:mm:ss")
    days = +diff.format("DDD") - 1
    ago = (if days then days + "d " else "") + time
    return new Date(timeAgo).toLocaleString() + " - " + ago + " ago"

  Template.login.loggedIn = -> Meteor.userId()

  Template.status.events =
    "submit form.start-monitor": (e, tmpl) ->
      e.preventDefault()
      UserStatus.startMonitor
        threshold: tmpl.find("input[name=threshold]").valueAsNumber
        interval: tmpl.find("input[name=interval]").valueAsNumber
        idleOnBlur: tmpl.find("select[name=idleOnBlur]").value is "true"

    "click .stop-monitor": -> UserStatus.stopMonitor()
    "click .resync": -> TimeSync.resync()

  Template.status.lastActivity = ->
    lastActivity = @lastActivity()
    if lastActivity?
      return relativeTime lastActivity
    else
      return "undefined"

  Template.status.serverTime = -> new Date(TimeSync.serverTime()).toLocaleString()
  Template.status.serverOffset = TimeSync.serverOffset
  Template.status.serverRTT = TimeSync.roundTripTime
  Template.status.isIdle = -> @isIdle() || "false"
  Template.status.isMonitoring = -> @isMonitoring() || "false"

  Template.serverStatus.users = -> Meteor.users.find()
  Template.serverStatus.userClass = -> if @status?.idle then "warning" else "success"

  Template.serverStatus.lastLogin = ->
    lastLogin = @status?.lastLogin
    return unless lastLogin?
    return new Date(lastLogin).toLocaleString()

  Template.serverStatus.lastActivity = ->
    lastActivity = @status?.lastActivity
    if lastActivity?
      return relativeTime lastActivity
    else
      return "(active or not monitoring)"

  Template.serverStatus.connections = -> UserConnections.find(userId: @_id)

  Template.serverConnection.connectionClass = -> if @idle then "warning" else "success"
  Template.serverConnection.loginTime = -> new Date(@loginTime).toLocaleString()
  Template.serverConnection.lastActivity = ->
    lastActivity = @lastActivity
    if lastActivity?
      return relativeTime lastActivity
    else
      return "(active or not monitoring)"

  Template.requestUsername.events =
    "submit form": (e, tmpl) ->
      e.preventDefault()
      input = tmpl.find("input[name=username]")
      input.blur()
      Meteor.insecureUserLogin input.value, (err, res) -> console.log(err) if err

  # Ask for a username as long as we're not logged in
  usernameDialog = null

  Meteor.startup ->
    Deps.autorun ->
      userId = Meteor.userId()
      # Don't recompute this when status fields change
      username = Meteor.users.findOne(userId, fields: {username: 1})?.username

      if username and usernameDialog
        usernameDialog.modal("hide")
        usernameDialog = null
        return

      if !username and usernameDialog is null
        usernameDialog = bootbox.dialog({ message: " " }).html('')
        UI.insert UI.render(Template.requestUsername), usernameDialog[0]
        return

  # Start monitor as soon as we got a signal, captain!
  Deps.autorun ->
    try
      UserStatus.startMonitor
        threshold: 30000
        idleOnBlur: true
      @stop()

if Meteor.isServer
  # Try setting this so it works on meteor.com
  # (https://github.com/oortcloud/unofficial-meteor-faq)
  process.env.HTTP_FORWARDED_COUNT = 1

  Meteor.publish null, ->
    [
      Meteor.users.find { "status.online": true }, # online users only
        fields:
          status: 1,
          username: 1
      UserStatus.connections.find()
    ]
