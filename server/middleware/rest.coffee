utils = require '../lib/utils'
Promise = require 'bluebird'
errors = require '../commons/errors'

module.exports =
  get: (Model, options) ->
    options = _.extend({}, options)
  
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

  post: (Model, options) ->
    options = _.extend({}, options)
    
    return (req, res, next) ->
      utils.run ->
        
        try
          doc = new Model({})
          
          if Model.schema.is_patchable
            watchers = [req.user.get('_id')]
            if req.user.isAdmin()  # https://github.com/codecombat/codecombat/issues/1105
              nick = mongoose.Types.ObjectId('512ef4805a67a8c507000001')
              watchers.push nick unless _.find watchers, (id) -> id.equals nick
            doc.set 'watchers', watchers
      
          if Model.schema.uses_coco_versions
            doc.set('original', doc._id)
            doc.set('creator', req.user._id)
    
          utils.assignBody(req, doc)
          utils.validateDoc(doc)
          doc = yield doc.save()
          res.status(201).send(doc.toObject())

        catch err
          next(err)
        