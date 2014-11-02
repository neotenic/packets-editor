express = require 'express'
http = require 'http'
mongoose = require 'mongoose'
async = require 'async'

db = mongoose.createConnection 'localhost', 'protoquest'
db.on 'error', (err) -> console.log 'Database Error', err
db.on 'open', (err) -> console.log 'opened database'

question_schema = new mongoose.Schema {
	type:             String, # for future support for different types of questions, e.g. certamen, jeopardy
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

question = db.model 'Question', question_schema
questions = question.collection

app = express()
port = 4444

app.set 'views', 'templates'
app.use '/bootstrap', express.static('bootstrap')

app.get '/test', (req, res) ->
	questions.distinct 'type', (err, types) ->
		async.map types, (type, cb) ->
			questions.distinct 'year', { type: type }, cb
		, (err, years) ->
			res.render 'test.jade', { years, types }

app.listen port, ->
	console.log "listening on port", port