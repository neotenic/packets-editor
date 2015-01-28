$(document).ready(function(){
	$('#paste').elastic()
	$('#paste').keyup(function(){
		process()
	})
	$(window).resize(function(){
		process()
	})
	process();
})

function process(){
	$('#preview').html('')

	var full = $('#paste').val();
	var textarea = $('#paste')[0];
	var mirror = $("#mirror span")[0]
	var lastIndex = 0;

	var offset = document.getElementById('paste').getClientRects()[0].top;
	document.getElementById('preview').style.top = (
		parseInt(document.getElementById('preview').style.top) + 
		(offset - 
			document.getElementById('preview').getClientRects()[0].top)) + 'px';

	var num = 0;
	var questions = [];

	full.split(/\n\s*\n/).map(function(text){
		var lines = text.trim().split('\n')
		var answer = lines[lines.length - 1]
		var question = lines.slice(0, lines.length - 1).join('\n')

		lastIndex = full.indexOf(text, lastIndex);
		mirror.innerHTML = full.substr(0, lastIndex).replace(/\n$/, "\n\001");
		var rects = mirror.getClientRects(),
			lastRect = rects[rects.length - 1],
			top = lastRect.top - textarea.scrollTop,
			left = lastRect.left + lastRect.width;
		
		num++;
							
		var host = $('<div>')
			.css('top', top - offset)
			.css('position', 'relative')
			.css('height', 0)
			.appendTo('#preview');
		var thing = $('<div>').addClass('thing').appendTo(host)
		$('<div>')
			.addClass('header')
			.text("Question "+ num)
			.appendTo(thing)
		$('<div>').addClass('question')
			.text(lines.slice(0, -1).join(' '))
			.append('<br>')
			.append('Answer: ')
			.append($('<span>').text(answer).addClass('answer'))
			.appendTo(thing)

		questions.push({
			answer: answer,
			question: lines.slice(0, -1).join(' '),
			num: num
		})
		
	})


	document.getElementById('json').value = JSON.stringify({
		type: document.getElementById('question_type').value,
		year: document.getElementById('packet_year').value,
		tournament: document.getElementById('tournament_name').value,
		packet: document.getElementById('packet_name').value,
		questions: questions
	})
}
