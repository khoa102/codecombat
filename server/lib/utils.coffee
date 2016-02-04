AnalyticsString = require '../analytics/AnalyticsString'
log = require 'winston'
mongoose = require 'mongoose'
config = require '../../server_config'
errors = require '../commons/errors'

module.exports =
  isID: (id) -> _.isString(id) and id.length is 24 and id.match(/[a-f0-9]/gi)?.length is 24

  getCodeCamel: (numWords=3) ->
    # 250 words
    words = 'angry apple arm army art baby back bad bag ball bath bean bear bed bell best big bird bite blue boat book box boy bread burn bus cake car cat chair city class clock cloud coat coin cold cook cool corn crash cup dark day deep desk dish dog door down draw dream drink drop dry duck dust east eat egg enemy eye face false farm fast fear fight find fire flag floor fly food foot fork fox free fruit full fun funny game gate gift glass goat gold good green hair half hand happy heart heavy help hide hill home horse house ice idea iron jelly job jump key king lamp large last late lazy leaf left leg life light lion lock long luck map mean milk mix moon more most mouth music name neck net new next nice night north nose old only open page paint pan paper park party path pig pin pink place plane plant plate play point pool power pull push queen rain ready red rest rice ride right ring road rock room run sad safe salt same sand sell shake shape share sharp sheep shelf ship shirt shoe shop short show sick side silly sing sink sit size sky sleep slow small snow sock soft soup south space speed spell spoon star start step stone stop sweet swim sword table team thick thin thing think today tooth top town tree true turn type under want warm watch water west wide win word yes zoo'.split(' ')
    _.map(_.sample(words, numWords), (s) -> s[0].toUpperCase() + s.slice(1)).join('')

  objectIdFromTimestamp: (timestamp) ->
    # mongoDB ObjectId contains creation date in first 4 bytes
    # So, it can be used instead of a redundant created field
    # http://docs.mongodb.org/manual/reference/object-id/
    # http://stackoverflow.com/questions/8749971/can-i-query-mongodb-objectid-by-date
    # Convert string date to Date object (otherwise assume timestamp is a date)
    timestamp = new Date(timestamp) if typeof(timestamp) == 'string'
    # Convert date object to hex seconds since Unix epoch
    hexSeconds = Math.floor(timestamp/1000).toString(16)
    # Create an ObjectId with that hex timestamp
    mongoose.Types.ObjectId(hexSeconds + "0000000000000000")

  findStripeSubscription: (customerID, options, done) ->
    # Grabs latest subscription (e.g. in case of a resubscribe)
    return done() unless customerID?
    return done() unless options.subscriptionID? or options.userID?
    # Some prepaid tests were calling this in such a way that stripe wasn't defined.
    stripe = require('stripe')(config.stripe.secretKey) unless stripe

    subscriptionID = options.subscriptionID
    userID = options.userID

    subscription = null
    nextBatch = (starting_after, done) ->
      options = limit: 100
      options.starting_after = starting_after if starting_after
      stripe.customers.listSubscriptions customerID, options, (err, subscriptions) ->
        return done(subscription) if err
        return done(subscription) unless subscriptions?.data?.length > 0
        for sub in subscriptions.data
          if subscriptionID? and sub.id is subscriptionID
            unless subscription?.cancel_at_period_end is false
              subscription = sub
          if userID? and sub.metadata?.id is userID
            unless subscription?.cancel_at_period_end is false
              subscription = sub

          # Check for backwards compatible basic subscription search
          # Only recipient subscriptions are currently searched for via userID
          if userID? and not sub.metadata?.id and sub.plan?.id is 'basic'
            subscription ?= sub

          return done(subscription) if subscription?.cancel_at_period_end is false

        if subscriptions.has_more
          nextBatch(subscriptions.data[subscriptions.data.length - 1].id, done)
        else
          done(subscription)
    nextBatch(null, done)

  getAnalyticsStringID: (str, callback) ->
    unless str?
      log.error "getAnalyticsStringID given invalid str param"
      return callback -1
    @analyticsStringCache ?= {}
    return callback @analyticsStringCache[str] if @analyticsStringCache[str]

    insertString = =>
      # http://docs.mongodb.org/manual/tutorial/create-an-auto-incrementing-field/#auto-increment-optimistic-loop
      AnalyticsString.find({}, {_id: 1}).sort({_id: -1}).limit(1).exec (err, documents) =>
        if err?
          log.error "Failed to find next analytics string _id for #{str}"
          return callback -1
        seq = if documents.length > 0 then documents[0]._id + 1 else 1
        doc = new AnalyticsString _id: seq, v: str
        doc.save (err) =>
          if err?
            log.error "Failed to save analytics string ID for #{str}"
            return callback -1
          @analyticsStringCache[str] = seq
          callback seq

    # Find existing string
    AnalyticsString.findOne(v: str).exec (err, document) =>
      if err?
        log.error "Failed to lookup analytics string #{str}"
        return callback -1
      if document
        @analyticsStringCache[str] = document._id
        return callback @analyticsStringCache[str]
      insertString()

  run: (fn) ->
    gen = fn()
    
    next = (err, res) ->
      if err
        return gen.throw(err)
      ret = gen.next(res)
      if ret.done
        return
      if typeof ret.value.then == 'function'
        try
          ret.value.then ((value) ->
            next null, value
            return
          ), next
        catch e
          gen.throw e
      else
        try
          ret.value next
        catch e
          gen.throw e
      return
    
    next()
    return


  getLimitFromReq: (req, options) ->
    options = _.extend({
      max: 1000
      default: 100
    }, options)
    
    limit = options.default
    
    if req.query.limit
      limit = parseInt(req.query.limit)
      valid = tv4.validate(limit, {
        type: 'integer'
        maximum: options.max
        minimum: 1
      })
      if not valid
        throw new errors.UnprocessableEntity('Invalid limit parameter.')
    
    return limit
    

  getSkipFromReq: (req, options) ->
    options = _.extend({
      max: 1000000
      default: 0
    }, options)
  
    skip = options.default
  
    if req.query.skip
      skip = parseInt(req.query.skip)
      valid = tv4.validate(skip, {
        type: 'integer'
        maximum: options.max
        minimum: 0
      })
      if not valid
        throw new errors.UnprocessableEntity('Invalid sort parameter.')
  
    return skip
    

  getProjectFromReq: (req, options) ->
    options = _.extend({}, options)
    return null unless req.query.project
    projection = {}
  
    if req.query.project is 'true'
      projection = {original: 1, name: 1, version: 1, description: 1, slug: 1, kind: 1, created: 1, permissions: 1}
    else
      for field in req.query.project.split(',')
        projection[field] = 1
  
    return projection


  applyCustomSearchToDBQ: (req, dbq) ->
    specialParameters = ['term', 'project', 'conditions']
  
    return unless req.user?.isAdmin()
    return unless req.query.filter or req.query.conditions
  
    # admins can send any sort of query down the wire
    # Example URL: http://localhost:3000/db/user?filter[anonymous]=true
    filter = {}
    if 'filter' of req.query
      for own key, val of req.query.filter
        if key not in specialParameters
          try
            filter[key] = JSON.parse(val)
          catch SyntaxError
            throw new errors.UnprocessableEntity("Could not parse filter for key '#{key}'.")
    dbq.find(filter)
  
    # Conditions are chained query functions, for example: query.find().limit(20).sort('-dateCreated')
    # Example URL: http://localhost:3000/db/user?conditions[limit]=20&conditions[sort]="-dateCreated"
    for own key, val of req.query.conditions
      if not dbq[key]
        throw new errors.UnprocessableEntity("No query condition '#{key}'.")
      try
        val = JSON.parse(val)
        dbq[key](val)
      catch SyntaxError
        throw new errors.UnprocessableEntity("Could not parse condition for key '#{key}'.")

  viewSearch: (dbq, req, done) ->
    Model = dbq.model
    # TODO: Make this function only alter dbq or returns a find. It should not also execute the query.
    term = req.query.term
    matchedObjects = []
    filters = if Model.schema.uses_coco_versions or Model.schema.uses_coco_permissions then [filter: {index: true}] else [filter: {}]
  
    if Model.schema.uses_coco_permissions and req.user
      filters.push {filter: {index: req.user.get('id')}}
  
    for filter in filters
      callback = (err, results) ->
        return done(new errors.InternalServerError('Error fetching search results.', {err: err})) if err
        for r in results.results ? results
          obj = r.obj ? r
          continue if obj in matchedObjects  # TODO: probably need a better equality check
          matchedObjects.push obj
        filters.pop()  # doesn't matter which one
        unless filters.length
          done(null, matchedObjects)
  
      if term
        filter.filter.$text = $search: term
      else if filters.length is 1 and filters[0].filter?.index is true
        # All we are doing is an empty text search, but that doesn't hit the index,
        # so we'll just look for the slug.
        filter.filter = slug: {$exists: true}
  
      # This try/catch is here to handle when a custom search tries to find by slug. TODO: Fix this more gracefully.
      try
        dbq.find filter.filter
      catch
      dbq.exec callback
    
    