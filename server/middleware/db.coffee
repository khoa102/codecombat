respond = require '../commons/respond'


module.exports = mw =

  isID: (id) ->
    _.isString(id) and id.length is 24 and id.match(/[a-f0-9]/gi)?.length is 24
  
  setModel: (Model) ->
    return (req, res, next) ->
      req.Model = Model
      next()
      
      
  getDocFromHandle: (options) ->
    options = _.extend({param: 'handle', prop: 'doc'}, {})
    
    return (req, res, next) ->
      handle = req.params[options.param]
      if not handle
        return respond.unprocessableEntity(res, { message: 'No handle provided.' })
      if mw.isID(handle)
        req.dbq.findOne({ _id: handle })
      else
        req.dbq.findOne({ slug: handle })

      req.dbq.exec (err, doc) ->
        if err
          return respond.internalServerError(res, { message: 'Error fetching document.' })
        if not doc
          return respond.notFound(res, { message: 'Document not found.' })
        req[options.prop] = doc
        next(err)
        
        
  returnDoc: (options) ->
    options = _.extend({param: 'handle', prop: 'doc'}, {})
    
    return (req, res) ->
      return respond.ok(res, req.doc.toObject())
    
      
  initDoc: (options) ->
    options = _.extend({}, options)
    
    return (req, res, next) ->
      req.doc = new req.Model({})
      
      if req.Model.schema.is_patchable
        watchers = [req.user.get('_id')]
        if req.user.isAdmin()  # https://github.com/codecombat/codecombat/issues/1105
          nick = mongoose.Types.ObjectId('512ef4805a67a8c507000001')
          watchers.push nick unless _.find watchers, (id) -> id.equals nick
        req.doc.set 'watchers', watchers
        
      if req.Model.schema.uses_coco_versions
        req.doc.set('original', req.doc._id)
        req.doc.set('creator', req.user._id)
        
      next()
      
  
  pickBody: (options) ->
    options = _.extend({}, options)
    
    return (req, res, next) ->
      if _.isEmpty(req.body)
        return respond.unprocessableEntity(res, { message: 'No input' })
        
      props = req.Model.schema.editableProperties.slice()
      
      if req.doc.isNew
        props = props.concat req.Model.schema.postEditableProperties
        
      if req.Model.schema.uses_coco_permissions and req.user
        isOwner = req.doc.getAccessForUserObjectId(req.user._id) is 'owner'
        if req.doc.isNew or isOwner or req.user?.isAdmin()
          props.push 'permissions'

      props.push 'commitMessage' if req.Model.schema.uses_coco_versions
      props.push 'allowPatches' if req.Model.schema.is_patchable
        
      for prop in props
        if (val = req.body[prop])?
          req.doc.set prop, val
        # Hold on, gotta think about that one
        #else if document.get(prop)? and req.method isnt 'PATCH'
        #  document.set prop, 'undefined'

      next()


  validateDoc: (options) ->
    options = _.extend({}, options)
    
    return (req, res, next) ->
      obj = req.doc.toObject()
      # Hack to get saving of Users to work. Probably should replace these props with strings
      # so that validation doesn't get hung up on Date objects in the documents.
      delete obj.dateCreated
      tv4 = require('tv4').tv4
      result = tv4.validateMultiple(obj, req.Model.schema.jsonSchema)
      if not result.valid
        return respond.unprocessableEntity(res, { 
          message: 'JSON-schema validation failed'
          validationErrors: result.errors
        })
      next()
      
      
  saveDoc: (options) ->
    options = _.extend({}, options)
    
    return (req, res, next) ->
      req.doc.save (err) ->
        if err
          if err.name is 'MongoError' and err.code is 11000
            return respond.conflict(res, { message: 'MongoDB conflict error.' })
          # TODO: Better handle plugin save errors?
          if err.code is 422 and err.response
            return respond.unprocessableEntity(res, err.response)
          if err.code is 409 and err.response
            return respond.conflict(res, err.response)
          return next(err)
        next()
        
        
  returnCreatedDoc: (options) ->
    options = _.extend({}, options)

    return (req, res) ->
      respond.created(res, req.doc.toObject())
          
  
  initDBQ: (options) ->
    options = _.extend({}, options)

    return (req, res, next) ->
      req.dbq = req.Model.find()
      next()

      
  limitDBQ: (options) ->
    options = _.extend({
      max: 1000
      default: 100
    }, options)
    
    return (req, res, next) ->
      limit = options.default
      
      if req.query.limit
        limit = parseInt(req.query.limit)
        valid = tv4.validate(limit, {
          type: 'integer'
          maximum: options.max
          minimum: 1
        })
        if not valid
          return respond.unprocessableEntity(res, { message: 'Invalid limit parameter.' })
          
      req.dbq.limit(limit)
      next()
      
      
  skipDBQ: (options) ->
    options = _.extend({
      max: 1000000
      default: 0
    }, options)
    
    return (req, res, next) ->
      offset = options.default
      
      if req.query.skip
        skip = parseInt(req.query.skip)
        valid = tv4.validate(skip, {
          type: 'integer'
          maximum: options.max
          minimum: 0
        })
        if not valid
          return respond.unprocessableEntity(res, { message: 'Invalid sort parameter.' })

      req.dbq.skip(skip)
      next()
      
      
  projectDBQ: (options) ->
    options = _.extend({}, options)
    
    return (req, res, next) ->
      return next() unless req.query.project
      projection = {}
      
      if req.query.project is 'true'
        projection = {original: 1, name: 1, version: 1, description: 1, slug: 1, kind: 1, created: 1, permissions: 1}
      else
        for field in req.query.project.split(',')
          projection[field] = 1
      
      req.dbq.select(projection)
      next()
      
      
  customSearchDBQ: (options) ->
    options = _.extend({}, options)
    specialParameters = ['term', 'project', 'conditions']
    
    return (req, res, next) ->
      return next() unless req.user?.isAdmin()
      return next() unless req.query.filter or req.query.conditions
      
      # admins can send any sort of query down the wire
      # Example URL: http://localhost:3000/db/user?filter[anonymous]=true
      filter = {}
      if 'filter' of req.query
        for own key, val of req.query.filter
          if key not in specialParameters
            try
              filter[key] = JSON.parse(val)
            catch SyntaxError
              return respond.unprocessableEntity(res, { message: "Could not parse filter for key '#{key}'." })
      req.dbq.find(filter)

      # Conditions are chained query functions, for example: query.find().limit(20).sort('-dateCreated')
      # Example URL: http://localhost:3000/db/user?conditions[limit]=20&conditions[sort]="-dateCreated"
      for own key, val of req.query.conditions
        if not req.dbq[key]
          return respond.unprocessableEntity(res, { message: "No query condition '#{key}'." })
        try
          val = JSON.parse(val)
          req.dbq[key](val)
        catch SyntaxError
          return respond.unprocessableEntity(res, { message: "Could not parse condition for key '#{key}'." })
      
      next()

      
  runDBQ: (options) ->
    options = _.extend({ return: false }, options)
    
    return (req, res, next) ->
      req.dbq.exec (err, documents) ->
        return respond.internalServerError(res, { message: 'Error loading from database.', err: err }) if err

        if options.return
          return respond.ok(res, (doc.toObject() for doc in documents))
  
        req.documents = documents
        next()
    