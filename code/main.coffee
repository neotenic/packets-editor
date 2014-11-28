express = require 'express'
http = require 'http'
mongoose = require 'mongoose'
async = require 'async'
_ = require 'underscore'
livereload = require 'express-livereload'
fs = require 'fs'

app = express()

livereload(app, {watchDir: 'templates'})
config = (try JSON.parse(fs.readFileSync('config.json', 'utf8'))) || process.env
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


Moderator = db.model 'Moderator', new mongoose.Schema {
	name:             String,
	email:            String,
	jurisdiction:     [String],
	added:            Date
}

ModLog = db.model 'ModLog', new mongoose.Schema {
	name:             String,
	date:             Date,
	event:            String,
	details:          String
}


app.set 'views', 'templates'
app.use '/bootstrap', express.static('bootstrap')

app.use express.json()
app.use express.urlencoded()
app.use express.cookieParser()
app.use express.session({ secret: config.secret || "protosecret" })
app.locals.moment = require 'moment'

app.use (req, res, next) ->
    res.locals.session = req.session
    res.locals.is_admin = req?.session?.email in (config.admins || [])
    next()

require("express-persona")(app, { config.audience || "http://localhost:#{port}" })

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

must_admin = (req, res, next) ->
	return next() if res.locals.is_admin
	res.redirect '/not-authorized'

literalize = (x) ->
	return null if x == 'null'
	return x

app.get '/not-authorized', (req, res) -> res.end 'not authorized'

app.get '/', (req, res) ->
	async.parallel [sidebar, (cb) ->
		cb null, { hello: 42 }
	], (err, data) ->
		res.render 'index.jade', _.extend({ main_page: true }, data...)

app.get '/review', (req, res) -> res.redirect '/review/qb'

app.get '/review/:type', (req, res) ->
	base = { type: literalize req.params.type }
	async.parallel [sidebar, reportbar, (cb) ->
		Report.find(base).limit(30).exec (err, reports) -> cb null, { reports }
	], (err, data) ->
		res.render 'review.jade', _.extend({ review_page: true }, base, data...)

app.get '/new', (req, res) ->
	res.render 'new.jade', {}

app.get '/logs', (req, res) ->
	ModLog.find().exec (err, logs) ->
		res.render 'logs.jade', { logs }

app.get '/mods', (req, res) ->
	Moderator.find().exec (err, mods) ->
		res.render 'moderators.jade', { mods }

app.post '/mods/create', must_admin, (req, res) ->
	mod = new Moderator {
		name: req.body.name,
		email: req.body.email,
		jurisdiction: req.body.juris.toLowerCase().split(/[,\s]+/),
		added: new Date
	}
	mod.save()
	res.redirect '/mods'

app.post '/mods/edit', must_admin, (req, res) ->
	Moderator.update({ email: req.body.email }, {
		$set: {
			jurisdiction: req.body.juris.toLowerCase().split(/[,\s]+/),
			name: req.body.name
		}
	}).exec (err, data) ->
		res.redirect '/mods'

app.post '/mods/delete', must_admin, (req, res) ->
	Moderator.remove({ email: req.body.email }).exec (err, data) ->
		res.redirect '/mods'

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
			.exec (err, clusters) -> cb null, { groups: clusters }
	], (err, data) ->
		res.render 'year.jade', _.extend({ main_page: true }, base, data...)

app.get "/:type/:year/:tournament", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type, tournament: req.params.tournament }
	async.parallel [sidebar, (cb) ->
		Question.distinct 'round', base, (err, rounds) -> cb null, { rounds }
	], (err, data) ->
		res.render 'tournament.jade', _.extend({ main_page: true }, base, data...)

app.get "/:type/:year/:tournament/:round", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type, tournament: req.params.tournament, round: req.params.round }
	async.parallel [sidebar, (cb) ->
		Question.find base, (err, entries) -> cb null, {entries}
	], (err, data) ->
		res.render 'packet.jade', _.extend({ main_page: true }, base, data...)

app.post "/reload-sidebar", (req, res) ->
	reload_sidebar ->
		res.redirect '/'

app.listen port, ->
	console.log "listening on port", port