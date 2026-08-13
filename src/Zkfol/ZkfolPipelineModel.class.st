Class {
	#name : 'ZkfolPipelineModel',
	#superclass : 'Object',
	#instVars : [
		'trail',
		'routeName',
		'passes',
		'intentName',
		'report',
		'proveFailure',
		'stageSpawner',
		'emitSpawner',
		'reportSpawner'
	],
	#category : 'Zkfol-Views',
	#package : 'Zkfol',
	#tag : 'Views'
}

{ #category : 'examples' }
ZkfolPipelineModel class >> example [
	"A realistic act at fixture scale, shaped exactly as the face's act
	 feed arrives: the composed hop route, four verdicts, the proof
	 intended and settled with a report. Stage states answer as prepared
	 statement summaries; the emit spawns a grid-wearing fixture so the
	 exclass principle shows without a node."
	| summaries report |
	summaries := {
		{ #rels -> 1. #branches -> nil. #witness -> nil. #claims -> 0. #args -> #(100) } asDictionary.
		{ #rels -> 0. #branches -> 3. #witness -> nil. #claims -> 0. #args -> #(100) } asDictionary.
		{ #rels -> 0. #branches -> 5. #witness -> nil. #claims -> 2. #args -> #(100) } asDictionary.
		{ #rels -> 0. #branches -> 5. #witness -> '8 rows'. #claims -> 2. #args -> #(100) } asDictionary.
		{ #rels -> 0. #branches -> 6. #witness -> '10 rows'. #claims -> 2. #args -> #(100) } asDictionary }.
	report := { #prove_ms -> 12.4. #verify_ms -> 1.7.
		#num_vars -> 3. #public_cols -> 1. #proof_bytes -> 4568.
		#backend -> 'zinc+ i64'.
		#claims -> { #('out' 6) } } asDictionary.
	^ (self onAct: {
		#route -> #composed_hop.
		#intent -> #composed_hop.
		#report -> report.
		#failure -> nil.
		#passes -> {
			{ #index -> 1. #name -> 'Doubling'. #verdict -> #rewrites } asDictionary.
			{ #index -> 2. #name -> 'Witness'. #verdict -> #solves } asDictionary.
			{ #index -> 3. #name -> 'Lang'. #verdict -> #lowers } asDictionary.
			{ #index -> 4. #name -> 'Accumulator'. #verdict -> #expands } asDictionary }.
		#trail -> {
			{ #id -> 41. #basedon -> nil. #body -> '{:define, :composed_hop, %Zkfol.Pipeline{}}' } asDictionary.
			{ #id -> 42. #basedon -> 41. #body -> '{:piped, [{Zkfol.Doubling, :rewrites}, ...]}' } asDictionary.
			{ #id -> 43. #basedon -> 42. #body -> '{:prove_requested, :composed_hop}' } asDictionary.
			{ #id -> 44. #basedon -> 43. #body -> '{:proved, %Zkfol.Prover.Report{}}' } asDictionary } } asDictionary)
		stageSpawner: [ :k | summaries at: k + 1 ];
		emitSpawner: [ ZkfolUairGrid onUair: ZkfolUairExamples new miniatureHop ];
		reportSpawner: [ report ];
		yourself
]

{ #category : 'instance creation' }
ZkfolPipelineModel class >> onAct: aFeed [
	"I read the face's act feed: the route, one pass per piped verdict
	 at display scale, the prove tail, and the rendered trail."
	^ self new readAct: aFeed; yourself
]

{ #category : 'accessing' }
ZkfolPipelineModel >> emitSpawner: aBlock [
	"The block answering the emitted UAIR for the prove tail; live it
	 re-emits and the exclass dresses the spawn in the pointer grid."
	emitSpawner := aBlock
]

{ #category : 'views' }
ZkfolPipelineModel >> gtPipelineFor: aView [
	"The journaled act as a vertical Mondrian graph, stage nodes
	 clickable, the canvas pannable and zoomable so it fills the space
	 and fits however many stages the act ran."
	<gtView>
	self passes isEmpty ifTrue: [ ^ aView empty ].
	^ aView mondrian
		title: 'Pipeline';
		priority: 5;
		painting: [ :aMondrian | self paintPipelineOn: aMondrian ]
]

{ #category : 'views' }
ZkfolPipelineModel >> gtTrailFor: aView [
	"The raw thread of events the act left on the log, oldest first."
	<gtView>
	self trail isEmpty ifTrue: [ ^ aView empty ].
	^ aView columnedList
		title: 'Trail';
		priority: 6;
		items: [ self trail ];
		column: 'Id' text: [ :each | (each at: #id) printString ] width: 60;
		column: 'Based on' text: [ :each | (each at: #basedon) printString ] width: 70;
		column: 'Body' text: [ :each | each at: #body ]
]

{ #category : 'accessing' }
ZkfolPipelineModel >> intentName [
	^ intentName
]

{ #category : 'accessing' }
ZkfolPipelineModel >> nodeLabeled: aString color: aColorOrNil id: anIdSymbol click: aBlockOrNil [
	"One pipeline node: a quiet rounded box with its label, its verdict
	 tinting the border, spawning what it names when clicked. A node
	 with nothing to spawn still consumes its clicks, or Mondrian's
	 default would spawn the node's model: a bare index."
	| node |
	node := BrHorizontalPane new
		id: anIdSymbol;
		background: ZkfolPalette nodeBackgroundColor;
		geometry: (BlRoundedRectangleGeometry cornerRadius: 4);
		border: (BlBorder
			paint: (aColorOrNil ifNil: [ ZkfolPalette nodeBorderColor ])
			width: 1);
		padding: (BlInsets top: 4 right: 10 bottom: 4 left: 10);
		margin: (BlInsets top: 1 right: 0 bottom: 1 left: 0);
		fitContent;
		addChild: (BlTextElement new
			text: (aString asRopedText fontSize: 11);
			yourself);
		yourself.
	aBlockOrNil
		ifNotNil: [ ZkfolElements make: node spawn: aBlockOrNil ]
		ifNil: [
			node addEventHandlerOn: BlClickEvent do: [ :evt | evt consumed: true ] ].
	^ node
]

{ #category : 'views' }
ZkfolPipelineModel >> paintPipelineOn: aMondrian [
	"The act as a vertical Mondrian graph: one node per stage in order,
	 reusing the shared node visual, a simple line down the consecutive
	 stages, laid out top-down. Node models are their positions, so the
	 edges join by identity and the same click still spawns each stage's
	 transform, emit, or report through phlow."
	| nodes |
	nodes := self stageNodes.
	aMondrian nodes
		stencil: [ :anIndex | (nodes at: anIndex) value ];
		with: (1 to: nodes size).
	aMondrian edges
		connect: ((1 to: nodes size - 1) collect: [ :i | i -> (i + 1) ])
		from: #key
		to: #value.
	aMondrian layout custom: GtGradVerticalDominanceTreeLayout new
]

{ #category : 'accessing' }
ZkfolPipelineModel >> passes [
	^ passes ifNil: [ #() ]
]

{ #category : 'printing' }
ZkfolPipelineModel >> printOn: aStream [
	aStream
		nextPutAll: 'pipeline ';
		print: routeName;
		nextPutAll: ', ';
		print: self passes size;
		nextPutAll: ' passes'.
	report ifNotNil: [ aStream nextPutAll: ', proved' ].
	proveFailure ifNotNil: [ aStream nextPutAll: ', failed' ]
]

{ #category : 'private' }
ZkfolPipelineModel >> readAct: aFeed [
	"One settled act feed from the face, taken in as it arrives, every
	 key present by construction. A nil feed, a stale proxy answering
	 the fetch with nothing, reads as an empty act rather than a raise."
	aFeed ifNil: [ ^ self ].
	routeName := aFeed at: #route.
	intentName := aFeed at: #intent.
	report := aFeed at: #report.
	proveFailure := aFeed at: #failure.
	trail := aFeed at: #trail.
	passes := (aFeed at: #passes) collect: [ :each |
		ZkfolPipelineStage
			index: (each at: #index)
			name: (each at: #name)
			verdict: (each at: #verdict) ]
]

{ #category : 'accessing' }
ZkfolPipelineModel >> report [
	^ report
]

{ #category : 'accessing' }
ZkfolPipelineModel >> reportLabel [
	"The report's one line: verdict, timings, size, backend. A report
	 exists only where proving and verifying both succeeded, so its
	 presence is the verdict and there is no field to read for it."
	proveFailure ifNotNil: [ ^ 'failed: ' , proveFailure asString ].
	report ifNil: [ ^ 'unsettled' ].
	^ String streamContents: [ :s |
		s nextPutAll: 'proved'.
		(report at: #prove_ms)
			ifNotNil: [ :ms | s nextPutAll: ' · prove ' , ms printString , ' ms' ].
		(report at: #verify_ms)
			ifNotNil: [ :ms | s nextPutAll: ' · verify ' , ms printString , ' ms' ].
		(report at: #proof_bytes)
			ifNotNil: [ :b | s nextPutAll: ' · ' , b printString , ' B' ].
		(report at: #backend)
			ifNotNil: [ :b | s nextPutAll: ' · ' , b asString ] ]
]

{ #category : 'accessing' }
ZkfolPipelineModel >> reportSpawner: aBlock [
	"The block answering the proved Report; live it fetches the real
	 struct so exclass can dress it, fixtures answer the plain facts."
	reportSpawner := aBlock
]

{ #category : 'accessing' }
ZkfolPipelineModel >> routeName [
	^ routeName
]

{ #category : 'accessing' }
ZkfolPipelineModel >> stageNodes [
	"One node builder per stage, in order: the source, one per pass with
	 its verdict, the prove tail when the trail carries one, and the
	 report at the bottom. A log-opened act has no spawners, but its
	 report rides the feed, so that click still answers."
	| nodes |
	nodes := OrderedCollection new.
	nodes add: [ self
		nodeLabeled: 'source · ' , routeName asString
		color: nil
		id: #zkfolPipelineSource
		click: [ self stageStateAt: 0 ] ].
	self passes do: [ :each |
		nodes add: [ self
			nodeLabeled: each label
			color: each verdictColor
			id: #zkfolPipelineNode
			click: [ self transformFor: each ] ] ].
	intentName ifNotNil: [
		nodes add: [ self
			nodeLabeled: 'prove · ' , intentName asString
			color: (ZkfolPalette kindColor: #pointer)
			id: #zkfolPipelineIntent
			click: (emitSpawner ifNotNil: [ [ emitSpawner value ] ]) ] ].
	(report notNil or: [ proveFailure notNil ]) ifTrue: [
		"a report exists only where it proved, so its presence settles it."
		nodes add: [ self
			nodeLabeled: self reportLabel
			color: (proveFailure
				ifNil: [ ZkfolPalette kindColor: #result ]
				ifNotNil: [ ZkfolPalette highlightColor ])
			id: #zkfolPipelineReport
			click: (reportSpawner
				ifNotNil: [ [ reportSpawner value ] ]
				ifNil: [ report ifNotNil: [ [ report ] ] ]) ] ].
	^ nodes
]

{ #category : 'accessing' }
ZkfolPipelineModel >> stageSpawner: aBlock [
	"The block answering stage k's state, 0 the source: fixture summaries
	 or a live Log.stage re-run over the bridge."
	stageSpawner := aBlock
]

{ #category : 'accessing' }
ZkfolPipelineModel >> stageStateAt: aStageIndex [
	"Stage k's state through the spawner, a refusal when there is none
	 or the re-run failed. It used to answer a String, which the stage
	 transform then treated as a state: fact:of: asked a String for its
	 #rels and got nil, because a String is indexed by integer."
	^ stageSpawner
		ifNil: [ ZkfolRefusal because: 'no stage spawner' ]
		ifNotNil: [ [ stageSpawner cull: aStageIndex ]
			on: Error
			do: [ :anError | ZkfolRefusal because: anError messageText asString ] ]
]

{ #category : 'accessing' }
ZkfolPipelineModel >> trail [
	^ trail ifNil: [ #() ]
]

{ #category : 'accessing' }
ZkfolPipelineModel >> transformFor: aStage [
	"The stage's output as a transformation: what its pass received and
	 what it handed on, both re-run through the spawner."
	^ ZkfolStageTransform
		route: routeName
		stage: aStage
		before: (self stageStateAt: aStage index - 1)
		after: (self stageStateAt: aStage index)
]
