# server.coffee
express = require('express')
fs = require('fs')
path = require('path')
http = require('http')
_ = require('../../../client/js/underscore-min.js')
pagehandler = require('./page.coffee')
favicon = require('./favicon.coffee')
passport = require('passport')
OpenIDstrat = require('passport-openid').Strategy


module.exports = (argv) ->
  ###
  This module is used to generate new Smallest Federated Wiki servers.

  To use it, require it in a program and call it with the options you want
  for each server.
  ###
  
  # Helper functions

  authenticated = (req, res, next) ->
    console.log "tryig to check auth"
    if req.isAuthenticated() then next() else res.send(403)

  
  # passport openID config

  passport.serializeUser( (user, done) ->
    done(null, user.id)
  )

  passport.deserializeUser( (id, done) ->
    done(null, {id})
  )

  passport.use(new OpenIDstrat({
    returnURL: 'http://localhost:3000/login/openid/complete',
    realm: 'http://localhost:3000/'
    identifierField: 'identifier'
  },
  ((id, done) ->
    process.nextTick( ->
      done(null, {id})
    )
  )))
  


  # Express configuration

  app = express.createServer()

  app.configure( ->
    app.use(express.cookieParser())
    app.use(express.bodyParser())
    app.use(express.methodOverride())
    app.use(express.session({ secret: 'notsecret'}))
    app.use(passport.initialize())
    app.use(passport.session())
    app.use(app.router)
    app.use(express.static(argv.c))
  )

  app.configure('development', ->
    app.use(express.errorHandler({ dumpExceptions: true, showStack: true }))
    argv.debug = console? and true
  )

  app.configure('production', ->
    app.use(express.errorHandler())
  )

  # Redirects

  app.redirect('index', (req, res) ->
    '/view/welcome-visitors'
  )

  app.redirect('remotefav', (req, res) ->
    console.log req.params
    "http://#{req.params[0]}"
  )

  # Get routes

  app.get('/', (req, res) ->
    res.redirect('index')
  )

  app.get(///^/remote/([a-zA-Z0-9:\.-]+)/([a-z0-9-]+)\.json$///, (req, res) ->
    getopts = {
      host: req.params[0]
      port: 80
      path: "/#{req.params[1]}.json"
    }
    console.log getopts
    http.get(getopts, (resp) ->
      responsedata = ''
      resp.on('data', (chunk) ->
        responsedata += chunk
      )
      resp.on('end', ->
        console.log responsedata
        res.json(JSON.parse(responsedata))
      )
    )
  )

  app.get('*.json', (req, res) ->
    file = req.params[0]
    pagehandler.get(path.join(argv.db, file), (page) =>
      res.json(page)
    )
  )

  app.get('*style.css', (req, res) ->
    res.sendfile("#{argv.r}/server/sinatra/views/style.css")
  )

  app.get(///^(/([a-zA-Z0-9.-]+)/([a-z0-9-]+))+$///, (req, res) ->
    res.sendfile("#{argv.r}/server/sinatra/views/static.html")
  )

  app.get('/plugins/factory.js', (req, res) ->
    catalog = """
              window.catalog = {
                "ByteBeat": {"menu": "8-bit Music by Formula"},
                "MathJax": {"menu": "TeX Formatted Equations"},
                "Calculator": {"menu": "Running Sums for Expenses"}
              };

              """
    fs.readFile("#{argv.r}/client/plugins/meta-factory.js", (err, data) =>
      if err then throw err
      res.header('Content-Type', 'application/javascript')
      res.send(catalog + data)
    )
  )

  app.get('/favicon.png', (req,res) ->
    favicon.get(path.join(argv.status, "favicon.png"), (loc) ->
      res.sendfile(loc)
    )
  )


  app.get('/*', (req, res, next) ->
    file = req.params[0]
    next()
  )

  app.get(///^/remote/([a-zA-Z0-9:\.-]+/favicon.png)$///, (req, res) ->
        res.redirect('remotefav')
  )

  # Put routes

  app.put(/^\/page\/([a-z0-9-]+)\/action$/i, authenticated, (req, res) ->
    action = JSON.parse(req.body.action)
    actionCB = (page) ->
      console.log page if argv.debug
      switch action.type
        when 'move'
          page.story = _(action.order).map((i) ->
            _(page.story).find( (story) ->
              console.log i, story
              i is story.id
            )
          )
          
        when 'add'
          before = -1
          for item, index in page.story
            if item.id is action.after
              before = action.after
          before += 1
          page.story.splice(before, 0, action.item)

        when 'remove'
          page.story = (item for item in page.story when item?.id isnt action.id)

        when 'edit'
          page.story = _(page.story).map( (i) ->
            if i.id is action.id
              action.item
            else
              i
          )

        else
          console.log "Unfamiliar action: #{action}"
      if not page.journal
        page.journal = []
      page.journal.push(action)
      pagehandler.put(path.join(argv.db, req.params[0]), page, (err) =>
        if err then throw err
        res.send('ok')
        console.log 'saved' if argv.debug
      )
    console.log(action) if argv.debug
    # TODO: test action.fork
    if action.fork
      getopts = {
        host: action.fork
        port: 80
        path: "/#{req.params[0]}.json"
      }
      http.get(getopts, (resp) ->
        responsedata = ''
        resp.on('data', (chunk) ->
          responsedata += chunk
        )
        resp.on('end', ->
          console.log responsedata
          actionCB(JSON.parse(responsedata))
        )
      )
    else
      pagehandler.get(path.join(argv.db, req.params[0]), actionCB)
  )

  # Routes used for openID authentication

  app.post('/login',
    passport.authenticate('openid', { failureRedirect: 'index'}),
    (req, res) ->
      res.redirect('index')
  )

  app.post('/logout', (req, res) ->
    req.logout()
    res.redirect('index')
  )

  app.get('/logout', (req, res) ->
    req.logout()
    res.redirect('index')
  )

  app.get('/login/openid/complete',
    passport.authenticate('openid', { failureRedirect: 'index'}),
    (req, res) ->
      res.redirect('index')
  )

  app.listen(argv.p, argv.o if argv.o)

  console.log("Smallest Federated Wiki server listening on #{app.address().port} in mode: #{app.settings.env}")
