Class {
	#name : 'ZkfolRun',
	#superclass : 'BeamProxyObject',
	#category : 'Zkfol-Proxies',
	#package : 'Zkfol',
	#tag : 'Proxies'
}

{ #category : 'accessing' }
ZkfolRun class >> elixirClass [
	"The proxy factory dispatches me for the journaled act's receipt."
	^ 'Zkfol.Log.Run'
]

{ #category : 'accessing' }
ZkfolRun >> emitted [
	"The final stage's statement emitted as its UAIR through the face:
	 the registered %Zkfol.Uair{} dispatches to ZkfolUair by exclass
	 and arrives already wearing the pointer grid; a refusal arrives
	 as its prose."
	^ self evaluateOrNil: 'Zkfol.Face.emitted(' , self resolve , ')'
]

{ #category : 'accessing' }
ZkfolRun >> finalStage [
	"The act's final statement, the bridged struct wearing its own
	 views; a run some pass refused answers a refusal that says so and
	 hides the forwarded tabs."
	| stage |
	stage := self evaluateOrNil: 'Zkfol.Log.Run.final_stage(' , self resolve , ')'.
	^ (stage isKindOf: ZkfolStatement)
		ifTrue: [ stage ]
		ifFalse: [ ZkfolRefusal because: 'no final stage: a pass refused' ]
]

{ #category : 'views' }
ZkfolRun >> gtDerivationFor: aView [
	"The final stage owns its derivation; I only forward to it, and a
	 stage that carries none hides the tab here."
	<gtView>
	<gtBeamView>
	(self stageCarries: 'derivation') ifFalse: [ ^ aView empty ].
	^ aView forward
		title: 'Derivation';
		priority: 11;
		object: [ self finalStage ];
		view: #gtDerivationGraphFor:
]

{ #category : 'views' }
ZkfolRun >> gtJudgementFor: aView [
	"The final stage owns the judgement; I only forward to it, and a
	 stage that carries no lay hides the tab here."
	<gtView>
	<gtBeamView>
	(self stageCarries: 'lay') ifFalse: [ ^ aView empty ].
	^ aView forward
		title: 'Judgement';
		priority: 9;
		object: [ self finalStage ];
		view: #gtJudgementFor:
]

{ #category : 'views' }
ZkfolRun >> gtLayFor: aView [
	"The final stage owns its lay; I only forward to it, and a stage
	 that carries none hides the tab here, since a forward cannot hide
	 itself."
	<gtView>
	<gtBeamView>
	(self stageCarries: 'lay') ifFalse: [ ^ aView empty ].
	^ aView forward
		title: 'Lay';
		priority: 10;
		object: [ self finalStage ];
		view: #gtLayFor:
]

{ #category : 'views' }
ZkfolRun >> gtObjectsFor: aView [
	"The act's interesting objects, one send each: my own beside the
	 final stage's own list, read from it rather than repeated here."
	<gtView>
	<gtBeamView>
	^ aView columnedList
		title: 'Objects';
		priority: 12;
		items: [ | stage |
			stage := self finalStage.
			{ 'source statement' -> [ self stageAt: 0 ].
				'final stage' -> [ stage ] }
				, stage interestingObjects
				, { 'emitted uair' -> [ self emitted ].
					'proved report' -> [ self provedReport ] } ];
		column: 'Object' text: [ :each | each key ];
		send: [ :each | each value value ]
]

{ #category : 'views' }
ZkfolRun >> gtPipelineFor: aView [
	"I show the journaled act as its vertical pipeline, built image-side
	 from the trail fetched over the bridge."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Pipeline' priority: 7 view: #gtPipelineFor:
]

{ #category : 'views' }
ZkfolRun >> gtProgramFor: aView [
	"The run's program where AL decompiles it; I only forward."
	<gtView>
	<gtBeamView>
	| program |
	program := self program.
	(program isKindOf: ALObject) ifFalse: [ ^ aView empty ].
	^ aView forward
		title: 'Program';
		priority: 9;
		object: [ program ];
		view: #gtMethodsFor:
]

{ #category : 'views' }
ZkfolRun >> gtThreadFor: aView [
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Thread' priority: 8 view: #gtThreadFor:
]

{ #category : 'accessing' }
ZkfolRun >> program [
	"The AL program my run installed: the class object on the run's own
	 branch, wearing AL's views. Nil while no run has landed."
	^ self evaluateOrNil: 'Zkfol.Face.program(Zkfol.Log.snapshot(), ' , self resolve , ')'
]

{ #category : 'accessing' }
ZkfolRun >> provedReport [
	"The report that settled my intent, fetched as the real struct so
	 exclass can dress it. The log owns the trail walk."
	^ self evaluateOrNil: 'Zkfol.Log.report(Zkfol.Log.snapshot(), ' , self resolve , ')'
]

{ #category : 'accessing' }
ZkfolRun >> replay [
	"The act run again from the arguments its define carries: a fresh
	 receipt, arriving as its own proxy."
	^ self evaluateAndWait: 'Zkfol.Log.Run.replay(' , self resolve , ')'
]

{ #category : 'accessing' }
ZkfolRun >> stageAt: aStageIndex [
	"Stage k re-run from the source over the bridge: the real statement,
	 registered, so the spawn is the bridged value itself. My #resolve
	 expression rides into the source at the call site, the index as its
	 own integer literal, the bridge's own splice."
	^ self evaluateOrNil:
		'Zkfol.Log.Run.stage(' , self resolve , ', ' , aStageIndex printString , ') |> elem(1)'
]

{ #category : 'accessing' }
ZkfolRun >> stageCarries: aReaderString [
	"Whether the act's final stage answers the reader, which says if a
	 forwarded tab can feed."
	^ true = (self evaluateOrNil: 'case Zkfol.Log.Run.final_stage(' , self resolve
		, ') do %Zkfol.Statement{} = s -> not is_nil(Zkfol.Statement.'
		, aReaderString , '(s)); _ -> false end')
]

{ #category : 'accessing' }
ZkfolRun >> viewModel [
	| eval run |
	run := self resolve.
	eval := [ :source | self application evaluateAndWait: source ].
	^ ZkfolPipelineModel new
		thread: (eval value: 'Zkfol.Log.thread(' , run , ')') asList;
		define: (eval value: 'Zkfol.Log.define(' , run , ')');
		report: (eval value: 'Zkfol.Log.report(' , run , ')');
		failure: (eval value: 'case Zkfol.Log.refusal(' , run
			, ') do nil -> nil; r -> Zkfol.Refusal.message(r) end');
		stageSpawner: [ :k | self stageAt: k ];
		emitSpawner: [ self emitted ];
		reportSpawner: [ self provedReport ];
		replaySpawner: [ self replay ];
		yourself
]
