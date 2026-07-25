Class {
	#name : 'ZkfolRan',
	#superclass : 'ZkfolProxy',
	#category : 'Zkfol-Proxies',
	#package : 'Zkfol',
	#tag : 'Proxies'
}

{ #category : 'accessing' }
ZkfolRan class >> elixirClass [
	"The proxy factory dispatches me for the journaled act's receipt."
	^ 'Zkfol.Log.Ran'
]

{ #category : 'accessing' }
ZkfolRan >> emitted [
	"The final stage's statement emitted as its UAIR through the face:
	 the registered %Zkfol.Uair{} dispatches to ZkfolUair by exclass
	 and arrives already wearing the pointer grid; a refusal arrives
	 as its prose."
	^ self evaluateOrNil: 'Zkfol.Face.emitted(' , self resolve , ')'
]

{ #category : 'views' }
ZkfolRan >> gtPipelineFor: aView [
	"I show the journaled act as its vertical pipeline, built image-side
	 from the trail fetched over the bridge."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Pipeline' priority: 7 view: #gtPipelineFor:
]

{ #category : 'views' }
ZkfolRan >> gtTrailFor: aView [
	"The raw thread of events my act left on the log."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Trail' priority: 8 view: #gtTrailFor:
]

{ #category : 'accessing' }
ZkfolRan >> provedReport [
	"The report that settled my intent, fetched as the real struct so
	 exclass can dress it. My #resolve expression is spliced into the
	 trail lookup at the call site, no marker."
	^ self evaluateOrNil: 'Zkfol.Log.trail(Zkfol.Log.snapshot(), ' , self resolve , ')
		|> Enum.find_value(fn
			%{body: {:proved, report}} -> report
			_ -> nil
		end)'
]

{ #category : 'accessing' }
ZkfolRan >> stageAt: aStageIndex [
	"Stage k re-run from the source over the bridge: the real statement,
	 registered, so the spawn is the bridged value itself. My #resolve
	 expression rides into the source at the call site, the index as its
	 own integer literal, the bridge's own splice."
	^ self evaluateOrNil:
		'Zkfol.Log.stage(' , self resolve , ', ' , aStageIndex printString , ') |> elem(1)'
]

{ #category : 'accessing' }
ZkfolRan >> viewModel [
	"My act off the log, one feed from the face. A stale proxy answers
	 the fetch nil, which reads as an empty act, not a raise. Stage
	 states re-run live through Log.stage so a click spawns the real
	 bridged statement, the emit re-emitted through the face so it wears
	 the pointer grid, the report fetched as its struct."
	| feed |
	feed := ZkfolProxy
		on: self
		fetch: 'Zkfol.Face.act(Zkfol.Log.snapshot(), ' , self resolve , ')'.
	(feed isKindOf: ZkfolRefusal) ifTrue: [ feed := nil ].
	^ (ZkfolPipelineModel onAct: feed)
		stageSpawner: [ :k | self stageAt: k ];
		emitSpawner: [ self emitted ];
		reportSpawner: [ self provedReport ];
		yourself
]
