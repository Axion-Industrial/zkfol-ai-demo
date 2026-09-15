Class {
	#name : 'ZkfolJudgement',
	#superclass : 'Object',
	#instVars : [
		'labels',
		'evals',
		'holds',
		'terms',
		'trees',
		'sources',
		'rowLabels',
		'witness',
		'labelWidth'
	],
	#category : 'Zkfol',
	#package : 'Zkfol'
}

{ #category : 'instance creation' }
ZkfolJudgement class >> onFeed: aDictionary [
	"The judgement feed whole, wherever it was fetched from: the act's
	 final stage or a statement in hand."
	^ self new
		setLabels: (aDictionary at: #labels)
			evals: (aDictionary at: #evals)
			terms: (aDictionary at: #terms ifAbsent: [ nil ])
			trees: (aDictionary at: #trees ifAbsent: [ nil ])
			sources: (aDictionary at: #sources ifAbsent: [ nil ])
			rows: (aDictionary at: #rows ifAbsent: [ nil ])
			witness: (aDictionary at: #witness ifAbsent: [ nil ])
			holds: (aDictionary at: #holds);
		yourself
]

{ #category : 'elements' }
ZkfolJudgement >> cellFor: aValue satisfied: columnHolds branch: b column: x [
	"One grid square in the shared vocabulary. Green answers, white
	 declines beside an answer, ⊥ a read beyond the matrix, red only
	 where nobody answers. A click opens the branch's own clause as the
	 root, unfolding into the equations it lowered to, whose cells hop
	 onward."
	| shown rope cell |
	shown := aValue = #error
		ifTrue: [ '⊥' ]
		ifFalse: [ aValue = 0
			ifTrue: [ '0' ]
			ifFalse: [ ZkfolElements compactValue: aValue upTo: 5 ] ].
	rope := aValue = 0
		ifTrue: [ shown asRopedText foreground: Color darkGray ]
		ifFalse: [ columnHolds
			ifTrue: [ shown asRopedText foreground: (aValue = #error
				ifTrue: [ Color lightGray ]
				ifFalse: [ Color gray ]) ]
			ifFalse: [ shown asRopedText foreground: Color red darker; bold ] ].
	cell := (ZkfolElements
		box: 24 @ 20
		color: (aValue = 0
			ifTrue: [ Color green muchLighter muchLighter ]
			ifFalse: [ columnHolds
				ifTrue: [ Color white ]
				ifFalse: [ Color red muchLighter muchLighter ] ])
		text: rope
		fontSize: 9)
		border: (BlBorder paint: Color veryLightGray width: 1);
		yourself.
	aValue = #error
		ifTrue: [ cell aptitude: (BrWithExplicitTooltipAptitude text: 'a read beyond the matrix') ]
		ifFalse: [ shown = aValue printString
			ifFalse: [ cell aptitude: (BrWithExplicitTooltipAptitude text: aValue printString) ] ].
	trees ifNil: [ ^ cell ].
	^ ZkfolElements make: cell spawn: [
		| root |
		root := Dictionary new
			at: #text put: (sources
				ifNil: [ labels at: b ]
				ifNotNil: [ :ss | ss isEmpty ifTrue: [ labels at: b ] ifFalse: [ ss at: b ] ]);
			at: #value put: aValue;
			at: #children put: ((trees at: b) at: x);
			yourself.
		ZkfolJudgementCell new
			setTitle: (labels at: b) , ' at x=' , x asString
			rows: { root }
			column: (witness ifNotNil: [ witness at: x ])
			judgement: self;
			yourself ]
]

{ #category : 'accessing' }
ZkfolJudgement >> evals [
	^ evals
]

{ #category : 'views' }
ZkfolJudgement >> gtEquationsFor: aView [
	"Each branch as the paper writes it: the formula whose squared sum
	 the grid scores. The oracle judges the whole predicate at each column."
	<gtView>
	terms ifNil: [ ^ aView empty ].
	^ aView columnedList
		title: 'Equations';
		priority: 2;
		items: [ (1 to: labels size) asOrderedCollection ];
		column: 'Branch' text: [ :b | labels at: b ] width: 140;
		column: 'Formula' text: [ :b | ' and ' join: (terms at: b) ]
]

{ #category : 'views' }
ZkfolJudgement >> gtHeatmapFor: aView [
	"The judgement as a picture: which branch answers for each column,
	 the math in red only where none does, each cell unfolding its
	 equations on a click."
	<gtView>
	evals ifNil: [ ^ aView empty ].
	^ ZkfolElements canvasOn: aView title: 'Judgement' priority: 1 node: self
]

{ #category : 'elements' }
ZkfolJudgement >> asElement [
	"Branches down, trace columns across, one verdict per column, in
	 the one grid vocabulary the Lay beneath me speaks. The heatmap
	 alone: the laid witness is the Lay's to show, beside me.
	 The oracle supplies the whole-predicate verdict. Green answers, white declines beside an answer, red only where nobody
	 answers. A branch label carries its formula as a tooltip; a cell
	 unfolds its equations; a header or verdict judges its column."
	| numCols rows header footer |
	numCols := evals first size.
	header := ZkfolElements gridRow.
	header addChild: (BlElement new size: (self labelWidth + 2) @ 16; yourself).
	1 to: numCols do: [ :x |
		header addChild: (ZkfolElements
			make: (ZkfolElements headerBox: x)
			spawn: [ ZkfolJudgementColumn new setJudgement: self column: x; yourself ]) ].
	rows := ZkfolElements gridContainer: #zkfolJudgement.
	rows addChild: header.
	labels doWithIndex: [ :aLabel :b |
		| line labelCell |
		labelCell := self labelCellOn: aLabel.
		(terms notNil and: [ (terms at: b) notEmpty ]) ifTrue: [
			labelCell aptitude: (BrWithExplicitTooltipAptitude
				text: (' and ' join: (terms at: b))) ].
		line := ZkfolElements gridRow.
		line addChild: labelCell.
		(evals at: b) doWithIndex: [ :aValue :x |
			line addChild: (self cellFor: aValue satisfied: (holds at: x) branch: b column: x) ].
		rows addChild: line ].
	footer := ZkfolElements gridRow.
	footer addChild: (self labelCellOn: 'column holds').
	holds doWithIndex: [ :columnHolds :x |
		footer addChild: (ZkfolElements
			make: (self verdictCellOn: columnHolds)
			spawn: [ ZkfolJudgementColumn new setJudgement: self column: x; yourself ]) ].
	rows addChild: footer.
	^ rows
]

{ #category : 'elements' }
ZkfolJudgement >> labelCellOn: aString [
	"A branch's introduction at the grid's one label width."
	^ ZkfolElements rowLabel: aString width: self labelWidth
]

{ #category : 'elements' }
ZkfolJudgement >> labelWidth [
	"One width for every branch label; a composer may hand both
	 stacked grids one width so their columns align."
	^ labelWidth ifNil: [ ZkfolElements labelWidthFor: (labels copyWith: 'column holds') ]
]

{ #category : 'elements' }
ZkfolJudgement >> labelWidth: aNumber [
	labelWidth := aNumber
]

{ #category : 'accessing' }
ZkfolJudgement >> labels [
	^ labels
]

{ #category : 'accessing' }
ZkfolJudgement >> rowLabels [
	^ rowLabels
]

{ #category : 'accessing' }
ZkfolJudgement >> setLabels: someLabels evals: aMatrix terms: someTerms trees: aTreeMatrix sources: someSources rows: someRowLabels witness: witnessColumns holds: verdicts [
	labels := someLabels.
	evals := aMatrix.
	terms := someTerms.
	trees := aTreeMatrix.
	sources := someSources.
	rowLabels := someRowLabels.
	witness := witnessColumns.
	holds := verdicts
]

{ #category : 'accessing' }
ZkfolJudgement >> trees [
	^ trees
]

{ #category : 'elements' }
ZkfolJudgement >> verdictCellOn: columnHolds [
	"The column's verdict as an icon at the grid's cell size: it
	 holds, or the judge refuses."
	| cell |
	cell := ZkfolElements
		box: 24 @ 20
		color: (columnHolds ifTrue: [ nil ] ifFalse: [ Color red muchLighter ])
		text: nil
		fontSize: 9.
	cell addChild: (columnHolds
		ifTrue: [ BrGlamorousVectorIcons accept asElement ]
		ifFalse: [ BrGlamorousVectorIcons cancel asElement ]).
	^ cell
]
