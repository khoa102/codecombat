require '../common'
mw = require '../middleware'
async = require 'async'
_ = require 'lodash'
utils = require '../../../server/lib/utils'
co = require 'co'
Promise = require 'bluebird'

wrap = (gen) ->
  fn = co.wrap(gen)
  return (done) ->
    fn.apply(@, [done]).catch (err) -> done.fail(err)

describe 'GET /db/article', ->
  articleData1 = { name: 'Article 1', body: 'Article 1 body cow', i18nCoverage: [] }
  articleData2 = { name: 'Article 2', body: 'Article 2 body moo' }
  
  beforeEach wrap (done) ->
    yield mw.clearModelsAsync([Article])
    @admin = yield mw.initAdminAsync({})
    yield mw.loginUserAsync(@admin)
    yield request.postAsync(getURL('/db/article'), { json: articleData1 })
    yield request.postAsync(getURL('/db/article'), { json: articleData2 })
    yield mw.logoutAsync()
    done()
      
      
  it 'returns an array of Article objects', wrap (done) ->
    [res, body] = yield request.getAsync { uri: getURL('/db/article'), json: true }
    expect(body.length).toBe(2)
    done()
      

  it 'accepts a limit parameter', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL('/db/article?limit=1'), json: true}
    expect(body.length).toBe(1)
    done()


  it 'returns 422 for an invalid limit parameter', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL('/db/article?limit=word'), json: true}
    expect(res.statusCode).toBe(422)
    done()
  

  it 'accepts a skip parameter', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL('/db/article?skip=1'), json: true}
    expect(body.length).toBe(1)
    [res, body] = yield request.getAsync {uri: getURL('/db/article?skip=2'), json: true}
    expect(body.length).toBe(0)
    done()

      
  it 'returns 422 for an invalid skip parameter', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL('/db/article?skip=???'), json: true}
    expect(res.statusCode).toBe(422)
    done()
  

  it 'accepts a custom project parameter', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL('/db/article?project=name,body'), json: true}
    expect(body.length).toBe(2)
    for doc in body
      expect(_.size(_.xor(_.keys(doc), ['_id', 'name', 'body']))).toBe(0)
    done()


  it 'returns a default projection if project is "true"', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL('/db/article?project=true'), json: true}
    expect(res.statusCode).toBe(200)
    expect(body.length).toBe(2)
    expect(body[0].body).toBeUndefined()
    expect(body[0].version).toBeDefined()
    done()
    
      
  it 'accepts custom filter parameters', wrap (done) ->
    yield mw.loginUserAsync(@admin)
    [res, body] = yield request.getAsync {uri: getURL('/db/article?filter[slug]="article-1"'), json: true}
    expect(body.length).toBe(1)
    done()
  

  it 'ignores custom filter parameters for non-admins', wrap (done) ->
    user = yield mw.initUserAsync()
    yield mw.loginUserAsync(user)
    [res, body] = yield request.getAsync {uri: getURL('/db/article?filter[slug]="article-1"'), json: true}
    expect(body.length).toBe(2)
    done()
  
    
  it 'accepts custom condition parameters', wrap (done) ->
    yield mw.loginUserAsync(@admin)
    [res, body] = yield request.getAsync {uri: getURL('/db/article?conditions[select]="slug body"'), json: true}
    expect(body.length).toBe(2)
    for doc in body
      expect(_.size(_.xor(_.keys(doc), ['_id', 'slug', 'body']))).toBe(0)
    done()
  
    
  it 'ignores custom condition parameters for non-admins', wrap (done) ->
    user = yield mw.initUserAsync()
    yield mw.loginUserAsync(user)
    [res, body] = yield request.getAsync {uri: getURL('/db/article?conditions[select]="slug body"'), json: true}
    expect(body.length).toBe(2)
    for doc in body
      expect(doc.name).toBeDefined()
    done()
  
    
  it 'allows non-admins to view by i18n-coverage', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL('/db/article?view=i18n-coverage'), json: true}
    expect(body.length).toBe(1)
    expect(body[0].slug).toBe('article-1')
    done()
  

  it 'allows non-admins to search by text', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL('/db/article?term=moo'), json: true}
    expect(body.length).toBe(1)
    expect(body[0].slug).toBe('article-2')
    done()


describe 'POST /db/article', ->
  
  articleData = { name: 'Article', body: 'Article', otherProp: 'not getting set' }
  
  beforeEach wrap (done) ->
    yield mw.clearModelsAsync([Article])
    @admin = yield mw.initAdminAsync({})
    yield mw.loginUserAsync(@admin)
    [@res, @body] = yield request.postAsync {
      uri: getURL('/db/article'), json: articleData 
    }
    done()
    
  
  it 'creates a new Article, returning 201', wrap (done) ->
    expect(@res.statusCode).toBe(201)
    article = yield Article.findById(@body._id).exec()
    expect(article).toBeDefined()
    done()
      
  
  it 'sets creator to the user who created it', ->
    expect(@res.body.creator).toBe(@admin.id)
    
  
  it 'sets original to _id', ->
    body = @res.body
    expect(body.original).toBe(body._id)
    
  
  it 'returns 422 when no input is provided', wrap (done) ->
    [res, body] = yield request.postAsync { uri: getURL('/db/article') }
    expect(res.statusCode).toBe(422)
    done()

      
  it 'allows you to set Article\'s editableProperties', ->
    expect(@body.name).toBe('Article')
    
  
  it 'ignores properties not included in editableProperties', ->
    expect(@body.otherProp).toBeUndefined()
  
    
  it 'returns 422 when properties do not pass validation', wrap (done) ->
    [res, body] = yield request.postAsync { 
      uri: getURL('/db/article'), json: { i18nCoverage: 9001 } 
    }
    expect(res.statusCode).toBe(422)
    expect(body.validationErrors).toBeDefined()
    done()

      
  it 'allows admins to create Articles', -> # handled in beforeEach
  
    
  it 'allows artisans to create Articles', wrap (done) ->
    yield mw.clearModelsAsync([Article])
    artisan = yield mw.initArtisanAsync({})
    yield mw.loginUserAsync(artisan)
    [res, body] = yield request.postAsync({uri: getURL('/db/article'), json: articleData })
    expect(res.statusCode).toBe(201)
    done()
  
  
  it 'does not allow normal users to create Articles', wrap (done) ->
    yield mw.clearModelsAsync([Article])
    user = yield mw.initUserAsync({})
    yield mw.loginUserAsync(user)
    [res, body] = yield request.postAsync({uri: getURL('/db/article'), json: articleData })
    expect(res.statusCode).toBe(403)
    done()
      
    
  it 'does not allow anonymous users to create Articles', wrap (done) ->
    yield mw.clearModelsAsync([Article])
    yield mw.logoutAsync()
    [res, body] = yield request.postAsync({uri: getURL('/db/article'), json: articleData })
    expect(res.statusCode).toBe(401)
    done()
  
  
  it 'does not allow creating Articles with reserved words', wrap (done) ->
    [res, body] = yield request.postAsync { uri: getURL('/db/article'), json: { name: 'Names' } }
    expect(res.statusCode).toBe(422)
    done()
  
      
  it 'does not allow creating a second article of the same name', wrap (done) ->
    [res, body] = yield request.postAsync { uri: getURL('/db/article'), json: articleData }
    expect(res.statusCode).toBe(409)
    done()
      
      
describe 'GET /db/article/:handle', ->

  articleData = { name: 'Some Name', body: 'Article', otherProp: 'not getting set' }

  beforeEach wrap (done) ->
    yield mw.clearModelsAsync([Article])
    @admin = yield mw.initAdminAsync({})
    yield mw.loginUserAsync(@admin)
    [@res, @body] = yield request.postAsync {
      uri: getURL('/db/article'), json: articleData
    }
    done()
    
    
  it 'returns Article by id', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL("/db/article/#{@body._id}"), json: true}
    expect(res.statusCode).toBe(200)
    expect(_.isObject(body)).toBe(true)
    done()
      
      
  it 'returns Article by slug', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL("/db/article/some-name"), json: true}
    expect(res.statusCode).toBe(200)
    expect(_.isObject(body)).toBe(true)
    done()
      
      
  it 'returns not found if handle does not exist in the db', wrap (done) ->
    [res, body] = yield request.getAsync {uri: getURL("/db/article/dne"), json: true}
    expect(res.statusCode).toBe(404)
    done()

      
describe 'PUT /db/article/:handle', ->

  articleData = { name: 'Some Name', body: 'Article' }

  beforeEach wrap (done) ->
    yield mw.clearModelsAsync([Article])
    @admin = yield mw.initAdminAsync({})
    yield mw.loginUserAsync(@admin)
    [@res, @body] = yield request.postAsync {
      uri: getURL('/db/article'), json: articleData
    }
    done()
    
  
  it 'edits editable Article properties', wrap (done) ->
    [res, body] = yield request.putAsync {uri: getURL("/db/article/#{@body._id}"), json: { body: 'New body' }}
    expect(body.body).toBe('New body')
    done()
      
      
  it 'updates the slug when the name is changed', wrap (done) ->
    [res, body] = yield request.putAsync {uri: getURL("/db/article/#{@body._id}"), json: json = { name: 'New name' }}
    expect(body.name).toBe('New name')
    expect(body.slug).toBe('new-name')
    done()
      
      
  it 'does not allow normal artisan, non-admins to make changes', wrap (done) ->
    artisan = yield mw.initArtisanAsync({})
    yield mw.loginUserAsync(artisan)
    [res, body] = yield request.putAsync {uri: getURL("/db/article/#{@body._id}"), json: { name: 'Another name' }}
    expect(res.statusCode).toBe(403)
    done()
    
    
    
describe 'POST /db/article/:handle/new-version', ->
  articleData = { name: 'Article name', body: 'Article body' }
  articleID = null
  
  beforeEach wrap (done) ->
    yield mw.clearModelsAsync([Article])
    @admin = yield mw.initAdminAsync({})
    yield mw.loginUserAsync(@admin)
    [res, body] = yield request.postAsync { uri: getURL('/db/article'), json: articleData }
    expect(res.statusCode).toBe(201)
    articleID = body._id
    done()
    
  postNewVersion = Promise.promisify (json, expectedStatus=201, done) ->
    if _.isFunction(expectedStatus)
      done = expectedStatus
      expectedStatus = 201
    url = getURL("/db/article/#{articleID}/new-version")
    request.post { uri: url, json: json }, (err, res) ->
      expect(res.statusCode).toBe(expectedStatus)
      done(err)
    
  testArrayEqual = (given, expected) ->
    expect(_.isEqual(given, expected)).toBe(true)
    
  
      
  it 'creates a new major version, updating model and version properties', wrap (done) ->
    yield postNewVersion({ name: 'Article name', body: 'New body' })
    yield postNewVersion({ name: 'New name', body: 'New new body' })
    articles = yield Article.find()
    expect(articles.length).toBe(3)
    versions = (article.get('version') for article in articles)
    articles = (article.toObject() for article in articles)
    
    testArrayEqual(_.pluck(versions, 'major'), [0, 1, 2])
    testArrayEqual(_.pluck(versions, 'minor'), [0, 0, 0])
    testArrayEqual(_.pluck(versions, 'isLatestMajor'), [false, false, true])
    testArrayEqual(_.pluck(versions, 'isLatestMinor'), [true, true, true])
    testArrayEqual(_.pluck(articles, 'name'), ['Article name', 'Article name', 'New name'])
    testArrayEqual(_.pluck(articles, 'body'), ['Article body', 'New body', 'New new body'])
    testArrayEqual(_.pluck(articles, 'slug'), [undefined, undefined, 'new-name'])
    testArrayEqual(_.pluck(articles, 'index'), [undefined, undefined, true])
    done()
    
    
  it 'works if there is no document with the appropriate version settings (new major)', wrap (done) ->
    article = yield Article.findById(articleID)
    article.set({ 'version.isLatestMajor': false, 'version.isLatestMinor': false })
    yield article.save()
    yield postNewVersion({ name: 'Article name', body: 'New body' })
    articles = yield Article.find()
    expect(articles.length).toBe(2)

    versions = (article.get('version') for article in articles)
    articles = (article.toObject() for article in articles)

    testArrayEqual(_.pluck(versions, 'major'), [0, 1])
    testArrayEqual(_.pluck(versions, 'minor'), [0, 0])
    testArrayEqual(_.pluck(versions, 'isLatestMajor'), [false, true])
    testArrayEqual(_.pluck(versions, 'isLatestMinor'), [false, true]) # does not fix the old version's value
    testArrayEqual(_.pluck(articles, 'body'), ['Article body', 'New body'])
    testArrayEqual(_.pluck(articles, 'slug'), [undefined, 'article-name'])
    testArrayEqual(_.pluck(articles, 'index'), [undefined, true])
    done()
    
    
  it 'creates a new minor version if version.major is included', wrap (done) ->
    yield postNewVersion({ name: 'Article name', body: 'New body', version: { major: 0 } })
    yield postNewVersion({ name: 'Article name', body: 'New new body', version: { major: 0 } })
    articles = yield Article.find()
    expect(articles.length).toBe(3)

    versions = (article.get('version') for article in articles)
    articles = (article.toObject() for article in articles)

    testArrayEqual(_.pluck(versions, 'major'), [0, 0, 0])
    testArrayEqual(_.pluck(versions, 'minor'), [0, 1, 2])
    testArrayEqual(_.pluck(versions, 'isLatestMajor'), [false, false, true])
    testArrayEqual(_.pluck(versions, 'isLatestMinor'), [false, false, true])
    testArrayEqual(_.pluck(articles, 'name'), ['Article name', 'Article name', 'Article name'])
    testArrayEqual(_.pluck(articles, 'body'), ['Article body', 'New body', 'New new body'])
    testArrayEqual(_.pluck(articles, 'slug'), [undefined, undefined, 'article-name'])
    testArrayEqual(_.pluck(articles, 'index'), [undefined, undefined, true])
    done()


  it 'works if there is no document with the appropriate version settings (new minor)', wrap (done) ->
    article = yield Article.findById(articleID)
    article.set({ 'version.isLatestMajor': false, 'version.isLatestMinor': false })
    yield article.save()
    yield postNewVersion({ name: 'Article name', body: 'New body', version: { major: 0 } })
    articles = yield Article.find()
    expect(articles.length).toBe(2)

    versions = (article.get('version') for article in articles)
    articles = (article.toObject() for article in articles)

    testArrayEqual(_.pluck(versions, 'major'), [0, 0])
    testArrayEqual(_.pluck(versions, 'minor'), [0, 1])
    testArrayEqual(_.pluck(versions, 'isLatestMajor'), [false, false])
    testArrayEqual(_.pluck(versions, 'isLatestMinor'), [false, true])
    testArrayEqual(_.pluck(articles, 'body'), ['Article body', 'New body'])
    testArrayEqual(_.pluck(articles, 'slug'), [undefined, 'article-name'])
    testArrayEqual(_.pluck(articles, 'index'), [undefined, true])
    done()
    
    
  it 'allows adding new minor versions to old major versions', wrap (done) ->
    yield postNewVersion({ name: 'Article name', body: 'New body' })
    yield postNewVersion({ name: 'Article name', body: 'New new body', version: { major: 0 } })
    articles = yield Article.find()
    expect(articles.length).toBe(3)

    versions = (article.get('version') for article in articles)
    articles = (article.toObject() for article in articles)
    
    testArrayEqual(_.pluck(versions, 'major'), [0, 1, 0])
    testArrayEqual(_.pluck(versions, 'minor'), [0, 0, 1])
    testArrayEqual(_.pluck(versions, 'isLatestMajor'), [false, true, false])
    testArrayEqual(_.pluck(versions, 'isLatestMinor'), [false, true, true])
    testArrayEqual(_.pluck(articles, 'name'), ['Article name', 'Article name', 'Article name'])
    testArrayEqual(_.pluck(articles, 'body'), ['Article body', 'New body', 'New new body'])
    testArrayEqual(_.pluck(articles, 'slug'), [undefined, 'article-name', undefined])
    testArrayEqual(_.pluck(articles, 'index'), [undefined, true, undefined])
    done()
    
    
  it 'unsets properties which are not included in the request', wrap (done) ->
    yield postNewVersion({ name: 'Article name', version: { major: 0 } })
    articles = yield Article.find()
    expect(articles.length).toBe(2)
    expect(articles[1].get('body')).toBeUndefined()
    done()
  
  
  it 'works for artisans', wrap (done) ->
    yield mw.logoutAsync()
    artisan = yield mw.initArtisanAsync()
    yield mw.loginUserAsync(artisan)
    yield postNewVersion({ name: 'Article name', body: 'New body' })
    articles = yield Article.find()
    expect(articles.length).toBe(2)
    done()
    
    
  it 'works for normal users submitting translations'


  it 'does not work for normal users', wrap (done) ->
    yield mw.logoutAsync()
    user = yield mw.initUserAsync()
    yield mw.loginUserAsync(user)
    yield postNewVersion({ name: 'Article name', body: 'New body' }, 403)
    articles = yield Article.find()
    expect(articles.length).toBe(1)
    done()


  it 'does not work for anonymous users', wrap (done) ->
    yield mw.logoutAsync()
    yield postNewVersion({ name: 'Article name', body: 'New body' }, 401)
    articles = yield Article.find()
    expect(articles.length).toBe(1)
    done()

  
  it 'notifies watchers of changes'
  
  it 'sends a notification to artisan and main HipChat channels'
  
  
describe 'GET /db/article/:handle/version/:version', ->
  
  it 'returns the latest version for the given original article when :version is empty'
  
  it 'returns the latest of a given major version when :version is X'
  
  it 'returns a specific version when :version is X.Y'
  
  
describe 'GET /db/article/:handle/versions', ->
  
  it 'returns an array of versions sorted by creation for the given original article'
  
  it 'is projected by default'
  
  
describe 'GET /db/article/:handle/files', ->
  
  it 'returns an array of file metadata for the given original article'
  
  
describe 'GET and POST /db/article/:handle/names', ->
  
  it 'returns an object mapping ids to names'
  
  
describe 'PATCH /db/article/:handle', ->
  
  it 'works like PUT'
  
  
describe 'GET /db/article/:handle/patches', ->
  
  it 'returns pending patches for the given original article'
  
  
describe 'PUT /db/article/:handle/watch', ->
  
  it 'adds the user to the list of watchers'
  
  it 'removes the user from the list of watchers if query param "on" is "false"'