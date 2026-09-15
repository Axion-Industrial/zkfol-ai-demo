Class {
	#name : 'ZkfolPipelineModel',
	#superclass : 'Object',
	#instVars : [
		'thread',
		'define',
		'report',
		'failure',
		'passes',
		'stageSpawner',
		'emitSpawner',
		'reportSpawner',
		'replaySpawner'
	],
	#category : 'Zkfol-Views',
	#package : 'Zkfol',
	#tag : 'Views'
}

{ #category : 'accessing' }
ZkfolPipelineModel >> define: aTuple [
	define := aTuple
]

{ #category : 'accessing' }
ZkfolPipelineModel >> emitSpawner: aBlock [
	"The block answering the emitted UAIR for the prove tail; live it
	 re-emits and the exclass dresses the spawn in the pointer grid."
	emitSpawner := aBlock
]

{ #category : 'accessing' }
ZkfolPipelineModel >> eventTagged: aSymbol [
	^ thread
		detect: [ :each | ((each attributeAt: #body) itemAt: 0) symbol = aSymbol ]
		ifNone: [ nil ]
]

{ #category : 'accessing' }
ZkfolPipelineModel >> failure: aStringOrNil [
	failure := aStringOrNil
]

{ #category : 'views' }
ZkfolPipelineModel >> gtPipelineFor: aView [
	"The journaled act as a vertical Mondrian graph, stage nodes
	 clickable, the canvas pannable and zoomable so it fills the space
	 and fits however many stages the act ran. Its toolbar plays the act
	 again, when whoever opened me said how, and opens the new receipt."
	<gtView>
	| view |
	self passes isEmpty ifTrue: [ ^ aView empty ].
	view := aView mondrian
		title: 'Pipeline';
		priority: 5;
		painting: [ :aMondrian | self paintPipelineOn: aMondrian ].
	replaySpawner ifNotNil: [
		view
			actionButtonIcon: BrGlamorousVectorIcons play
			tooltip: 'Replay the act'
			action: [ :aButton | aButton phlow spawnObject: replaySpawner value ] ].
	^ view
]

{ #category : 'views' }
ZkfolPipelineModel >> gtThreadFor: aView [
	<gtView>
	thread isEmpty ifTrue: [ ^ aView empty ].
	^ aView columnedList
		title: 'Thread';
		priority: 6;
		items: [ thread ];
		column: 'Id' text: [ :each | (each attributeAt: #id) printString ] width: 60;
		column: 'Based on' text: [ :each | (each attributeAt: #basedon) printString ] width: 70;
		column: 'Body' text: [ :each | (each attributeAt: #body) printString ]
]

{ #category : 'accessing' }
ZkfolPipelineModel >> intentName [
	^ (self eventTagged: #prove_requested)
		ifNotNil: [ :each | ((each attributeAt: #body) itemAt: 1) symbol ]
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
	^ passes ifNil: [
		passes := (self eventTagged: #piped)
			ifNil: [ #() ]
			ifNotNil: [ :each |
				((each attributeAt: #body) itemAt: 1) asList
					withIndexCollect: [ :pair :index | ZkfolPipelineStage index: index pair: pair ] ] ]
]

{ #category : 'printing' }
ZkfolPipelineModel >> printOn: aStream [
	aStream
		nextPutAll: 'pipeline ';
		print: self routeName;
		nextPutAll: ', ';
		print: self passes size;
		nextPutAll: ' passes'.
	report ifNotNil: [ aStream nextPutAll: ', proved' ].
	failure ifNotNil: [ aStream nextPutAll: ', failed' ]
]

{ #category : 'accessing' }
ZkfolPipelineModel >> replaySpawner: aBlock [
	"The block answering the act run again, a fresh receipt; whoever
	 opens me off the log knows the define to replay from. Without one
	 the pipeline view has no play button."
	replaySpawner := aBlock
]

{ #category : 'accessing' }
ZkfolPipelineModel >> report [
	^ report
]

{ #category : 'accessing' }
ZkfolPipelineModel >> report: aReportOrNil [
	report := aReportOrNil
]

{ #category : 'accessing' }
ZkfolPipelineModel >> reportLabel [
	"The report's one line: verdict, timings, size, backend. A report
	 exists only where proving and verifying both succeeded, so its
	 presence is the verdict and there is no field to read for it."
	failure ifNotNil: [ ^ 'failed: ' , failure asString ].
	report ifNil: [ ^ 'unsettled' ].
	^ String streamContents: [ :s |
		s nextPutAll: 'proved'.
		(report attributeAt: #prove_ms)
			ifNotNil: [ :ms | s nextPutAll: ' · prove ' , ms printString , ' ms' ].
		(report attributeAt: #verify_ms)
			ifNotNil: [ :ms | s nextPutAll: ' · verify ' , ms printString , ' ms' ].
		(report attributeAt: #proof_bytes)
			ifNotNil: [ :b | s nextPutAll: ' · ' , b printString , ' B' ].
		(report attributeAt: #backend)
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
	^ (define itemAt: 1) symbol
]

{ #category : 'accessing' }
ZkfolPipelineModel >> stageNodes [
	"One node builder per stage, in order: the source, one per pass with
	 its verdict, the prove tail when the thread carries one, and the
	 report at the bottom. A log-opened act has no spawners, but its
	 report rides the feed, so that click still answers."
	| nodes |
	nodes := OrderedCollection new.
	nodes add: [ self
		nodeLabeled: 'source · ' , self routeName asString
		color: nil
		id: #zkfolPipelineSource
		click: [ self stageStateAt: 0 ] ].
	self passes do: [ :each |
		nodes add: [ self
			nodeLabeled: each label
			color: each verdictColor
			id: #zkfolPipelineNode
			click: [ self transformFor: each ] ] ].
	self intentName ifNotNil: [ :intent |
		nodes add: [ self
			nodeLabeled: 'prove · ' , intent asString
			color: (ZkfolPalette kindColor: #pointer)
			id: #zkfolPipelineIntent
			click: (emitSpawner ifNotNil: [ [ emitSpawner value ] ]) ] ].
	(report notNil or: [ failure notNil ]) ifTrue: [
		"a report exists only where it proved, so its presence settles it."
		nodes add: [ self
			nodeLabeled: self reportLabel
			color: (failure
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
ZkfolPipelineModel >> thread: events [
	thread := events
]

{ #category : 'accessing' }
ZkfolPipelineModel >> transformFor: aStage [
	"The stage's output as a transformation: what its pass received and
	 what it handed on, both re-run through the spawner."
	^ ZkfolStageTransform
		route: self routeName
		stage: aStage
		before: (self stageStateAt: aStage index - 1)
		after: (self stageStateAt: aStage index)
]
