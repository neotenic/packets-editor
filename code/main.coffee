express = require 'express'
http = require 'http'
mongoose = require 'mongoose'
async = require 'async'
_ = require 'underscore'
livereload = require 'express-livereload'
fs = require 'fs'

app = express()

livereload(app, {watchDir: 'templates', port: 35723})
if process.env.NODE_ENV == 'production'
	config = process.env
else
	config = (try JSON.parse(fs.readFileSync('config.json', 'utf8'))) || process.env || {}
port = config.port || process.env.PORT || 4444

db = mongoose.createConnection config.db || 'mongodb://localhost/protoquest'


db.on 'error', (err) -> console.log 'Database Error', err
db.on 'open', (err) -> console.log 'opened database'

public_room_list = ['lobby', 'hsquizbowl', 'msquizbowl', 'science', 'literature', 'history', 'trash', 'art', 'philosophy', 'college']

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
# db.reviews.ensureIndex( { comments: "text" } )


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
	uid:              String,
	date:             Date,
	event:            String,
	room:             String,
	details:          String
}

Tournament = db.model 'Tournament', new mongoose.Schema {
	difficulty:       String,
	year:             Number,
	source:           String,
	owner:            String,
	season:           String,
	links:            [String],
	files:            [String],
	name:             String
}

Pending = db.model 'Pending', new mongoose.Schema {
	author:           String,
	questions:        [{
		answer: String,
		question: String,
		category: String,
		num: Number
	}],
	type:             String,
	tournament:       String,
	packet:           String,
	year:             Number,
	added:            Date
}



app.set 'views', 'templates'
app.use '/bootstrap', express.static('bootstrap')

app.use express.json()
app.use express.urlencoded()
app.use express.cookieParser()
app.use express.session({ secret: config.secret || "protosecret" })
app.locals.moment = require 'moment'
app.locals.querystring = require 'querystring'
app.locals._ = _
app.locals.censor_room = (name) ->
	return name if name in public_room_list
	if name?.length < 4
		return "..."
	else
		return name?.slice(0, 2) + "..." + name?.slice(-2)



app.use (req, res, next) ->
    res.locals.session = req.session
    res.locals.is_admin = req?.session?.email in ((try JSON.parse(process.env.admins)) || config.admins || [])
    next()

require("express-persona")(app, { audience: [
	"http://localhost:#{port}", 
	"http://packets.herokuapp.com", 
	"http://packets.protobowl.com"
] })

sidebar_cache = null

sidebar = (done) ->
	if sidebar_cache
		done null, {types: sidebar_cache}
	else
		reload_sidebar done

qsidebar = (done) ->
	Question.aggregate()
		.group({
			_id: {type: "$type", category: "$category"},
			type: { $last: "$type" },
			category: { $last: "$category" },
			count: { $sum: 1 }
		})
		.group({
			_id: "$type",
			type: {$last: "$type"},
			category: { $push: "$category" },
			count: { $sum: "$count" }
		})
		.exec (err, clusters) ->
			done err, { qtypes: clusters }

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

must_login = (req, res, next) ->
	return next() if req?.session?.email
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

app.get '/new', must_login, (req, res) ->
	base = {
		default_type: req.query.type,
		default_year: req.query.year,
		default_tournament: req.query.tournament
	}
	async.parallel [
		(cb) -> Question.distinct 'type', (err, types) -> cb null, { types }
	], (err, data) ->
		res.render 'new/import.jade', _.extend({ new_page: true }, base, data...)

app.post '/categorize-packet', must_login, (req, res) ->
	{tournament, type, year, questions, packet} = JSON.parse(req.body.json)
	base = { tournament, type, year, questions, packet }
	async.parallel [
		(cb) -> Question.distinct 'category', { type }, (err, categories) -> cb null, { categories }
	], (err, data) ->
		res.render 'new/categorize.jade', _.extend({ cat_page: true }, base, data...)
	# 	type:             String, # for future support for different types of Question, e.g. certamen, jeopardy
	# category:         String,
	# num:              Number,
	# tournament:       String,
	# question:         String,
	# answer:           String,
	# difficulty:       String,
	# value:            String,
	# date:             String,
	# year:             Number,
	# round:            String,
	# seen:             Number, 
	# next:             mongoose.Schema.ObjectId,
	# fixed:            Number,
	# inc_random:       Number,
	# tags:             [String]
	# req.

	# 
	# for q in questions
	# 	question = new Question {
	# 		type,
	# 		c
	# 	}
	# # Moderator.remove({ email: req.body.email }).exec (err, data) ->
	# # 	res.redirect '/mods'
	# mod = new Moderator {
	# 	name: req.body.name,
	# 	email: req.body.email,
	# 	jurisdiction: req.body.juris.toLowerCase().split(/[,\s]+/),
	# 	added: new Date
	# }
	# mod.save()
	# res.redirect '/mods'

app.post '/upload-packet', must_login, (req, res) ->
	j = JSON.parse(req.body.json)
	pending = new Pending {
		added: new Date,
		tournament: j.tournament,
		type: j.type,
		year: j.year,
		packet: j.packet,
		author: req?.session?.email,
		questions: j.questions
	}
	pending.save ->
		res.redirect '/pending'
	
	
app.get '/pending', (req, res) ->
	base = {}
	async.parallel [
		(cb) -> Pending.find({}).exec (err, packets) -> cb null, { packets }
	], (err, data) ->
		res.render 'new/pending.jade', _.extend({}, base, data...)
	
#	for q in questions
#		question = new Question {
#			
#		}
#	{tournament, type, year, questions, packet} = JSON.parse(req.body.json)
#	base = { tournament, type, year, questions, packet }
#	async.parallel [
#		(cb) -> Question.distinct 'category', { type }, (err, categories) -> cb null, { categories }
#	], (err, data) ->
#		res.render 'new/categorize.jade', _.extend({ cat_page: true }, base, data...)

app.get '/categorize-packet', (req, res) -> res.redirect '/new'

app.get '/logs', (req, res) ->
	ModLog.find().sort(date: -1).exec (err, logs) ->
		res.render 'logs.jade', { logs }

app.get '/logs/room/:room', (req, res) ->
	ModLog.find(room: req.params.room).sort(date: -1).exec (err, logs) ->
		res.render 'logs.jade', { logs }

app.get '/logs/event/:event', (req, res) ->
	ModLog.find(event: req.params.event).sort(date: -1).exec (err, logs) ->
		res.render 'logs.jade', { logs }

app.get '/logs/user/:uid', (req, res) ->
	# log = new ModLog {
	# 	name: 'name shit',
	# 	uid: 'wumbo',
	# 	date: new Date
	# 	room: 'merps'
	# 	event: 'this shit is fucked up dude'
	# 	details: 'i wanna get out'
	# }
	# log.save()
	ModLog.find(uid: req.params.uid).sort(date: -1).exec (err, logs) ->
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

app.get '/questions', (req, res) ->
	async.parallel [qsidebar, (cb) ->
		cb null, { hello: 42 }
	], (err, data) ->
		res.render 'search/questions.jade', _.extend({ }, data...)

app.get '/search', (req, res) ->
	crit = {}
	if req.query.q
		crit.question = { $regex: req.query.q, $options: 'i'}
	crit.type = req.query.type if req.query.type
	crit.year = req.query.year if req.query.year
	crit.tournament = req.query.tournament if req.query.tournament
	crit.category = req.query.category if req.query.category
	crit.difficulty = req.query.difficulty if req.query.difficulty
	# crit = { type: req.query.type, year: req.query.year, tournament: req.query.tournament, category: req.query.category }

	async.parallel [
		((cb) -> Question.find(crit).limit(20).exec (err, entries) -> cb null, { entries }),
		((cb) -> Question.count crit, (err, count) -> cb null, { count }),
		((cb) -> Question.distinct 'category', crit, (err, categories) -> cb null, { categories }),
		((cb) -> Question.distinct 'difficulty', crit, (err, difficulties) -> cb null, { difficulties }),
		((cb) -> Question.distinct 'tournament', crit, (err, tournaments) -> cb null, { tournaments }),
		((cb) -> Question.distinct 'year', crit, (err, years) -> cb null, { years }),
		((cb) -> Question.distinct 'type', crit, (err, types) -> cb null, { types })
	], (err, data) ->
		fakecrit = _.omit(crit, 'question')
		fakecrit.q = req.query.q if req.query.q
		res.render 'search/search.jade', _.extend({ crit: fakecrit }, data...)


app.get '/questions/:type/:category', (req, res) ->
	async.parallel [qsidebar, (cb) ->
		Question.find({
			type: req.params.type,
			category: req.params.category
		})
		.limit(10)
		.exec (err, entries) -> cb null, {entries}
	], (err, data) ->
		res.render 'search/category.jade', _.extend({ type: req.params.type, cat: req.params.category }, data...)


app.get "/packets/:type", (req, res) ->
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
		res.render 'packets/tournaments.jade', _.extend({ main_page: true }, base, data...)

app.get "/packets/:type/:year", (req, res) ->
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
		res.render 'packets/year.jade', _.extend({ main_page: true }, base, data...)

app.get "/packets/:type/:year/:tournament", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type, tournament: req.params.tournament }
	async.parallel [sidebar, (cb) ->
		Question.distinct 'round', base, (err, rounds) -> cb null, { rounds }
	], (err, data) ->
		res.render 'packets/tournament.jade', _.extend({ main_page: true }, base, data...)

app.get "/packets/:type/:year/:tournament/:round", (req, res) ->
	base = { year: parseInt(req.params.year), type: req.params.type, tournament: req.params.tournament, round: req.params.round }
	async.parallel [sidebar, (cb) ->
		Question.find base, (err, entries) -> cb null, {entries}
	], (err, data) ->
		res.render 'packets/packet.jade', _.extend({ main_page: true }, base, data...)

app.get "/tournaments", (req, res) ->
	base = {}
	async.parallel [sidebar], (err, data) ->
		res.render 'tournaments/main.jade', _.extend({}, base, data...)

app.get "/tournaments/import_quizbowlpackets", (req, res) ->
	cheerio = require 'cheerio'
	util = require 'util'
	request = require 'request'

	res.writeHead 200, {
		'Content-Type': 'text/plain'
		'Transfer-Encoding': 'chunked'
	}

	log = (text...) -> 
		res.write text.map((x) ->
			return x if typeof x is 'string'
			return util.inspect x
		).join(' ') + '\n'

	log 'downloading packets from quizbowlpackets.com'

	res.write ' ' for i in [1..1000]

	get_tournaments = (sub = "www", cb) ->
		path = "http://#{sub}.quizbowlpackets.com/"
		log 'loading tournaments from', path
		request path, (err, res, body) ->
			$ = cheerio.load(body)
			tournaments = for e in $('.MainColumn ul>li>span.Name>a').get()
				{ href: path + $(e).attr('href'), name: $(e).text() }
			cb? null, tournaments

	tournament_info = (path, cb) ->
		request path, (err, res, body) ->
			$ = cheerio.load(body)
			name = $('.MainColumn .First h2').text().trim()
			links = ($(e).attr('href') for e in $('#ActionBox a').get())
			fields = _.object (for field in $('.MainColumn p>span.FieldName').get()
				[ $(field).text().replace(':', '').trim(), $(field).parent().text().replace($(field).text(), '').trim() ])

			files = for link in $('ul.FileList>li>a').get()
				{ href: $(link).attr('href'), name: $(link).text() }

			owner = $('.PermissionsInformation').text()

			log path, { name, level: fields['Target level'], season: fields['Season primarily used'] }
			cb? { name, fields, files, links, owner }


	cached_lookup = (path, cb) ->
		path = path.replace /\w+\.quizbowlpackets\.com/g, 'www.quizbowlpackets.com'
		Tournament.count { source: path }, (err, count) ->
			return cb?() if count > 0
			tournament_info path, ({name, fields, files, links, owner}) ->
				year = name.match(/^\d{4}/) || fields['Season primarily used']?.split('-')?[0]
				t = new Tournament {
					source: path
					difficulty: fields['Target level']
					season: fields['Season primarily used']
					year: (if year then parseInt(year) else null)
					links
					name
					owner
					files
				}
				t.save cb

	async.map ['collegiate', 'www', 'ms', 'trash'], get_tournaments, (err, data) ->
		tournament_paths = _.shuffle(_.pluck(_.flatten(data), 'href'))
		log 'total tournament paths', tournament_paths.length
		async.eachLimit tournament_paths, 1, cached_lookup, (err) ->
			if err
				log 'error exploring tournaments', err
			else
				log 'done with exploring tournaments'
			res.end()


app.post "/reload-sidebar", (req, res) ->
	reload_sidebar ->
		res.redirect '/'

app.listen port, ->
	console.log "listening on port", port