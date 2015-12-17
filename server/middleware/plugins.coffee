respond = require '../commons/respond'
Handler = require '../commons/Handler'
User = require '../users/User'
sendwithus = require '../sendwithus'
hipchat = require '../hipchat'

module.exports =
  
  viewI18NCoverage: (options) ->
    options = _.extend({}, options)

    return (req, res, next) ->
      return next() unless req.query.view is 'i18n-coverage'
      req.dbq.find({ slug: {$exists: true}, i18nCoverage: {$exists: true} })
      next()
  
      
  viewSearch: (options) ->
    options = _.extend({}, options)

    return (req, res) ->
      # TODO: Enable this? That way there's a way to allow pass this middleware
      # return next() if _.isUndefined(req.query.term)
      
      Model = req.Model

      term = req.query.term
      matchedObjects = []
      filters = if Model.schema.uses_coco_versions or Model.schema.uses_coco_permissions then [filter: {index: true}] else [filter: {}]

      if Model.schema.uses_coco_permissions and req.user
        filters.push {filter: {index: req.user.get('id')}}
        
      for filter in filters
        callback = (err, results) ->
          return respond.internalServerError(res, { message: 'Error fetching search results.', error: err }) if err
          for r in results.results ? results
            obj = r.obj ? r
            continue if obj in matchedObjects  # TODO: probably need a better equality check
            matchedObjects.push obj
          filters.pop()  # doesn't matter which one
          unless filters.length
            res.send matchedObjects
            res.end()

        if term
          filter.filter.$text = $search: term
        else if filters.length is 1 and filters[0].filter?.index is true
            # All we are doing is an empty text search, but that doesn't hit the index,
            # so we'll just look for the slug.
          filter.filter = slug: {$exists: true}
          
        # This try/catch is here to handle when a custom search tries to find by slug. TODO: Fix this more gracefully.
        try
          req.dbq.find filter.filter
        catch
        req.dbq.exec callback
    
        
  extendDocWithParent: (options) ->
    ATTRIBUTES_NOT_INHERITED = ['_id', 'version', 'created', 'creator']
    options = _.extend({prop: 'parent'}, options)

    return (req, res, next) ->
      
      parent = req[options.prop]
      attributes = _.omit(req[options.prop].toObject(), ATTRIBUTES_NOT_INHERITED)
      req.doc.set(attributes)
      next()
      
    
  getLatest: (options) ->
    options = _.extend({}, options)
    
    return (req, res, next) ->
      major = req.body.version?.major
      original = req.parent.get('original')
      if _.isNumber(major)
        query = req.Model.findOne({original: original, 'version.isLatestMinor': true, 'version.major': major})
      else
        query = req.Model.findOne({original: original, 'version.isLatestMajor': true})
      query.select 'version'
      query.exec (err, latest) ->
        if err
          return respond.internalServerError(res, { message: 'Error loading latest version.', error: err })
        
        if latest
          req.latest = latest
          return next()

        # handle the case where no version is marked as latest, since making new
        # versions is not atomic
        if _.isNumber(major)
          q = req.Model.findOne({original: original, 'version.major': major})
          q.sort({'version.minor': -1})
        else
          q = req.Model.findOne({original: original})
          q.sort({'version.major': -1, 'version.minor': -1})
        q.select 'version'
        
        q.exec (err, latest) ->
          if err
            return respond.internalServerError(res, { message: 'Error loading latest version.', error: err })
          if not latest
            return respond.notFound(res, { message: 'Previous version not found.'})
          
          req.latest = latest
          return next()
        
        
  transferLatest: (options) ->
    options = _.extend({}, options)

    return (req, res, next) ->
      # update the last latest version to account for the new version
      major = req.body.version?.major
      version = _.clone(req.latest.get('version'))
      wasLatestMajor = version.isLatestMajor
      version.isLatestMajor = false
      if _.isNumber(major)
        version.isLatestMinor = false
        
      conditions = {_id: req.latest._id}
      doc = {version: version, $unset: {index: 1, slug: 1}}
      
      req.Model.update conditions, doc, (err, raw) ->
        if err
          return respond.internalServerError(res,
            { message: 'Error updating latest version.', error: err })
        if not raw.nModified
          console.error('Conditions', conditions)
          console.error('Doc', doc)
          console.error('Raw response', raw)
          return respond.internalServerError(res,
            { message: 'Latest version could not be modified.' })

        # update the new doc with version, index information
        # Relying heavily on Mongoose schema default behavior here. TODO: Make explicit?
        if _.isNumber(major)
          req.doc.set({
            'version.major': req.latest.version.major
            'version.minor': req.latest.version.minor + 1
            'version.isLatestMajor': wasLatestMajor
          })
          if wasLatestMajor
            req.doc.set('index', true)
          else
            req.doc.set({index: undefined, slug: undefined})
        else
          req.doc.set('version.major', req.latest.version.major + 1)
          req.doc.set('index', true)
          
        req.doc.set('parent', req.latest._id)
        next()

        
  notifyChange: (options) ->
    options = _.extend({}, options)

    return (req, res, next) ->
      editPath = req.headers['x-current-path']
      docLink = "http://codecombat.com#{editPath}"
      
      # Post a message on HipChat
      message = "#{req.user.get('name')} saved a change to <a href=\"#{docLink}\">#{req.doc.get('name')}</a>: #{req.doc.get('commitMessage') or '(no commit message)'}"
      rooms = if /Diplomat submission/.test(message) then ['main'] else ['main', 'artisans']
      hipchat.sendHipChatMessage message, rooms
      
      # Send emails to watchers
      watchers = req.doc.get('watchers') or []
      # Don't send these emails to the person who submitted the patch, or to Nick, George, or Scott.
      watchers = (w for w in watchers when not w.equals(req.user.get('_id')) and not (w + '' in ['512ef4805a67a8c507000001', '5162fab9c92b4c751e000274', '51538fdb812dd9af02000001']))
      return next() unless watchers.length
      User.find({_id:{$in:watchers}}).select({email:1, name:1}).exec (err, watchers) ->
        for watcher in watchers
          context =
            email_id: sendwithus.templates.change_made_notify_watcher
            recipient:
              address: watcher.get('email')
              name: watcher.get('name')
            email_data:
              doc_name: req.doc.get('name') or '???'
              submitter_name: req.user.get('name') or '???'
              doc_link: if editPath then docLink else null
              commit_message: req.doc.get('commitMessage')
          sendwithus.api.send context, _.noop
      
      next() # do not block ending the response