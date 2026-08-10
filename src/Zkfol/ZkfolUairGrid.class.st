Class {
	#name : 'ZkfolUairGrid',
	#superclass : 'Object',
	#instVars : [
		'displayColumns',
		'kinds',
		'payload',
		'refusal',
		'derefCache',
		'hoverCache'
	],
	#category : 'Zkfol-Grid',
	#package : 'Zkfol',
	#tag : 'Grid'
}

{ #category : 'instance creation' }
ZkfolUairGrid class >> onUair: aUair [
	"The one way to make a grid. The uair reaches me as ordinary
	 Smalltalk, the boundary having made it so."
	| grid |
	grid := self new.
	grid setFromPayload: (grid plainDataFrom: aUair).
	^ grid
]

{ #category : 'rows' }
ZkfolUairGrid >> cellAtRow: aZeroBasedIndex position: aPosition [
	"One cell as an object, its kind and bit coordinate derived. The
	 column, the target strip, and every deref chain all build cells
	 through me rather than repeating the four derivations."
	^ ZkfolUairCell
		row: aZeroBasedIndex
		kind: (self kindOfRow: aZeroBasedIndex)
		position: aPosition
		bits: (ZkfolUairCell bitsOf: aPosition over: self numVars)
		value: (self valueAtRow: aZeroBasedIndex position: aPosition)
]

{ #category : 'rows' }
ZkfolUairGrid >> columnAt: aPosition [
	"The whole trace position as an object: every row's cell, and the
	 deref chain of each composed read. Display orientation throughout."
	^ ZkfolUairColumn
		position: aPosition
		bits: (ZkfolUairCell bitsOf: aPosition over: self numVars)
		cells: ((0 to: self displayColumns size - 1)
			collect: [ :row | self cellAtRow: row position: aPosition ])
		derefs: (self derefChainsAt: aPosition)
]

{ #category : 'accessing' }
ZkfolUairGrid >> columns [
	^ payload at: #columns ifAbsent: [ #() ]
]


{ #category : 'rendering' }
ZkfolUairGrid >> compactValue: aNumber [
	"A cell is 24 points wide; a value that cannot say itself in five
	 characters says its two leading digits and its magnitude, honest
	 and terse: 1.2e20 is a 21 digit number. The full value stays one
	 hover or one click away."
	| s |
	s := aNumber printString.
	s size <= 5 ifTrue: [ ^ s ].
	aNumber isInteger ifFalse: [ ^ (s first: 4) , '…' ].
	^ s first asString , '.' , s second asString , 'e' , (s size - 1) printString
]

{ #category : 'accessing' }
ZkfolUairGrid >> composedReads [
	^ payload at: #reads ifAbsent: [ #() ]
]


{ #category : 'rows' }
ZkfolUairGrid >> derefChainsAt: aPosition [
	"One chain per composed read, each an object that recovers its own
	 address from the read's bit rows and knows both ends of the walk."
	^ (derefCache ifNil: [ derefCache := Dictionary new ])
		at: aPosition
		ifAbsentPut: [ self composedReads withIndexCollect: [ :read :oneBased |
			ZkfolDerefChain onGrid: self position: aPosition read: read index: oneBased ] ]
]


{ #category : 'rows' }
ZkfolUairGrid >> displayColumns [
	"The committed columns as displayed, settled at construction. Grid,
	 hover and deref chains all read through me."
	^ displayColumns
]

{ #category : 'rendering' }
ZkfolUairGrid >> fullWidth [
	"The widest committed column: the real trace length the display
	 draws from, before the render cap."
	^ self displayColumns
		inject: 0
		into: [ :max :each | each isCollection ifTrue: [ max max: each size ] ifFalse: [ max ] ]
]

{ #category : 'rows' }
ZkfolUairGrid >> displayedPositions [
	"How many trace positions actually get drawn: the trace's own width,
	 capped by the render cap."
	^ self fullWidth min: self picture maxPositions
]

{ #category : 'rows' }
ZkfolUairGrid >> failingChains [
	"Every composed read that contradicts itself, at every position."
	| chains |
	chains := OrderedCollection new.
	1 to: self displayedPositions do: [ :p |
		chains addAll: ((self derefChainsAt: p) select: [ :c |
			c agrees not
				and: [ c valueRow notNil
				and: [ c resultRow notNil
				and: [ c target between: 1 and: self displayedPositions ] ] ] ]) ].
	^ chains
]


{ #category : 'views' }
ZkfolUairGrid >> gtFailuresFor: aView [
	"The contradictions, one per line. A composed read claims the address
	 its bits spell lands on the value its result row holds; these are
	 the reads where it does not, with both numbers side by side so the
	 mismatch is the thing you read first. Clicking one opens the chain,
	 which draws its own walk.

	 An honest trace has nothing to list, so I am empty: if this tab is
	 there at all, something does not add up."
	<gtView>
	self failingChains ifEmpty: [ ^ aView empty ].
	^ aView columnedList
		title: 'Failures';
		priority: 2;
		items: [ self failingChains ];
		column: 'Read' text: [ :chain | chain index ] width: 50;
		column: 'Position' text: [ :chain | chain position ] width: 70;
		column: 'Address' text: [ :chain | chain address ] width: 70;
		column: 'At target' text: [ :chain | chain valueAtTarget ] width: 80;
		column: 'Result here' text: [ :chain | chain resultHere ] width: 90;
		column: 'Why' text: [ :chain | chain failureSummary ]
]

{ #category : 'views' }
ZkfolUairGrid >> gtPointerGridFor: aView [
	"The Uair pointer grid on Mondrian's canvas: committed columns as
	 rows, colored by derived kind, claimed rows outlined. The whole
	 trace is one Mondrian node, so it inherits the canvas's pan and
	 zoom, out to fit a wide fibonacci or in for a region's detail,
	 nothing cut off, no hand-rolled scroll or zoom control. The grid's
	 own cell, label, and header clicks still spawn through phlow from
	 inside the node. The stencil stays total: elementOrError draws its
	 own error rather than raising on the async build path.

	 A refused uair says so rather than answering no view at all."
	<gtView>
	refusal ifNotNil: [ :why |
		^ aView explicit
			title: 'Pointer grid';
			priority: 1;
			stencil: [ ZkfolElements
				safely: [ self error: why reason ]
				as: #zkfolUairGridRefused ] ].
	self columns isEmpty ifTrue: [ ^ aView empty ].
	^ self picture canvasOn: aView title: 'Pointer grid' priority: 1
]

{ #category : 'rows' }
ZkfolUairGrid >> hoverPairsOf: aRowIndex position: aPosition value: aValue [
	"What a hovered cell relates, each entry a colour paired with the
	 coordinates to light. Any cell a composed read touches lights that
	 whole read in the read's own colour, red where it contradicts
	 itself, so the relation can be entered from either end. A scheduled
	 row relates itself at each offset it carries; committed order flips
	 the shift the way trace order does not."
	^ (hoverCache ifNil: [ hoverCache := Dictionary new ])
		at: aRowIndex @ aPosition
		ifAbsentPut: [
			| touching |
			touching := (self derefChainsAt: aPosition) select: [ :chain |
				(self pointerRows includes: aRowIndex)
					or: [ (chain bitRowIndices includes: aRowIndex)
					or: [ chain resultRow = aRowIndex ] ] ].
			touching
				ifNotEmpty: [ touching collect: [ :chain | chain displayColor -> chain coords ] ]
				ifEmpty: [ (self shiftOffsetsOfRow: aRowIndex) collect: [ :offset |
					ZkfolPalette highlightColor -> {
						aRowIndex @ (self tracesOrder
							ifTrue: [ aPosition - offset ]
							ifFalse: [ aPosition + offset ]) } ] ] ]
]


{ #category : 'rows' }
ZkfolUairGrid >> kindOfRow: aZeroBasedIndex [
	"The derived kind of one grid row, settled at construction."
	^ kinds at: aZeroBasedIndex + 1 ifAbsent: [ #plain ]
]

{ #category : 'accessing' }
ZkfolUairGrid >> labelTextFor: aKind at: aZeroBasedIndex [
	"A row label at a glance: the index, the interpretation row it
	 carries, its kind or schedule, its claim."
	| parts origins |
	parts := OrderedCollection with: aZeroBasedIndex printString.
	origins := payload at: #origins ifAbsent: [ nil ].
	(origins notNil and: [ aZeroBasedIndex < origins size ]) ifTrue: [
		parts add: (origins at: aZeroBasedIndex + 1) ].
	aKind = #scheduled
		ifTrue: [ parts add: 'shifts '
			, (', ' join: ((self shiftOffsetsOfRow: aZeroBasedIndex)
				collect: [ :each | each printString ])) ]
		ifFalse: [ aKind = #plain ifFalse: [ parts add: aKind asString ] ].
	aZeroBasedIndex < self numPublic ifTrue: [ parts add: 'claimed' ].
	^ ' · ' join: parts
]

{ #category : 'accessing' }
ZkfolUairGrid >> lookups [
	^ payload at: #lookups ifAbsent: [ #() ]
]

{ #category : 'accessing' }
ZkfolUairGrid >> numCols [
	^ self columns size
]

{ #category : 'accessing' }
ZkfolUairGrid >> numPublic [
	^ payload at: #num_public ifAbsent: [ 0 ]
]

{ #category : 'accessing' }
ZkfolUairGrid >> numVars [
	"The cube's width, as the face read it off the padded columns."
	^ payload at: #num_vars ifAbsent: [ 0 ]
]


{ #category : 'views' }
ZkfolUairGrid >> picture [
	"A fresh picture of me. Two of them never collide: the trace is
	 mine, the elements and the hover are each picture's own."
	^ ZkfolUairPicture on: self
]

{ #category : 'private' }
ZkfolUairGrid >> plainDataFrom: aUair [
	"The uair as its settled grid feed. A fixture already is one; a live
	 proxy asks the face, which is where everything Elixir-shaped stops.
	 When the boundary refuses I keep its reason, so the view can say
	 why instead of quietly not appearing."
	| answer |
	aUair isDictionary ifTrue: [ ^ aUair ].
	answer := ZkfolProxy on: aUair fetch: 'Zkfol.Face.grid(' , aUair resolve , ')'.
	(answer isKindOf: ZkfolRefusal) ifTrue: [
		refusal := ZkfolRefusal because: 'no uair payload: ' , answer reason.
		^ Dictionary new ].
	^ answer
]

{ #category : 'rows' }
ZkfolUairGrid >> pointerRows [
	"The 0-based grid rows a Word lookup constrains as pointers. A
	 bit-poly lookup names col instead, an index into the binary shadow
	 columns that never appear in this grid, so I read only row."
	^ (self lookups
		collect: [ :each | each at: #row ifAbsent: [ nil ] ]
		thenReject: [ :each | each isNil ]) asSet
]

{ #category : 'accessing' }
ZkfolUairGrid >> refusal [
	"Why the boundary could not read this uair, or nil when it did."
	^ refusal
]



{ #category : 'initialization' }
ZkfolUairGrid >> setFromPayload: data [
	"Take everything the grid holds from one payload, then settle the
	 display model. A grid is made one way and does not change after,
	 which is what lets the derived model be resolved here rather than
	 rebuilt by every question asked of it."
	payload := data.
	self settle
]

{ #category : 'settling' }
ZkfolUairGrid >> settle [
	"The display model arrives settled: the face oriented the columns
	 and named every row's kind, so I only take them in."
	displayColumns := self columns.
	kinds := payload at: #kinds ifAbsent: [ #() ]
]

{ #category : 'rows' }
ZkfolUairGrid >> shiftOffsetsOfRow: aZeroBasedIndex [
	"Every offset the schedule gives this row, ascending: shifts arrive
	 as {col, offset} pairs and one row can carry several."
	^ ((self shifts
		select: [ :each | each isCollection and: [ each size = 2 and: [ each first = aZeroBasedIndex ] ] ])
		collect: [ :each | each second ]) asSortedCollection asArray
]

{ #category : 'accessing' }
ZkfolUairGrid >> shifts [
	^ payload at: #shifts ifAbsent: [ #() ]
]

{ #category : 'rows' }
ZkfolUairGrid >> tracesOrder [
	"Whether the face handed me trace order; a feed that says not is
	 shown committed and marked."
	^ payload at: #traces_order ifAbsent: [ false ]
]

{ #category : 'rows' }
ZkfolUairGrid >> valueAtRow: aRowIndex position: aPosition [
	"The displayed value at grid row and 1-based position, nil off the
	 grid. Display orientation, so chains agree with what is drawn."
	(aRowIndex isInteger and: [ aPosition isInteger ]) ifFalse: [ ^ nil ].
	(aRowIndex between: 0 and: self displayColumns size - 1) ifFalse: [ ^ nil ].
	^ (self displayColumns at: aRowIndex + 1) in: [ :col |
		(col isCollection and: [ aPosition between: 1 and: col size ])
			ifTrue: [ col at: aPosition ]
			ifFalse: [ nil ] ]
]
