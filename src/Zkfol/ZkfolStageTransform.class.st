Class {
	#name : 'ZkfolStageTransform',
	#superclass : 'Object',
	#instVars : [
		'routeName',
		'stage',
		'before',
		'after'
	],
	#category : 'Zkfol-Values',
	#package : 'Zkfol',
	#tag : 'Values'
}

{ #category : 'instance creation' }
ZkfolStageTransform class >> route: aName stage: aStage before: beforeState after: afterState [
	^ self new setRoute: aName stage: aStage before: beforeState after: afterState
]

{ #category : 'accessing' }
ZkfolStageTransform >> afterText [
	"The after state as diffable Elixir text."
	^ self textOf: after
]

{ #category : 'accessing' }
ZkfolStageTransform >> beforeText [
	"The before state as diffable Elixir text."
	^ self textOf: before
]

{ #category : 'accessing' }
ZkfolStageTransform >> delta [
	"The transformation as before-to-after facts: one row per fact the
	 two states name between them, marked when the pass changed it."
	| beforeFacts afterFacts |
	beforeFacts := self factsOf: before.
	afterFacts := self factsOf: after.
	^ (self factKeys select: [ :key |
		(beforeFacts at: key ifAbsent: [ nil ]) notNil
			or: [ (afterFacts at: key ifAbsent: [ nil ]) notNil ] ])
		collect: [ :key |
			| b a |
			b := beforeFacts at: key ifAbsent: [ nil ].
			a := afterFacts at: key ifAbsent: [ nil ].
			{ key. b. a. b ~= a } ]
]

{ #category : 'views' }
ZkfolStageTransform >> elixirStyler [
	"The Elixir syntax styler the coders use, built by the smaccStyler
	 pragma's own constructor over the SmaCC Elixir parser; nil when the
	 parser is not loaded, and the diff shows unstyled. The styler
	 skips what does not parse, so fixture summaries stay plain while
	 inspect output styles."
	^ (Smalltalk globals at: #ElixirParser ifAbsent: [ nil ])
		ifNotNil: [ :parserClass | GtSmaCCParserStyler elixirStyler: parserClass ]
]

{ #category : 'accessing' }
ZkfolStageTransform >> factKeys [
	"The statement facts a stage transition shows, in reading order. The
	 delta, the diff text and the fact extraction each carried their own
	 copy of this list."
	^ #(rels branches arity witness claims args)
]

{ #category : 'accessing' }
ZkfolStageTransform >> factsOf: aState [
	"The state's facts as one dictionary: a fixture summary already is
	 one, a live bridged statement summarises through the face in one
	 round trip, and a refusal or prepared string has none."
	(aState isKindOf: Dictionary) ifTrue: [ ^ aState ].
	(aState isKindOf: BeamProxyObject) ifTrue: [
		| fetched |
		fetched := aState plainFetch: 'Zkfol.Face.summary(' , aState resolve , ')'.
		^ (fetched isKindOf: Dictionary) ifTrue: [ fetched ] ifFalse: [ Dictionary new ] ].
	^ Dictionary new
]

{ #category : 'views' }
ZkfolStageTransform >> gtDeltaFor: aView [
	"How the pass transformed the statement: each fact before and after,
	 the changed ones marked in the highlight color."
	<gtView>
	^ aView columnedList
		title: 'Delta';
		priority: 5;
		items: [ self delta ];
		column: '' stencil: [ :each |
			(ZkfolElements swatch: ((each at: 4) ifTrue: [ ZkfolPalette highlightColor ] ifFalse: [ nil ]))
				margin: (BlInsets top: 2 right: 0 bottom: 0 left: 0);
				yourself ] width: 24;
		column: 'Fact' text: [ :each | each first ] width: 90;
		column: 'Before' text: [ :each | (each at: 2) printString ];
		column: 'After' text: [ :each | (each at: 3) printString ]
]

{ #category : 'views' }
ZkfolStageTransform >> gtDiffFor: aView [
	"The transformation in full: both states as pretty text under the
	 word diff, the detail beside Delta's glance, styled as the Elixir
	 it is when the parser is loaded."
	<gtView>
	| view |
	view := aView diff
		title: 'Diff';
		priority: 6;
		from: [ self beforeText ];
		to: [ self afterText ];
		fromLabel: 'stage ' , (stage index - 1) printString , ' · before ' , stage name;
		toLabel: 'stage ' , stage index printString , ' · after ' , stage name , ' ' , stage verdictLabel.
	self elixirStyler ifNotNil: [ :aStyler | view styler: aStyler ].
	^ view
]

{ #category : 'printing' }
ZkfolStageTransform >> printOn: aStream [
	aStream
		nextPutAll: routeName asString;
		nextPutAll: ' stage ';
		print: stage index - 1;
		nextPutAll: ' to ';
		print: stage index;
		nextPutAll: ': ';
		nextPutAll: stage name;
		nextPutAll: ' ';
		nextPutAll: stage verdictLabel
]

{ #category : 'accessing' }
ZkfolStageTransform >> setRoute: aName stage: aStage before: beforeState after: afterState [
	routeName := aName.
	stage := aStage.
	before := beforeState.
	after := afterState
]

{ #category : 'accessing' }
ZkfolStageTransform >> textOf: aState [
	"A state as diffable text: a prepared string stands, a fixture
	 summary formats one fact per line, and a live bridged statement
	 renders through the face, pretty and bounded, the witness elided
	 since a long trace as text is the noise, the pred the interesting
	 diff. A stale proxy degrades to its print string, never a raise."
	(aState isKindOf: ZkfolRefusal) ifTrue: [ ^ aState reason ].
	aState isString ifTrue: [ ^ aState ].
	(aState isKindOf: Dictionary) ifTrue: [
		^ String streamContents: [ :s |
			self factKeys do: [ :key |
				(aState includesKey: key) ifTrue: [
					s nextPutAll: key; nextPutAll: ': ';
						print: (aState at: key); cr ] ] ] ].
	(aState isKindOf: BeamProxyObject) ifTrue: [
		| fetched |
		fetched := aState plainFetch: 'Zkfol.Face.text(' , aState resolve , ')'.
		^ fetched isString ifTrue: [ fetched ] ifFalse: [ aState printString ] ].
	^ aState printString
]
