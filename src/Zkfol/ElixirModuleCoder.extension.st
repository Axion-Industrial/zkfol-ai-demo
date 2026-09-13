Extension { #name : 'ElixirModuleCoder' }

{ #category : '*Zkfol' }
ElixirModuleCoder >> gtPassViewFor: aView context: aContext [
	"The module I edit as the pass it may be: every journaled run whose
	 route carried it, with its define id, each opening as the full
	 act's pipeline off the log, the play button replaying it from the
	 receipt the log rebuilds. A module that is no pass, or a bridge
	 that cannot answer, shows no tab: the one guarded degrade. Row
	 fields come straight off the feed; a feed missing them is a broken
	 log and should look broken."
	<gtElixirModuleView>
	| fetch feed |
	fetch := [ :source | BeamProxyObject plainFetch: source through: self application ].
	feed := fetch value: 'Zkfol.Face.pass(' , self moduleName , ')'.
	((feed isKindOf: Dictionary) and: [ (feed at: #implements) == true ])
		ifFalse: [ ^ aView empty ].
	^ aView columnedList
		title: 'Pass';
		priority: 22;
		items: [ feed at: #acts ];
		column: 'Id' text: [ :a | (a at: #defined) printString ] width: 50;
		column: 'Route' text: [ :a | (a at: #route) asString ] width: 180;
		column: '' text: [ :a |
			(a at: #verdict)
				ifNil: [ (a at: #settled) asString ]
				ifNotNil: [ :verdict | verdict asString , ' · ' , (a at: #settled) asString ] ];
		send: [ :a |
			| id2 act |
			id2 := (a at: #defined) printString.
			act := fetch value: 'Zkfol.Log.Ran.story(' , id2 , ')'.
			(ZkfolPipelineModel onAct: ((act isKindOf: Dictionary) ifTrue: [ act ] ifFalse: [ nil ]))
				replaySpawner: [ self application evaluateAndWait:
					'Zkfol.Log.Ran.replay(Zkfol.Log.Ran.at(Zkfol.Log.snapshot(), ' , id2 , '))' ];
				yourself ]
]
