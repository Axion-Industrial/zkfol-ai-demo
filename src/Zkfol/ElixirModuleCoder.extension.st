Extension { #name : 'ElixirModuleCoder' }

{ #category : '*Zkfol' }
ElixirModuleCoder >> gtPassViewFor: aView context: aContext [
	"Every run whose pipeline carried the module I edit, one row per run
	 id. Each column is its own query on the log; opening a row opens the
	 run itself, which carries the pipeline and every other view."
	<gtElixirModuleView>
	| app eval ids |
	app := self application.
	app ifNil: [ ^ aView empty ].
	eval := [ :source | app evaluateAndWait: source ].
	ids := (eval value: 'Zkfol.Log.module_runs(' , self moduleName , ')') asList.
	ids isEmpty ifTrue: [ ^ aView empty ].
	^ aView columnedList
		title: 'Pass';
		priority: 22;
		items: [ ids ];
		column: 'Id' text: [ :id | id printString ] width: 50;
		column: 'Route' text: [ :id |
			(eval value: 'elem(Zkfol.Log.define(' , id printString , '), 1)') symbol asString ] width: 180;
		column: 'Outcome' text: [ :id | self outcomeOf: id through: eval ];
		send: [ :id | eval value: 'Zkfol.Log.Run.at(Zkfol.Log.snapshot(), ' , id printString , ')' ]
]

{ #category : '*Zkfol' }
ElixirModuleCoder >> outcomeOf: anId through: anEvalBlock [
	"Proved, or the message of what refused the run, or nothing settled yet."
	| id |
	id := anId printString.
	(anEvalBlock value: 'Zkfol.Log.report(' , id , ') != nil') = true
		ifTrue: [ ^ 'proved' ].
	^ (anEvalBlock value:
		'case Zkfol.Log.refusal(' , id , ') do nil -> "unsettled"; r -> Zkfol.Refusal.message(r) end')
		asString
]
