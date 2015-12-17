respond = require '../commons/respond'


module.exports =
  
  viewI18NCoverage: (options) ->
    options = _.extend({}, options)

    return (req, res, next) ->
      return next() unless req.query.view is 'i18n-coverage'
      req.dbq.find({ slug: {$exists: true}, i18nCoverage: {$exists: true} })
      next()
  
      
  viewSearch: (options) ->
    options = _.extend({}, options)

    return (req, res, next) ->
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