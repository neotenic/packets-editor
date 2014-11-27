express = require 'express'
http = require 'http'
mongoose = require 'mongoose'
async = require 'async'
_ = require 'underscore'
livereload = require 'express-livereload'

app = express()
livereload(app, {watchDir: 'templates'})
port = 4444

db = mongoose.createConnection 'localhost', 'protoquest'
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

ext = (target, others...) ->
	for thing in others
		for key, val of thing
			target[key] = val
	return target


sidebar = (done) ->
	Question.distinct 'type', (err, types) ->
		async.map types, (type, cb) ->
			Question.distinct 'year', { type: type }, cb
		, (err, years) ->
			done err, { years, types }

app.get '/', (req, res) ->
	async.parallel [sidebar, (cb) ->
		cb null, { hello: 42 }
	], (err, data) ->
		res.render 'index.jade', ext({}, data...)

app.get '/review', (req, res) ->
	async.parallel [sidebar, (cb) ->
		cb null, { hello: 42 }
	], (err, data) ->
		res.render 'review.jade', ext({}, data...)

app.get '/new', (req, res) ->
	res.render 'new.jade', {}

app.get "/:type/:year", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type }
	async.parallel [sidebar, (cb) ->
		Question.distinct 'tournament', base, (err, tournaments) ->
			async.map tournaments, (tournament, end) ->
				Question.findOne ext({ tournament }, base), end
			, (err, Question) ->
				groups = _.groupBy(_.zip(tournaments, Question), ([a,q]) -> q.difficulty)
				cb null, { tournaments, Question, groups }
	], (err, data) ->
		res.render 'year.jade', ext({}, base, data...)

app.get "/:type/:year/:tournament", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type, tournament: req.params.tournament }
	async.parallel [sidebar, (cb) ->
		Question.distinct 'round', base, (err, rounds) ->
			cb null, { rounds }
	], (err, data) ->
		res.render 'tournament.jade', ext({}, base, data...)

app.get "/:type/:year/:tournament/:round", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type, tournament: req.params.tournament, round: req.params.round }
	console.log base
	async.parallel [sidebar, (cb) ->
		Question.find base, (err, entries) ->
			console.log err, entries
			cb null, {entries}
	], (err, data) ->
		res.render 'packet.jade', ext({}, base, data...)


app.listen port, ->
	console.log "listening on port", port