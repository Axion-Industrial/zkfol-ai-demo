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
		'refusal'
	],
	#category : 'Zkfol',
	#package : 'Zkfol'
}

{ #category : 'instance creation' }
ZkfolJudgement class >> labels: someLabels evals: aMatrix [
	^ self new setLabels: someLabels evals: aMatrix; yourself
]

{ #category : 'instance creation' }
ZkfolJudgement class >> through: anApplication source: anElixirSource [
	"The node computes the judgement table; one wire trip. The source
	 must answer %{labels: [...], evals: [[...]]}."
	| answer |
	answer := ZkfolProxy fetch: anElixirSource through: anApplication.
	answer ifNil: [ ^ self new refuse: 'the node did not answer'; yourself ].
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
	"One package square, constrained the bloc way. Green answers, gray
	 declines beside an answer, red only where nobody answers. A click
	 opens the branch's own clause as the root, unfolding into the
	 equations it lowered to, whose cells hop onward."
	| shown rope cell |
	shown := aValue = 0 ifTrue: [ '0' ] ifFalse: [ self compactValue: aValue ].
	rope := aValue = 0
		ifTrue: [ shown asRopedText foreground: Color darkGray ]
		ifFalse: [ columnHolds
			ifTrue: [ shown asRopedText foreground: Color gray ]
			ifFalse: [ shown asRopedText foreground: Color red darker; bold ] ].
	cell := (ZkfolElements box: 64 @ 26 color: (aValue = 0
			ifTrue: [ Color green muchLighter muchLighter ]
			ifFalse: [ columnHolds
				ifTrue: [ Color white ]
				ifFalse: [ Color red muchLighter muchLighter ] ])
		text: rope
		fontSize: 11)
		border: (BlBorder paint: Color veryLightGray width: 1);
		padding: (BlInsets all: 3);
		constraintsDo: [ :c | c horizontal exact: 64. c vertical fitContent ];
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
ZkfolJudgement >> compactValue: aNumber [
	"A cell is 64 points wide; a value that cannot say itself in seven
	 characters says its two leading digits and its magnitude, honest
	 and terse: 1.2e20 is a 21 digit number. The exact value stays one
	 click away, in the cell's own equations."
	| s |
	s := aNumber printString.
	s size <= 7 ifTrue: [ ^ s ].
	aNumber isInteger ifFalse: [ ^ (s first: 6) , '…' ].
	^ s first asString , '.' , s second asString , 'e' , (s size - 1) printString
]

{ #category : 'elements' }
ZkfolJudgement >> elementOrError [
	"The stencil stays total: a refusal or an error draws itself rather
	 than raising on the async build path. The judgement above, the
	 named witness below it, columns aligned."
	refusal ifNotNil: [ :why |
		^ BlTextElement new text: why asString asRopedText ].
	^ [ | stack |
		stack := BlElement new
			layout: BlLinearLayout vertical;
			constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
			addChild: self heatmapElement;
			yourself.
		(witness notNil and: [ rowLabels notNil and: [ rowLabels notEmpty ] ])
			ifTrue: [ stack addChild: self witnessElement ].
		stack ]
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
	"Branches down, trace columns across, one verdict per column.
	 Disjunction is a product: a column holds when some branch zeroes
	 it. Green answers, gray declines, red only where nobody answers.
	 A branch label carries its formula as a tooltip; a cell unfolds
	 its equations; a column header or verdict judges its column."
	| numCols holds rows header footer |
	numCols := evals first size.
	holds := (1 to: numCols) collect: [ :x |
		evals anySatisfy: [ :branchEvals | (branchEvals at: x) = 0 ] ].
	header := BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		addChild: (self labelCellOn: '');
		yourself.
	1 to: numCols do: [ :x |
		header addChild: (self
			make: (self headerCellOn: 'x=', x asString)
			spawn: [ ZkfolJudgementColumn new setJudgement: self column: x; yourself ]) ].
	rows := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		addChild: header;
		yourself.
	labels doWithIndex: [ :aLabel :b |
		| line labelCell |
		labelCell := self labelCellOn: aLabel.
		(terms notNil and: [ (terms at: b) notEmpty ]) ifTrue: [
			labelCell aptitude: (BrWithExplicitTooltipAptitude
				text: (' and ' join: (terms at: b))) ].
		line := BlElement new
			layout: BlLinearLayout horizontal;
			constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
			addChild: labelCell;
			yourself.
		(evals at: b) doWithIndex: [ :aValue :x |
			line addChild: (self cellFor: aValue satisfied: (holds at: x) branch: b column: x) ].
		rows addChild: line ].
	footer := BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		addChild: (self labelCellOn: 'column holds');
		yourself.
	holds doWithIndex: [ :columnHolds :x |
		footer addChild: (self
			make: (self verdictCellOn: columnHolds)
			spawn: [ ZkfolJudgementColumn new setJudgement: self column: x; yourself ]) ].
	rows addChild: footer.
	^ rows
]

{ #category : 'elements' }
ZkfolJudgement >> labelCellOn: aString [
	| text |
	text := BlTextElement new
		text: (aString asRopedText fontSize: 11; foreground: Color darkGray).
	^ BlElement new
		layout: BlLinearLayout horizontal alignCenterLeft;
		padding: (BlInsets all: 3);
		margin: (BlInsets all: 1);
		constraintsDo: [ :c | c horizontal exact: 110. c vertical fitContent ];
		addChild: text;
		yourself
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
	"The column's verdict as an icon: it holds, or the judge refuses."
	^ BlElement new
		layout: BlLinearLayout horizontal alignCenter;
		padding: (BlInsets all: 3);
		margin: (BlInsets all: 1);
		constraintsDo: [ :c | c horizontal exact: 64. c vertical fitContent ];
		addChild: (columnHolds
			ifTrue: [ BrGlamorousVectorIcons accept asElement ]
			ifFalse: [ BrGlamorousVectorIcons cancel asElement
				background: Color red muchLighter;
				yourself ]);
		yourself
]

{ #category : 'accessing' }
ZkfolJudgement >> witness [
	^ witness
]

{ #category : 'elements' }
ZkfolJudgement >> witnessElement [
	"The interpretation whole, every row wearing its meaning, columns
	 aligned under the judgement's. Clicking a cell judges its column."
	| rows |
	rows := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		margin: (BlInsets top: 14);
		yourself.
	1 to: rowLabels size do: [ :i |
		| line |
		line := BlElement new
			layout: BlLinearLayout horizontal;
			constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
			addChild: (self labelCellOn: (rowLabels at: i));
			yourself.
		1 to: witness size do: [ :x |
			| v shown cell |
			v := (witness at: x) at: i.
			shown := self compactValue: v.
			cell := (ZkfolElements
				box: 64 @ 26
				color: Color white
				text: (shown asRopedText foreground: Color darkGray)
				fontSize: 11)
				border: (BlBorder paint: Color veryLightGray width: 1);
				padding: (BlInsets all: 3);
				constraintsDo: [ :c | c horizontal exact: 64. c vertical fitContent ];
				yourself.
			shown = v printString
				ifFalse: [ cell aptitude: (BrWithExplicitTooltipAptitude text: v printString) ].
			line addChild: (self make: cell spawn: [
				ZkfolJudgementColumn new setJudgement: self column: x; yourself ]) ].
		rows addChild: line ].
	^ rows
]
