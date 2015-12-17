async = require 'async'


module.exports = mw =
  makeTestIterator: (testObject) ->
    (func, callback) -> func(testObject, callback)

  getURL: (path) -> 'http://localhost:3001' + path
      
  clearModels: (models) ->
    return (test, cb) ->
      funcs = []
      for model in models
        wrapped = (m) ->
          (callback) ->
            m.remove {}, (err) ->
              callback(err, true)
        funcs.push(wrapped(model))
      async.parallel funcs, cb
      
  initUser: (options) ->
    options = _.extend({prop: 'user', permissions: []}, options)
    doc = {
      email: 'user'+_.uniqueId()+'@gmail.com'
      password: 'password'
      permissions: options.permissions
    }
    return (test, cb) ->
      new User(doc).save (err, admin) ->
        expect(err).toBe(null)
        test[options.prop] = admin
        cb(err)

  loginUser: (options) ->
    options = _.extend({prop: 'user'}, options)
    return (test, cb) ->
      user = test[options.prop]
      form = {
        username: user.get('email')
        password: 'password'
      }
      request.post mw.getURL('/auth/login'), { form: form }, (err, res) ->
        expect(err).toBe(null)
        expect(res.statusCode).toBe(200)
        cb()

  initAdmin: (options) ->
    options = _.extend({prop: 'admin', permissions: ['admin']}, options)
    return @initUser(options)

  loginAdmin: (options) ->
    options = _.extend({prop: 'admin'}, options)
    return @loginUser(options)
    
  initArtisan: (options) ->
    options = _.extend({prop: 'artisan', permissions: ['artisan']}, options)
    return @initUser(options)
    
  loginArtisan: (options) ->
    options = _.extend({prop: 'artisan'}, options)
    return @loginUser(options)
        
  logout: (options) ->
    options = _.extend({}, options)
    return (test, cb) ->
      request.post mw.getURL('/auth/logout'), ->
        cb()
    
  post: (path, options) ->
    options = _.extend({ prop: 'post', json: true }, options)
    prop = options.prop
    delete options.prop
    path = mw.getURL(path)
    return (test, cb) ->
      request.post path, options, (err, res, body) ->
        test[prop] = { err: err, res: res, body: body }
        cb()

  get: (path, options) ->
    options = _.extend({ prop: 'get', json: true }, options)
    prop = options.prop
    delete options.prop
    path = mw.getURL(path)
    return (test, cb) ->
      request.get path, options, (err, res, body) ->
        test[prop] = { err: err, res: res, body: body }
        cb()
        
  put: (path, options) ->
    options = _.extend({ prop: 'put', json: true }, options)
    prop = options.prop
    delete options.prop
    path = mw.getURL(path)
    return (test, cb) ->
      request.put path, options, (err, res, body) ->
        test[prop] = { err: err, res: res, body: body }
        cb()