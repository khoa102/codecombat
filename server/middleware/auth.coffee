# Middleware for both authentication and authorization

respond = require '../commons/respond'

module.exports = {
  checkDocumentPermissions: (req, res, next) ->
    return next() if req.user?.isAdmin()
    if not req.doc.hasPermissionsForMethod(req.user, req.method)
      if req.user
        return respond.forbidden(res, {message: 'You do not have permissions necessary.'})
      return respond.unauthorized(res, {message: 'You must be logged in.'})
    next()
    
  checkHasPermission: (permissions) ->
    if _.isString(permissions)
      permissions = [permissions]
    
    return (req, res, next) ->
      if not req.user
        return respond.unauthorized(res, {message: 'You must be logged in.'})
      if not _.size(_.intersection(req.user.get('permissions'), permissions))
        return respond.forbidden(res, {message: 'You do not have permissions necessary.'})
      next()

}