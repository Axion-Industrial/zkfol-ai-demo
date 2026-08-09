Class {
	#name : 'ZkfolDerivationGraph',
	#superclass : 'Object',
	#instVars : [
		'rows',
		'spawner'
	],
	#category : 'Zkfol-Views',
	#package : 'Zkfol',
	#tag : 'Views'
}

{ #category : 'instance creation' }
ZkfolDerivationGraph class >> onFeed: aDictionary [
	"The derivation feed: one row per fact beside what it consumed."
	^ self new setRows: (aDictionary at: #rows ifAbsent: [ #() ])
]

{ #category : 'accessing' }
ZkfolDerivationGraph >> edges [
	"One edge per consumption, consumer row to callee row with which
	 of the consumer's calls the read was, so the edge wears its
	 read's color and both ends stay the facts themselves."
	| byFact |
	byFact := Dictionary new.
	rows do: [ :row | byFact at: (row at: #fact) put: row ].
	^ rows flatCollect: [ :row |
		((row at: #consumes) collectWithIndex: [ :callee :oneBased |
			{ row. byFact at: callee ifAbsent: [ nil ]. oneBased - 1 } ])
				select: [ :edge | edge second notNil ] ]
]

{ #category : 'accessing' }
ZkfolDerivationGraph >> labelOf: aFact [
	"A fact says itself: its relation over its tuple, each value
	 compacted to cell honesty."
	^ (aFact first) asString , '(' , ((aFact allButFirst
		collect: [ :v | ZkfolElements compactValue: v upTo: 5 ]) fold: [ :a :b | a , ', ' , b ]) , ')'
]

{ #category : 'painting' }
ZkfolDerivationGraph >> paint: aMondrian [
	"The fact DAG as the run derived it: one node per established fact,
	 one arc per consumption pointing at what was read, each call
	 site's arcs wearing its read color, shared subderivations visibly
	 shared by their fan-in. A node's click answers through the
	 spawner, the statement beneath the fact; without one, the fact's
	 own row."
	aMondrian nodes
		shape: [ :row |
			| node |
			node := BlTextElement new
				text: ((self labelOf: (row at: #fact)) asRopedText fontSize: 11);
				background: ZkfolPalette nodeBackgroundColor;
				padding: (BlInsets all: 8);
				border: (BlBorder paint: ZkfolPalette nodeBorderColor);
				geometry: (BlRoundedRectangleGeometry cornerRadius: 4).
			spawner ifNotNil: [
				node mouseCursor: BlHandCursor new.
				node addEventHandlerOn: BlClickEvent do: [ :evt |
					evt consumed: true.
					evt currentTarget phlow spawnObject:
						(spawner value: (rows indexOf: row)) ] ].
			node ];
		with: rows.
	aMondrian edges
		stencil: [ :edge |
			| color |
			color := ZkfolPalette readColor: edge last.
			BlParabollaArcElement new
				zIndex: -1;
				curvatureFraction: 0.1;
				border: (BlBorder paint: (color alpha: 0.7) width: 1.5);
				toHead: (BlArrowheadSimpleArrow new
					arrowLengthFraction: 5;
					arrowNoseAngle: 60;
					border: (BlBorder paint: (color alpha: 0.7) width: 1.5)) ];
		connect: self edges
			from: [ :edge | edge first ]
			to: [ :edge | edge second ].
	aMondrian layout horizontalDominanceTree
		nodeDistance: 10;
		levelDistance: 40
]

{ #category : 'accessing' }
ZkfolDerivationGraph >> spawner: aBlock [
	"The block a node's click answers through, taking the fact's
	 1-based position in the derivation; without one, clicking spawns
	 the fact's own row."
	spawner := aBlock
]

{ #category : 'accessing' }
ZkfolDerivationGraph >> setRows: someRows [
	rows := someRows
]
