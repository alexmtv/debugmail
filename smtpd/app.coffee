require 'sugar'
smtp = require "simplesmtp"
models = require "./models"
async = require "async"
MailParser = require("mailparser").MailParser
ProjectModel = models.Project
LetterModel = models.Letter
UserModel = models.User


exports.run = (settings)->
  # Create model instances
  db = settings.getConnection()
  Project = ProjectModel db
  Letter = LetterModel db
  User = UserModel db

  # Create smtp server
  server = smtp.createServer 
    name: 'localhost'
    debug: false
    maxSize: 5 * 1024
    requireAuthentication: true
    disableDNSValidation: true
    authMethods: ['LOGIN', 'PLAIN']

  server.on 'startData', (req)->
    req.parser = new MailParser
    # Save letter
    req.parser.on 'end', (mail)->
      console.log mail
      headers = mail.headers
      if 'date' in headers
        [date, time] = headers.date.split ' '
        [day, month, year] = date.split '/'
        [hour, minute] = time.split ':'
        send_date = Date.create().set
          day: day
          month: month
          year: year
          hour: hour
          minute: minute
      else
        send_date = new Date
      letter = new Letter
        subject: mail.subject
        date: send_date
        sender: headers.from
        to: headers.to
        content: mail.text
        project: req.project._id
        priority: mail.priority
      letter.html = mail.html if 'html' of mail
      delete headers.from
      delete headers.to
      delete headers.subject if 'subject' of headers
      delete headers.date if 'date' of headers
      letter.headers = headers
      console.log letter
      letter.save()


  server.on 'data', (req, chunk)->
    req.parser.write chunk
    
  server.on 'dataReady', (req, cb)->
    req.parser.end()
    cb null, 'OK'

  server.on 'authorizeUser', (req, username, password, cb)->

    async.waterfall [
      (callback)->
        User.findOne {'email': username}, (err, user)->
          if err
            callback err, false
          else if not user
            callback new Error('User was not found.')
          else
            callback null, user

      (user, callback)->
        Project.findOne {user: user._id, password: password}, (err, project)->
          if err
            callback err
          else if not project
            callback new Error('Project was not found.')
          else
            callback null, user, project

    ], (err, user, project)->
      if err
        console.error err
        cb null, false
        return
      req.user = user
      req.project = project
      cb null, true
      

  server.listen 9025

  console.log "Running..."