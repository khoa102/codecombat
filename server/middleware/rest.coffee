utils = require '../lib/utils'
Promise = require 'bluebird'
errors = require '../commons/errors'
User = require '../users/User'
sendwithus = require '../sendwithus'
hipchat = require '../hipchat'
_ = require 'lodash'

module.exports =
  get: (Model, options={}) ->
    return (req, res, next) ->
      utils.run ->
        try
          dbq = Model.find()
          dbq.limit(utils.getLimitFromReq(req))
          dbq.skip(utils.getSkipFromReq(req))
          dbq.select(utils.getProjectFromReq(req))
          utils.applyCustomSearchToDBQ(req, dbq)
        
          if Model.schema.uses_coco_translation_coverage and req.query.view is 'i18n-coverage'
            dbq.find({ slug: {$exists: true}, i18nCoverage: {$exists: true} })
        
          results = yield Promise.promisify(utils.viewSearch)(dbq, req)
          res.send(results)
          
        catch err
          next(err)

  post: (Model, options={}) ->
    return (req, res, next) ->
      utils.run ->
        try
          doc = utils.initDoc(req, Model)
          utils.assignBody(req, doc)
          utils.validateDoc(doc)
          doc = yield doc.save()
          res.status(201).send(doc.toObject())

        catch err
          next(err)
        
  getByHandle: (Model, options={}) ->
    return (req, res, next) ->
      utils.run ->
        try
          doc = yield Promise.promisify(utils.getDocFromHandle)(req, Model)
          if not doc
            throw new errors.NotFound('Document not found.')
          res.status(200).send(doc.toObject())
          
        catch err
          next(err)
          
  put: (Model, options={}) ->
    return (req, res, next) ->
      utils.run ->
        try
          doc = yield Promise.promisify(utils.getDocFromHandle)(req, Model)
          if not doc
            throw new errors.NotFound('Document not found.')
          
          utils.assignBody(req, doc)
          utils.validateDoc(doc)
          doc = yield doc.save()
          res.status(200).send(doc.toObject())

        catch err
          next(err)
          
  postNewVersion: (Model, options={}) ->
    return (req, res, next) ->
      utils.run ->
        try
          parent = yield Promise.promisify(utils.getDocFromHandle)(req, Model)
          if not parent
            throw new errors.NotFound('Parent not found.')

          doc = utils.initDoc(req, Model)
          ATTRIBUTES_NOT_INHERITED = ['_id', 'version', 'created', 'creator']
          doc.set(_.omit(parent.toObject(), ATTRIBUTES_NOT_INHERITED))
          
          utils.assignBody(req, doc, { unsetMissing: true })
          
          # Get latest version
          major = req.body.version?.major
          original = parent.get('original')
          console.log 'find with original', original, _.isString(original)
          if _.isNumber(major)
            q1 = Model.findOne({original: original, 'version.isLatestMinor': true, 'version.major': major})
          else
            q1 = Model.findOne({original: original, 'version.isLatestMajor': true})
          q1.select 'version'
          latest = yield q1.exec()
          
          if not latest
            # handle the case where no version is marked as latest, since making new
            # versions is not atomic
            if _.isNumber(major)
              q2 = Model.findOne({original: original, 'version.major': major})
              q2.sort({'version.minor': -1})
            else
              q2 = Model.findOne()
              q2.sort({'version.major': -1, 'version.minor': -1})
            q2.select 'version'
            latest = yield q2.exec()
            if not latest
              throw new errors.NotFound('Previous version not found.')

          # Transfer latest version
          major = req.body.version?.major
          version = _.clone(latest.get('version'))
          wasLatestMajor = version.isLatestMajor
          version.isLatestMajor = false
          if _.isNumber(major)
            version.isLatestMinor = false
          
          conditions = {_id: latest._id}
          
          raw = yield Model.update(conditions, {version: version, $unset: {index: 1, slug: 1}})
          if not raw.nModified
            console.error('Conditions', conditions)
            console.error('Doc', doc)
            console.error('Raw response', raw)
            throw new errors.InternalServerError('Latest version could not be modified.')
        
          # update the new doc with version, index information
          # Relying heavily on Mongoose schema default behavior here. TODO: Make explicit?
          if _.isNumber(major)
            doc.set({
              'version.major': latest.version.major
              'version.minor': latest.version.minor + 1
              'version.isLatestMajor': wasLatestMajor
            })
            if wasLatestMajor
              doc.set('index', true)
            else
              doc.set({index: undefined, slug: undefined})
          else
            doc.set('version.major', latest.version.major + 1)
            doc.set('index', true)
        
          doc.set('parent', latest._id)
          
          doc = yield doc.save()

          editPath = req.headers['x-current-path']
          docLink = "http://codecombat.com#{editPath}"
    
          # Post a message on HipChat
          message = "#{req.user.get('name')} saved a change to <a href=\"#{docLink}\">#{doc.get('name')}</a>: #{doc.get('commitMessage') or '(no commit message)'}"
          rooms = if /Diplomat submission/.test(message) then ['main'] else ['main', 'artisans']
          hipchat.sendHipChatMessage message, rooms
    
          # Send emails to watchers
          watchers = doc.get('watchers') or []
          # Don't send these emails to the person who submitted the patch, or to Nick, George, or Scott.
          watchers = (w for w in watchers when not w.equals(req.user.get('_id')) and not (w + '' in ['512ef4805a67a8c507000001', '5162fab9c92b4c751e000274', '51538fdb812dd9af02000001']))
          if watchers.length
            User.find({_id:{$in:watchers}}).select({email:1, name:1}).exec (err, watchers) ->
              for watcher in watchers
                context =
                  email_id: sendwithus.templates.change_made_notify_watcher
                  recipient:
                    address: watcher.get('email')
                    name: watcher.get('name')
                  email_data:
                    doc_name: doc.get('name') or '???'
                    submitter_name: req.user.get('name') or '???'
                    doc_link: if editPath then docLink else null
                    commit_message: doc.get('commitMessage')
                sendwithus.api.send context, _.noop

          res.status(201).send(doc.toObject())
        
        catch err
          next(err)