mw = require '../../middleware'
Article = require '../../models/Article'
respond = require '../../commons/respond'


module.exports.getByHandle = (path, app) ->
  app.get(path,
    mw.db.setModel(Article)
    mw.db.initDBQ()
    mw.db.projectDBQ()
    mw.db.getDocFromHandle()
    mw.db.returnDoc()
  )
  
module.exports.put = (path, app) ->
  app.put(path,
    mw.auth.checkHasPermission('admin')
    mw.db.setModel(Article)
    mw.db.initDBQ()
    mw.db.getDocFromHandle()
    mw.db.pickBody()
    mw.db.validateDoc()
    mw.db.saveDoc()
    mw.db.returnDoc()
  )
  
module.exports.postNewVersion = (path, app) ->
 app.post(path,
   mw.auth.checkHasPermission(['admin', 'artisan'])
   mw.db.setModel(Article)
   mw.db.initDoc()
   mw.db.initDBQ()
   mw.db.getDocFromHandle({ prop: 'parent' })
   mw.plugins.extendDocWithParent({ prop: 'parent' })
   mw.db.pickBody({ unsetMissing: true })
   mw.plugins.getLatest()
   mw.plugins.transferLatest()
   mw.db.saveDoc()
   mw.plugins.notifyChange()
   mw.db.returnCreatedDoc()
 )
