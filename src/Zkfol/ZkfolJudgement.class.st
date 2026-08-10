Class {
	#name : 'ZkfolJudgement',
	#superclass : 'Object',
	#instVars : [
		'labels',
		'evals',
		'terms',
		'termEvals',
		'trees',
		'sources',
		'rowLabels',
		'witness',
		'refusal',
		'labelWidth'
	],
	#category : 'Zkfol',
	#package : 'Zkfol'
}

{ #category : 'instance creation' }
ZkfolJudgement class >> labels: someLabels evals: aMatrix [
	^ self new setLabels: someLabels evals: aMatrix; yourself
]

{ #category : 'instance creation' }
ZkfolJudgement class >> onFeed: aDictionary [
	"The judgement feed whole, wherever it was fetched from: the act's
	 final stage or a statement in hand."
	^ self new
		setLabels: (aDictionary at: #labels)
			evals: (aDictionary at: #evals)
			terms: (aDictionary at: #terms ifAbsent: [ nil ])
			termEvals: (aDictionary at: #term_evals ifAbsent: [ nil ])
			trees: (aDictionary at: #trees ifAbsent: [ nil ])
			sources: (aDictionary at: #sources ifAbsent: [ nil ])
			rows: (aDictionary at: #rows ifAbsent: [ nil ])
			witness: (aDictionary at: #witness ifAbsent: [ nil ]);
		yourself
]

{ #category : 'instance creation' }
ZkfolJudgement class >> through: anApplication source: anElixirSource [
	"The node computes the judgement table; one wire trip. The source
	 must answer %{labels: [...], evals: [[...]]}. A refusal keeps what
	 the node said."
	| answer |
	answer := BeamProxyObject plainFetch: anElixirSource through: anApplication.
	(answer isKindOf: ZkfolRefusal) ifTrue: [ ^ self new refuse: answer reason; yourself ].
	^ self labels: (answer at: 'labels') evals: (answer at: 'evals')
]

{ #category : 'views' }
ZkfolJudgement >> canvasOn: aView title: aTitle priority: aNumber [
	"Me on a canvas as one node, so I pan and zoom as one picture,
	 and my cell clicks still spawn through phlow from inside it."
	^ aView mondrian
		title: aTitle;
		priority: aNumber;
		painting: [ :aMondrian |
			aMondrian nodes
				stencil: [ :each | each elementOrError ];
				with: { self } ]
]

{ #category : 'elements' }
ZkfolJudgement >> cellFor: aValue [
	"Zero is a quiet green; an objection shows its math in red."
	| text |
	text := BlTextElement new
		text: (aValue = 0
			ifTrue: [ '0' asRopedText foreground: Color darkGray ]
			ifFalse: [ aValue asString asRopedText foreground: Color red darker; bold ]).
	^ BlElement new
		layout: BlLinearLayout horizontal alignCenter;
		background: (aValue = 0
			ifTrue: [ Color green muchLighter muchLighter ]
			ifFalse: [ Color red muchLighter muchLighter ]);
		border: (BlBorder paint: Color veryLightGray width: 1);
		size: 64 @ 26;
		margin: (BlInsets all: 1);
		addChild: text;
		yourself
]

{ #category : 'elements' }
ZkfolJudgement >> cellFor: aValue satisfied: columnHolds [
	"Green answers for its column. In a column someone answers, the
	 others decline quietly in gray. Red is reserved for the failure:
	 the math of every branch in a column nobody answers."
	| text |
	text := BlTextElement new
		text: (aValue = 0
			ifTrue: [ '0' asRopedText foreground: Color darkGray ]
			ifFalse: [ columnHolds
				ifTrue: [ aValue asString asRopedText foreground: Color gray ]
				ifFalse: [ aValue asString asRopedText foreground: Color red darker; bold ] ]).
	^ BlElement new
		layout: BlLinearLayout horizontal alignCenter;
		background: (aValue = 0
			ifTrue: [ Color green muchLighter muchLighter ]
			ifFalse: [ columnHolds
				ifTrue: [ Color white ]
				ifFalse: [ Color red muchLighter muchLighter ] ]);
		border: (BlBorder paint: Color veryLightGray width: 1);
		size: 64 @ 26;
		margin: (BlInsets all: 1);
		addChild: text;
		yourself
]

{ #category : 'elements' }
ZkfolJudgement >> cellFor: aValue satisfied: columnHolds branch: b column: x [
	"One grid square in the shared vocabulary. Green answers, white
	 declines beside an answer, red only where nobody answers. A click
	 opens the branch's own clause as the root, unfolding into the
	 equations it lowered to, whose cells hop onward."
	| shown rope cell |
	shown := aValue = 0
		ifTrue: [ '0' ]
		ifFalse: [ ZkfolElements compactValue: aValue upTo: 5 ].
	rope := aValue = 0
		ifTrue: [ shown asRopedText foreground: Color darkGray ]
		ifFalse: [ columnHolds
			ifTrue: [ shown asRopedText foreground: Color gray ]
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
	shown = aValue printString
		ifFalse: [ cell aptitude: (BrWithExplicitTooltipAptitude text: aValue printString) ].
	trees ifNil: [ ^ cell ].
	^ self make: cell spawn: [
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

{ #category : 'elements' }
ZkfolJudgement >> elementOrError [
	"The stencil stays total: a refusal or an error draws itself rather
	 than raising on the async build path. The heatmap alone: the laid
	 witness is the Lay's to show, beside me."
	refusal ifNotNil: [ :why |
		^ BlTextElement new text: why asString asRopedText ].
	^ [ self heatmapElement ]
		on: Error
		do: [ :anError |
			BlTextElement new text: anError messageText asString asRopedText ]
]

{ #category : 'accessing' }
ZkfolJudgement >> evals [
	^ evals
]

{ #category : 'views' }
ZkfolJudgement >> gtEquationsFor: aView [
	"Each branch as the paper writes it: the formula whose squared sum
	 the grid scores. A column holds when some branch's sum reaches
	 zero there."
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
	 equations on a click. A refusal says why instead."
	<gtView>
	refusal ifNotNil: [ :why |
		^ aView explicit
			title: 'Judgement';
			priority: 1;
			stencil: [ BlTextElement new text: why asString asRopedText ] ].
	evals ifNil: [ ^ aView empty ].
	^ self canvasOn: aView title: 'Judgement' priority: 1
]

{ #category : 'elements' }
ZkfolJudgement >> headerCellOn: aString [
	"A column header: the column's width, the text's height."
	^ (ZkfolElements
		box: 64 @ 26
		color: nil
		text: (aString asRopedText foreground: Color darkGray)
		fontSize: 11)
		padding: (BlInsets all: 3);
		constraintsDo: [ :c | c horizontal exact: 64. c vertical fitContent ];
		yourself
]

{ #category : 'elements' }
ZkfolJudgement >> heatmapElement [
	"Branches down, trace columns across, one verdict per column, in
	 the one grid vocabulary the Lay beneath me speaks. Disjunction is
	 a product: a column holds when some branch zeroes it. Green
	 answers, white declines beside an answer, red only where nobody
	 answers. A branch label carries its formula as a tooltip; a cell
	 unfolds its equations; a header or verdict judges its column."
	| numCols holds rows header footer |
	numCols := evals first size.
	holds := (1 to: numCols) collect: [ :x |
		evals anySatisfy: [ :branchEvals | (branchEvals at: x) = 0 ] ].
	header := ZkfolElements gridRow.
	header addChild: (BlElement new size: (self labelWidth + 2) @ 16; yourself).
	1 to: numCols do: [ :x |
		header addChild: (self
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
		footer addChild: (self
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

{ #category : 'elements' }
ZkfolJudgement >> make: anElement spawn: aBlock [
	"Clicking anElement opens what the block answers in the next pane."
	anElement mouseCursor: BlHandCursor new.
	anElement addEventHandlerOn: BlClickEvent do: [ :evt |
		evt consumed: true.
		evt currentTarget phlow spawnObject: aBlock value ].
	^ anElement
]

{ #category : 'accessing' }
ZkfolJudgement >> refuse: aReason [
	refusal := aReason
]

{ #category : 'accessing' }
ZkfolJudgement >> rowLabels [
	^ rowLabels
]

{ #category : 'accessing' }
ZkfolJudgement >> setLabels: someLabels evals: aMatrix [
	labels := someLabels.
	evals := aMatrix
]

{ #category : 'accessing' }
ZkfolJudgement >> setLabels: someLabels evals: aMatrix terms: someTerms termEvals: aTermMatrix [
	labels := someLabels.
	evals := aMatrix.
	terms := someTerms.
	termEvals := aTermMatrix
]

{ #category : 'accessing' }
ZkfolJudgement >> setLabels: someLabels evals: aMatrix terms: someTerms termEvals: aTermMatrix sides: aSidesMatrix witness: witnessColumns [
	labels := someLabels.
	evals := aMatrix.
	terms := someTerms.
	termEvals := aTermMatrix.
	sides := aSidesMatrix.
	witness := witnessColumns
]

{ #category : 'accessing' }
ZkfolJudgement >> setLabels: someLabels evals: aMatrix terms: someTerms termEvals: aTermMatrix trees: aTreeMatrix sources: someSources rows: someRowLabels witness: witnessColumns [
	labels := someLabels.
	evals := aMatrix.
	terms := someTerms.
	termEvals := aTermMatrix.
	trees := aTreeMatrix.
	sources := someSources.
	rowLabels := someRowLabels.
	witness := witnessColumns
]

{ #category : 'accessing' }
ZkfolJudgement >> setLabels: someLabels evals: aMatrix terms: someTerms termEvals: aTermMatrix trees: aTreeMatrix sources: someSources witness: witnessColumns [
	labels := someLabels.
	evals := aMatrix.
	terms := someTerms.
	termEvals := aTermMatrix.
	trees := aTreeMatrix.
	sources := someSources.
	witness := witnessColumns
]

{ #category : 'accessing' }
ZkfolJudgement >> setLabels: someLabels evals: aMatrix terms: someTerms termEvals: aTermMatrix trees: aTreeMatrix witness: witnessColumns [
	labels := someLabels.
	evals := aMatrix.
	terms := someTerms.
	termEvals := aTermMatrix.
	trees := aTreeMatrix.
	witness := witnessColumns
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

{ #category : 'accessing' }
ZkfolJudgement >> witness [
	^ witness
]

