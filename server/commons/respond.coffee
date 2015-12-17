
errorResponseSchema = {
  type: 'object'
  required: ['errorName', 'code', 'message']
  properties: {
    error: {
      description: 'Error object which the callback returned'
    }
    errorName: {
      type: 'string'
      description: 'Human readable error code name'
    }
    code: {
      type: 'integer'
      description: 'HTTP error code'
    }
    validationErrors: {
      type: 'array'
      description: 'TV4 array of validation error objects'
    }
    message: {
      type: 'string'
      description: 'Human readable descripton of the error'
    }
    property: {
      type: 'string'
      description: 'Property which is related to the error (conflict, validation).'
    }
  }
}

#- 200 responses
# http://en.wikipedia.org/wiki/List_of_HTTP_status_codes#2xx_Success

module.exports.ok = (res, data) ->
  send(res, 200, data)

module.exports.created = (res, data) ->
  send(res, 201, data)

module.exports.noContent = (res) ->
  res.sendStatus(204)


#- 400 client errors 
# http://en.wikipedia.org/wiki/List_of_HTTP_status_codes#4xx_Client_Error

module.exports.unauthorized = (res, details) ->
  # http://stackoverflow.com/questions/1748374/http-401-whats-an-appropriate-www-authenticate-header-value
  
  # Technically, this is an invalid response for 401. HTTP stipulates you need to
  # provide a WWW-Authenticate header which specifies something like "Basic"
  # or "Digest" authentication. But I need *some* code to indicate that the user
  # needs to login so I'm going to use this one. It's the closest one available.

  details = _.extend({ errorName: 'Unauthorized' }, details)
  send(res, 401, details)

module.exports.forbidden = (res, details) ->
  details = _.extend({ errorName: 'Forbidden' }, details)
  send(res, 403, details)

module.exports.notFound = (res, details) ->
  details = _.extend({ errorName: 'Not Found' }, details)
  send(res, 404, details)

module.exports.methodNotAllowed = (res, details) ->
  details = _.extend({ errorName: 'Method Not Allowed' }, details)
  send(res, 405, details)

module.exports.requestTimeout = (res, details) ->
  details = _.extend({ errorName: 'Request Timeout' }, details)
  send(res, 408, details)

module.exports.conflict = (res, details) ->
  details = _.extend({ errorName: 'Conflict' }, details)
  send(res, 409, details)
  
module.exports.unprocessableEntity = (res, details) ->
  details = _.extend({ errorName: 'Unprocessable Entity' }, details)
  if details.validationErrors
    for error in details.validationErrors
      delete error.stack
  send(res, 422, details)



#- 500 errors
# http://en.wikipedia.org/wiki/List_of_HTTP_status_codes#5xx_Server_Error

module.exports.internalServerError = (res, details) ->
  details = _.extend({ errorName: 'Internal Server Error' }, details)
  send(res, 500, details)

module.exports.gatewayTimeout = (res, details) ->
  details = _.extend({ errorName: 'Gateway Timeout' }, details)
  send(res, 504, details)


# All responses should return a JSON object with at least a code value.
send = (res, code, details) ->
  code ?= 500
  if code >= 400
    details.code = code or 500
    valid = tv4.validate(details, errorResponseSchema)
    if not valid
      console.trace()
      console.error('Invalid response object.')
    if details.error
      console.log 'Got an error object?', error
    details = _.omit(details, 'error')
  res.status(code).json(details)

  