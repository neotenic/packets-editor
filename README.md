packets
=======

protobowl packets editor



	db.questions.aggregate([
	 {$group: {
	        _id: {type: "$type", year: "$year"},
	     type: {
	         $last: "$type"
	     },
	     year: {
	         $last: "$year"
	     }
	 }}, 
	 {$group: {
	     _id: "$type",
	     years: {
	         $push: "$year"
	     }
	   }}
	]).result




	db.questions.aggregate([
	{$match: {year: 2010, type: 'qb'}},
	 {$group: {
	        _id: "$tournament",
	     tournament: {
	         $last: "$tournament"
	     },
	     difficulty: {
	         $last: "$difficulty"
	     }
	 }}, 
	 {$group: {
	     _id: "$difficulty",
	     tournaments: {
	         $push: "$tournament"
	     }
	   }}
	]).result