require '../common'
mw = require '../middleware'
async = require 'async'

describe 'GET /db/article', ->
  articleData1 = { name: 'Article 1', body: 'Article 1 body cow', i18nCoverage: [] }
  articleData2 = { name: 'Article 2', body: 'Article 2 body moo' }
  
  beforeEach (done) ->
    async.eachSeries([
      mw.clearModels([Article])
      mw.initAdmin()
      mw.loginAdmin()
      mw.post('/db/article', { json: articleData1 })
      mw.post('/db/article', { json: articleData2 })
      mw.logout()
    ], mw.makeTestIterator(@), done)
  

  it 'returns an array of Article objects', (done) ->
    url = getURL('/db/article')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(body.length).toBe(2)
      done()


  it 'accepts a limit parameter', (done) ->
    url = getURL('/db/article?limit=1')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(body.length).toBe(1)
      done()
  

  it 'returns 422 for an invalid limit parameter', (done) ->
    url = getURL('/db/article?limit=word')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(res.statusCode).toBe(422)
      done()
  

  it 'accepts a skip parameter', (done) ->
    url = getURL('/db/article?skip=1')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(body.length).toBe(1)
      url = getURL('/db/article?skip=2')
      request.get {uri: url, json: true}, (err, res, body) ->
        expect(body.length).toBe(0)
        done()
  

  it 'returns 422 for an invalid skip parameter', (done) ->
    url = getURL('/db/article?skip=???')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(res.statusCode).toBe(422)
      done()
  

  it 'accepts a custom project parameter', (done) ->
    url = getURL('/db/article?project=name,body')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(body.length).toBe(2)
      for doc in body
        expect(_.size(_.xor(_.keys(doc), ['_id', 'name', 'body']))).toBe(0)
      done()


  it 'returns a default projection if project is "true"', (done) ->
    url = getURL('/db/article?project=true')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(res.statusCode).toBe(200)
      expect(body.length).toBe(2)
      expect(body[0].body).toBeUndefined()
      expect(body[0].version).toBeDefined()
      done()
    
      
  it 'accepts custom filter parameters', (done) ->
    async.eachSeries([
      mw.loginAdmin()
      (test, cb) ->
        url = getURL('/db/article?filter[slug]="article-1"')
        request.get {uri: url, json: true}, (err, res, body) ->
          expect(body.length).toBe(1)
          cb()
    ], mw.makeTestIterator(@), done)
  

  it 'ignores custom filter parameters for non-admins', (done) ->
    async.eachSeries([
      mw.initUser()
      mw.loginUser()
      (test, cb) ->
        url = getURL('/db/article?filter[slug]="article-1"')
        request.get {uri: url, json: true}, (err, res, body) ->
          expect(body.length).toBe(2)
          cb()
    ], mw.makeTestIterator(@), done)
  
    
  it 'accepts custom condition parameters', (done) ->
    async.eachSeries([
      mw.loginAdmin()
      (test, cb) ->
        url = getURL('/db/article?conditions[select]="slug body"')
        request.get {uri: url, json: true}, (err, res, body) ->
          expect(body.length).toBe(2)
          for doc in body
            expect(_.size(_.xor(_.keys(doc), ['_id', 'slug', 'body']))).toBe(0)
          cb()
    ], mw.makeTestIterator(@), done)
  
    
  it 'ignores custom condition parameters for non-admins', (done) ->
    async.eachSeries([
      mw.initUser()
      mw.loginUser()
      (test, cb) ->
        url = getURL('/db/article?conditions[select]="slug body"')
        request.get {uri: url, json: true}, (err, res, body) ->
          expect(body.length).toBe(2)
          for doc in body
            expect(doc.name).toBeDefined()
          cb()
    ], mw.makeTestIterator(@), done)
  
    
  it 'allows non-admins to view by i18n-coverage', (done) ->
    url = getURL('/db/article?view=i18n-coverage')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(body.length).toBe(1)
      expect(body[0].slug).toBe('article-1')
      done()
  

  it 'allows non-admins to search by text', (done) ->
    url = getURL('/db/article?term=moo')
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(body.length).toBe(1)
      expect(body[0].slug).toBe('article-2')
      done()


describe 'POST /db/article', ->
  
  articleData = { name: 'Article', body: 'Article', otherProp: 'not getting set' }
  
  beforeEach (done) ->
    async.eachSeries([
      mw.clearModels([Article])
      mw.initAdmin()
      mw.loginAdmin()
      mw.post('/db/article', { json: articleData })
    ], mw.makeTestIterator(@), done)
    
  
  it 'creates a new Article, returning 201', (done) ->
    expect(@post.res.statusCode).toBe(201)
    Article.findById(@post.body._id).exec (err, article) ->
      expect(err).toBe(null)
      expect(article).toBeDefined()
      done()
      
  
  it 'sets creator to the user who created it', ->
    expect(@post.res.body.creator).toBe(@admin.id)
    
  
  it 'sets original to _id', ->
    body = @post.res.body
    expect(body.original).toBe(body._id)
    
  
  it 'returns 422 when no input is provided', (done) ->
    url = getURL('/db/article')
    request.post { uri: url }, (err, res, body) ->
      expect(res.statusCode).toBe(422)
      done()

      
  it 'allows you to set Article\'s editableProperties', ->
    expect(@post.body.name).toBe('Article')
    
  
  it 'ignores properties not included in editableProperties', ->
    expect(@post.body.otherProp).toBeUndefined()
  
    
  it 'returns 422 when properties do not pass validation', (done) ->
    url = getURL('/db/article')
    json = { i18nCoverage: 9001 }
    request.post { uri: url, json: json }, (err, res, body) ->
      expect(res.statusCode).toBe(422)
      expect(body.validationErrors).toBeDefined()
      done()

      
  it 'allows admins to create Articles', -> # handled in beforeEach
  
    
  it 'allows artisans to create Articles', (done) ->
    async.eachSeries([
      mw.clearModels([Article])
      mw.initArtisan()
      mw.loginArtisan()
      mw.post('/db/article', { json: articleData })
      (test, cb) ->
        expect(test.post.res.statusCode).toBe(201)
        cb()
    ], mw.makeTestIterator(@), done)
  
  
  it 'does not allow normal users to create Articles', (done) ->
    async.eachSeries([
      mw.clearModels([Article])
      mw.initUser()
      mw.loginUser()
      mw.post('/db/article', { json: articleData })
      (test, cb) ->
        expect(test.post.res.statusCode).toBe(403)
        cb()
    ], mw.makeTestIterator(@), done)
  
    
  it 'does not allow anonymous users to create Articles', (done) ->
    async.eachSeries([
      mw.clearModels([Article])
      mw.logout()
      mw.post('/db/article', { json: articleData })
      (test, cb) ->
        expect(test.post.res.statusCode).toBe(401)
        cb()
    ], mw.makeTestIterator(@), done)
  
  
  it 'does not allow creating Articles with reserved words', (done) ->
    url = getURL('/db/article')
    json = { name: 'Names' }
    request.post { uri: url, json: json }, (err, res, body) ->
      expect(res.statusCode).toBe(422)
      done()
  
      
  it 'does not allow creating a second article of the same name', (done) ->
    url = getURL('/db/article')
    request.post { uri: url, json: articleData }, (err, res, body) ->
      expect(res.statusCode).toBe(409)
      done()
      
      
describe 'GET /db/article/:handle', ->

  articleData = { name: 'Some Name', body: 'Article', otherProp: 'not getting set' }

  beforeEach (done) ->
    async.eachSeries([
      mw.clearModels([Article])
      mw.initAdmin()
      mw.loginAdmin()
      mw.post('/db/article', { json: articleData })
      mw.logout()
    ], mw.makeTestIterator(@), done)
    
    
  it 'returns Article by id', (done) ->
    url = getURL("/db/article/#{@post.body._id}")
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(res.statusCode).toBe(200)
      expect(_.isObject(body)).toBe(true)
      done()
      
      
  it 'returns Article by slug', (done) ->
    url = getURL("/db/article/some-name")
    request.get {uri: url, json: true}, (err, res, body) ->
      expect(res.statusCode).toBe(200)
      expect(_.isObject(body)).toBe(true)
      done()
      
      
  it 'returns not found if handle does not exist in the db', (done) ->
    url = getURL("/db/article/dne")
    request.get {uri: url, json: true}, (err, res) ->
      expect(res.statusCode).toBe(404)
      done()
      
      
describe 'PUT /db/article/:handle', ->

  articleData = { name: 'Some Name', body: 'Article' }

  beforeEach (done) ->
    async.eachSeries([
      mw.clearModels([Article])
      mw.initAdmin()
      mw.loginAdmin()
      mw.post('/db/article', { json: articleData })
    ], mw.makeTestIterator(@), done)
    
  
  it 'edits editable Article properties', (done) ->
    url = getURL("/db/article/#{@post.body._id}")
    json = { body: 'New body' }
    request.put {uri: url, json: json}, (err, res, body) ->
      expect(body.body).toBe('New body')
      done()
      
      
  it 'updates the slug when the name is changed', (done) ->
    url = getURL("/db/article/#{@post.body._id}")
    json = { name: 'New name' }
    request.put {uri: url, json: json}, (err, res, body) ->
      expect(body.name).toBe('New name')
      expect(body.slug).toBe('new-name')
      done()
      
      
  it 'does not allow normal artisan, non-admins to make changes', (done) ->
    async.eachSeries([
      mw.initArtisan()
      mw.loginArtisan()
      mw.put('/db/article', { json: { name: 'Another name' } })
      (test, cb) ->
        expect(test.put.res.statusCode).toBe(403)
        cb()
    ], mw.makeTestIterator(@), done)

#xdescribe '/db/article', ->
#  request = require 'request'
#  it 'clears the db first', (done) ->
#    clearModels [User, Article], (err) ->
#      throw err if err
#      done()
#
#  article = {name: 'Yo', body: 'yo ma'}
#  article2 = {name: 'Original', body: 'yo daddy'}
#
#  url = getURL('/db/article')
#  articles = {}
#
#  it 'allows admins to make new minor versions', (done) ->
#    new_article = _.clone(articles[0])
#    new_article.body = 'yo daddy'
#    request.post {uri: url, json: new_article}, (err, res, body) ->
#      expect(res.statusCode).toBe(200)
#      expect(body.version.major).toBe(0)
#      expect(body.version.minor).toBe(1)
#      expect(body._id).not.toBe(articles[0]._id)
#      expect(body.parent).toBe(articles[0]._id)
#      expect(body.creator).toBeDefined()
#      articles[1] = body
#      done()
#
#  it 'allows admins to make new major versions', (done) ->
#    new_article = _.clone(articles[1])
#    delete new_article.version
#    request.post {uri: url, json: new_article}, (err, res, body) ->
#      expect(res.statusCode).toBe(200)
#      expect(body.version.major).toBe(1)
#      expect(body.version.minor).toBe(0)
#      expect(body._id).not.toBe(articles[1]._id)
#      expect(body.parent).toBe(articles[1]._id)
#      articles[2] = body
#      done()
#
#  it 'grants access for regular users', (done) ->
#    loginJoe ->
#      request.get {uri: url+'/'+articles[0]._id}, (err, res, body) ->
#        body = JSON.parse(body)
#        expect(res.statusCode).toBe(200)
#        expect(body.body).toBe(articles[0].body)
#        done()
#
#  it 'does not allow regular users to make new versions', (done) ->
#    new_article = _.clone(articles[2])
#    request.post {uri: url, json: new_article}, (err, res, body) ->
#      expect(res.statusCode).toBe(403)
#      done()
#
#  it 'allows name changes from one version to the next', (done) ->
#    loginAdmin ->
#      new_article = _.clone(articles[0])
#      new_article.name = 'Yo mama now is the larger'
#      request.post {uri: url, json: new_article}, (err, res, body) ->
#        expect(res.statusCode).toBe(200)
#        expect(body.name).toBe(new_article.name)
#        done()
#
#  it 'get schema', (done) ->
#    request.get {uri: url+'/schema'}, (err, res, body) ->
#      expect(res.statusCode).toBe(200)
#      body = JSON.parse(body)
#      expect(body.type).toBeDefined()
#      done()
