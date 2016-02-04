utils = require '../lib/utils'
Promise = require 'bluebird'

module.exports.get = (Model, options) ->
  options = _.extend({}, options)

  return (req, res) ->
    utils.run ->
      dbq = Model.find()
    
      dbq.limit(utils.getLimitFromReq(req))
      dbq.skip(utils.getSkipFromReq(req))
      dbq.select(utils.getProjectFromReq(req))
      utils.applyCustomSearchToDBQ(req, dbq)
    
      if Model.schema.uses_coco_translation_coverage and req.query.view is 'i18n-coverage'
        dbq.find({ slug: {$exists: true}, i18nCoverage: {$exists: true} })
    
      results = yield Promise.promisify(utils.viewSearch)(dbq, req)
      res.send(results)
