Extension { #name : 'ElixirModuleCoder' }

{ #category : '*Zkfol' }
ElixirModuleCoder >> gtPassViewFor: aView context: aContext [
	"The module I edit as the pass it may be: every journaled run whose
	 route carried it, with its define id, each opening as the full
	 act's pipeline off the log. A module that is no pass, or a bridge
	 that cannot answer, shows no tab: the one guarded degrade. Row
	 fields come straight off the feed; a feed missing them is a broken
	 log and should look broken."
	<gtElixirModuleView>
	| fetch feed |
	fetch := [ :source |
		[ ZkfolProxy plainly: (BeamLinkDeserializer new decodeWire:
			(STONJSON fromString: (self application evaluateAndWait:
				source , ' |> GtBridge.Serializer.to_json() |> elem(1)'))) ]
			on: Error
			do: [ :e | nil ] ].
	feed := fetch value: 'Zkfol.Face.pass(Zkfol.Log.snapshot(), ' , self moduleName , ')'.
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
			ZkfolPipelineModel onAct: (fetch value:
				'Zkfol.Face.act_at(Zkfol.Log.snapshot(), ' , (a at: #defined) printString , ')') ]
]
