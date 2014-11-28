express = require 'express'
http = require 'http'
mongoose = require 'mongoose'
async = require 'async'
_ = require 'underscore'
livereload = require 'express-livereload'
fs = require 'fs'

app = express()

livereload(app, {watchDir: 'templates'})
config = (try JSON.parse(fs.readFileSync('config.json', 'utf8'))) || {}
port = config.port || 4444

db = mongoose.createConnection config.db || 'mongodb://localhost/protoquest'


db.on 'error', (err) -> console.log 'Database Error', err
db.on 'open', (err) -> console.log 'opened database'


question_schema = new mongoose.Schema {
	type:             String, # for future support for different types of Question, e.g. certamen, jeopardy
	category:         String,
	num:              Number,
	tournament:       String,
	question:         String,
	answer:           String,
	difficulty:       String,
	value:            String,
	date:             String,
	year:             Number,
	round:            String,
	seen:             Number, 
	next:             mongoose.Schema.ObjectId,
	fixed:            Number,
	inc_random:       Number,
	tags:             [String]
}

Question = db.model 'Question', question_schema

report_schema = new mongoose.Schema {
	type:             String, # for future support for different types of questions, e.g. certamen, jeopardy
	category:         String,
	num:              Number,
	tournament:       String,
	question:         String,
	answer:           String,
	difficulty:       String,
	year:             Number,
	round:            String,
	qid:              String,
	fixed_category:   String,
	describe:         String,
	room:             String,
	user:             String,
	comment:          String
}
Report = db.model 'Report', report_schema


app.set 'views', 'templates'
app.use '/bootstrap', express.static('bootstrap')

app.use express.json()
app.use express.urlencoded()
app.use express.cookieParser()
app.use express.session({ secret: config.secret || "protosecret" })

app.use (req, res, next) ->
    res.locals.session = req.session
    next()

# audience = "http://localhost:#{port}"
audience = "http://localhost:4455/"

require("express-persona")(app, { audience })

sidebar_cache = null

sidebar = (done) ->
	if sidebar_cache
		done null, {types: sidebar_cache}
	else
		reload_sidebar done

reload_sidebar = (done) ->
	Question.distinct 'type', (err, types) ->
		async.map types, (type, cb) ->
			Question.distinct 'year', { type: type }, cb
		, (err, years) ->
			sidebar_cache = _.object(types, years)
			done err, {types: sidebar_cache}

reportbar = (done) ->
	Report.aggregate()
		.group({
			_id: "$type"
			type: { $last: "$type" },
			count: { $sum: 1 }
		})
		.exec (err, types) ->
			done err, { report_types: types }

literalize = (x) ->
	return null if x == 'null'
	return x

app.get '/', (req, res) ->
	async.parallel [sidebar, (cb) ->
		cb null, { hello: 42 }
	], (err, data) ->
		res.render 'index.jade', _.extend({ main_page: true }, data...)

app.get '/review', (req, res) -> res.redirect '/review/qb'

app.get '/review/:type', (req, res) ->
	base = { type: literalize req.params.type }
	async.parallel [sidebar, reportbar, (cb) ->
		Report.find(base).limit(30).exec (err, reports) ->
			cb null, { reports }
	], (err, data) ->
		res.render 'review.jade', _.extend({ review_page: true }, base, data...)

app.get '/new', (req, res) ->
	res.render 'new.jade', {}

app.get "/:type", (req, res) ->
	base = { type: req.params.type }
	async.parallel [sidebar, (cb) ->
		Question.aggregate( $match: base )
			.group({
				_id: {year: "$year", tournament: "$tournament"},
				tournament: { $last: "$tournament" },
				year: { $last: "$year" },
				difficulty: { $last: "$difficulty" }
			})
			.group({
				_id: "$tournament",
				difficulty: { $last: "$difficulty" }
				tournament: { $last: "$tournament" }
				years: { $push: "$year" }
			})
			.group({
				_id: "$difficulty",
				difficulty: { $last: "$difficulty" }
				tournaments: { $push: {
					name: "$tournament",
					years: "$years"
				} }
			})
			.exec (err, clusters) ->
				cb err, { clusters: _.sortBy(clusters, 'difficulty') }
		# Question.distinct 'tournament', base, (err, tournaments) ->
		# 	cb err, {tournaments}
	], (err, data) ->
		res.render 'tournaments.jade', _.extend({ main_page: true }, base, data...)

app.get "/:type/:year", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type }

	async.parallel [sidebar, (cb) ->
		Question.aggregate( $match: base )
			.group({
				_id: "$tournament",
				tournament: { $last: "$tournament" },
				difficulty: { $last: "$difficulty" }
			})
			.group({
				_id: "$difficulty",
				difficulty: { $last: "$difficulty" }
				tournaments: { $push: "$tournament" }
			})
			.exec (err, clusters) ->
				# console.log clusters 
				cb null, { groups: clusters }
					
		# Question.distinct 'tournament', base, (err, tournaments) ->
		# 	async.map tournaments, (tournament, end) ->
		# 		Question.findOne _.extend({ tournament }, base), end
		# 	, (err, Question) ->
		# 		groups = _.groupBy(_.zip(tournaments, Question), ([a,q]) -> q.difficulty)
		# 		console.log tournaments, groups
		# 		cb null, { tournaments, Question, groups }
	], (err, data) ->
		res.render 'year.jade', _.extend({ main_page: true }, base, data...)

app.get "/:type/:year/:tournament", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type, tournament: req.params.tournament }

	async.parallel [sidebar, (cb) ->
		Question.distinct 'round', base, (err, rounds) ->
			cb null, { rounds }
	], (err, data) ->
		res.render 'tournament.jade', _.extend({ main_page: true }, base, data...)

app.get "/:type/:year/:tournament/:round", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type, tournament: req.params.tournament, round: req.params.round }
	console.log base
	async.parallel [sidebar, (cb) ->
		Question.find base, (err, entries) ->
			console.log err, entries
			cb null, {entries}
	], (err, data) ->
		res.render 'packet.jade', _.extend({ main_page: true }, base, data...)

app.post "/reload-sidebar", (req, res) ->
	reload_sidebar ->
		res.redirect '/'

app.listen port, ->
	console.log "listening on port", port