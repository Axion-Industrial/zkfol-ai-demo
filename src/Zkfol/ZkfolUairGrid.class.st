Class {
	#name : 'ZkfolUairGrid',
	#superclass : 'Object',
	#instVars : [
		'displayColumns',
		'kinds',
		'payload',
		'refusal',
		'derefCache',
		'hoverCache',
		'labelMode'
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

{ #category : 'cost' }
ZkfolUairGrid >> codewordLength [
	"What one committed column becomes once encoded: the cube times the
	 code's inverse rate. Nil when the backend named no rate."
	^ self repFactor ifNotNil: [ :r | r * self fullWidth ]
]

{ #category : 'accessing' }
ZkfolUairGrid >> columnAt: aPosition [
	"The whole trace position as an object: every row's cell, and the
	 deref chain of each composed read."
	^ ZkfolUairColumn
		position: aPosition
		bits: (ZkfolUairCell bitsOf: aPosition over: self numVars)
		cells: ((0 to: self displayColumns size - 1)
			collect: [ :row | self cellAtRow: row position: aPosition ])
		derefs: (self derefChainsAt: aPosition)
]

{ #category : 'cost' }
ZkfolUairGrid >> columnOpenings [
	"How many codeword positions an opening reveals: the proximity
	 test's sample count. Nil when the backend named none."
	^ self pcs ifNotNil: [ :p | p at: #column_openings ifAbsent: [ nil ] ]
]

{ #category : 'accessing' }
ZkfolUairGrid >> columns [
	^ payload at: #columns ifAbsent: [ #() ]
]

{ #category : 'accessing' }
ZkfolUairGrid >> composedReads [
	^ payload at: #reads ifAbsent: [ #() ]
]

{ #category : 'cost' }
ZkfolUairGrid >> costModel [
	"The proof's cost in the fewest rows that still say it: the shape
	 the fold runs over, what the code does to each committed column,
	 and the two totals -- the cells the prover touches and what it
	 sends. The code's rows appear only when the backend named its
	 parameters, since a cost view must not quote what it was not told."
	| rows cube mk out rep opens fold depth |
	rows := self displayColumns size.
	cube := self fullWidth.
	fold := rows * cube.
	mk := [ :n :f :v |
		Dictionary new at: #name put: n; at: #formula put: f; at: #value put: v; yourself ].
	out := OrderedCollection new.
	out add: (mk value: 'rows' value: 'committed columns' value: rows).
	out add: (mk value: 'cube' value: '2^mu, len ' , self len printString value: cube).
	out add: (mk value: 'sumcheck' value: 'rows x 2^mu' value: fold).
	rep := self repFactor.
	opens := self columnOpenings.
	rep ifNotNil: [
		out add: (mk value: 'codeword / column' value: 'rate x 2^mu' value: rep * cube).
		out add: (mk value: 'prover work' value: 'sumcheck + rows x rate x 2^mu'
			value: fold + (rows * rep * cube)) ].
	opens ifNotNil: [
		depth := ((rep * cube) max: 2) log: 2.
		out add: (mk value: 'proof cells' value: 'row 2^mu + draws x rows'
			value: cube + (rows * opens)).
		out add: (mk value: 'proof hashes' value: 'draws x log2 codeword'
			value: opens * depth rounded) ].
	^ out asArray
]

{ #category : 'cost' }
ZkfolUairGrid >> degree [
	"The degree of the predicate the trace's polynomial arithmetizes: the
	 budget the fold spends that the rows and the cube do not say. Nil
	 when the face named none."
	^ payload at: #degree ifAbsent: [ nil ]
]

{ #category : 'cost' }
ZkfolUairGrid >> degreeBound [
	"The highest degree the protocol's polynomials may reach, the backend's
	 own number. Nil when it named none."
	^ self pcs ifNotNil: [ :p | p at: #degree ifAbsent: [ nil ] ]
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
	1 to: self fullWidth do: [ :p |
		chains addAll: ((self derefChainsAt: p) select: [ :c |
			c agrees not
				and: [ c valueRow notNil
				and: [ c resultRow notNil
				and: [ c target between: 1 and: self fullWidth ] ] ] ]) ].
	^ chains
]

{ #category : 'rendering' }
ZkfolUairGrid >> fullWidth [
	"The widest committed column: the real trace length the display
	 draws from, before the render cap."
	^ self displayColumns
		inject: 0
		into: [ :max :each | each isCollection ifTrue: [ max max: each size ] ifFalse: [ max ] ]
]

{ #category : 'views' }
ZkfolUairGrid >> gtCommitmentFor: aView [
	"What the commitment does to one committed column. The picture owns
	 the view; I forward to it."
	<gtView>
	self displayColumns isEmpty ifTrue: [ ^ aView empty ].
	^ aView forward
		title: 'Commitment';
		priority: 5;
		object: [ ZkfolCommitPicture on: self ];
		view: #gtCommitmentFor:
]

{ #category : 'views' }
ZkfolUairGrid >> gtCostFor: aView [
	"The proof cost as a picture: the fold read off my committed strip.
	 The picture owns the view; I forward to it."
	<gtView>
	self displayColumns isEmpty ifTrue: [ ^ aView empty ].
	^ aView forward
		title: 'Cost';
		priority: 3;
		object: [ ZkfolCostPicture on: self ];
		view: #gtCostFor:
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
	 rows, colored by derived kind, the padding past the real trace
	 faded, claimed rows outlined. A toolbar toggle flips the position
	 ruler between its binary cube coordinate and its decimal index.

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
	^ (ZkfolElements canvasOn: aView title: 'Pointer grid' priority: 1 node: self picture)
		actionButtonIcon: BrGlamorousVectorIcons note
			tooltip: 'Toggle position labels between binary and decimal'
			action: [ :aButton :aTab | self toggleLabelMode. aTab phlow fireViewUpdateWish ]
]

{ #category : 'views' }
ZkfolUairGrid >> gtTotalsFor: aView [
	"Every cost in one table: the sumcheck's two axes, and what the
	 commitment does to each committed column, each with the formula
	 that gives it. The Cost view draws the fold; I total the rest."
	<gtView>
	self displayColumns isEmpty ifTrue: [ ^ aView empty ].
	^ aView columnedList
		title: 'Totals';
		priority: 4;
		items: [ self costModel ];
		column: 'Quantity' text: [ :each | each at: #name ] width: 150;
		column: 'Formula' text: [ :each | each at: #formula ] width: 200;
		column: 'Value' text: [ :each | (each at: #value) printString ]
]

{ #category : 'hover' }
ZkfolUairGrid >> hoverPairsOf: aRowIndex position: aPosition value: aValue [
	"What a hovered cell relates, each entry a colour paired with the
	 coordinates to light. A composed read touches its own pointer row,
	 its bits and its result; any of those cells lights that read alone
	 in the read's own colour, red where it contradicts itself, so the
	 relation can be entered from either end and neighbouring reads
	 stay dark. A scheduled row relates itself at each offset it carries,
	 the shift reaching forward across the committed columns."
	^ (hoverCache ifNil: [ hoverCache := Dictionary new ])
		at: aRowIndex @ aPosition
		ifAbsentPut: [
			| touching |
			touching := (self derefChainsAt: aPosition) select: [ :chain |
				chain addressRow = aRowIndex
					or: [ (chain bitRowIndices includes: aRowIndex)
					or: [ chain resultRow = aRowIndex ] ] ].
			touching
				ifNotEmpty: [ touching collect: [ :chain | chain displayColor -> chain coords ] ]
				ifEmpty: [ (self shiftOffsetsOfRow: aRowIndex) collect: [ :offset |
					ZkfolPalette highlightColor -> { aRowIndex @ (aPosition + offset) } ] ] ]
]

{ #category : 'rows' }
ZkfolUairGrid >> kindOfRow: aZeroBasedIndex [
	"The derived kind of one grid row, settled at construction."
	^ kinds at: aZeroBasedIndex + 1 ifAbsent: [ #plain ]
]

{ #category : 'accessing' }
ZkfolUairGrid >> labelMode [
	"How the position ruler reads: #binary the cube coordinate, #decimal
	 its index. Held here so it survives the view's own refresh."
	^ labelMode ifNil: [ labelMode := #binary ]
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
ZkfolUairGrid >> labelWidth [
	"The one width every row label wears, sized to the longest so the
	 grid's cells align whatever the labels say. The pointer grid and
	 the cost picture both read it off me rather than each sizing it."
	^ ZkfolElements labelWidthFor: ((0 to: self displayColumns size - 1)
		collect: [ :each | self labelTextFor: (self kindOfRow: each) at: each ])
]

{ #category : 'accessing' }
ZkfolUairGrid >> len [
	"How many committed positions are the real trace; the rest is the
	 base-case padding the cube is filled to."
	^ payload at: #len ifAbsent: [ self fullWidth ]
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

{ #category : 'cost' }
ZkfolUairGrid >> pcs [
	"The pinned code's parameters as the backend reported them, nil when
	 it reported none. A view that needs them says so rather than
	 quoting numbers of its own."
	^ payload at: #pcs ifAbsent: [ nil ]
]

{ #category : 'views' }
ZkfolUairGrid >> picture [
	"A fresh picture of me. Two of them never collide: the trace is
	 mine, the elements and the hover are each picture's own."
	^ ZkfolUairPicture on: self
]

{ #category : 'accessing' }
ZkfolUairGrid >> plainDataFrom: aUair [
	"The uair as its settled grid feed. A fixture already is one; a live
	 proxy asks the face, which is where everything Elixir-shaped stops.
	 When the boundary refuses I keep its reason, so the view can say
	 why instead of quietly not appearing. The code's own parameters ride
	 in beside the trace, since the cost is read off both."
	| answer pcs |
	aUair isDictionary ifTrue: [ ^ aUair ].
	answer := aUair plainFetch: 'Zkfol.Face.grid(' , aUair resolve , ')'.
	(answer isKindOf: ZkfolRefusal) ifTrue: [
		refusal := ZkfolRefusal because: 'no uair payload: ' , answer reason.
		^ Dictionary new ].
	pcs := aUair plainFetch: 'Zkfol.Face.pcs()'.
	pcs isDictionary ifTrue: [ answer at: #pcs put: pcs ].
	^ answer
]

{ #category : 'accessing' }
ZkfolUairGrid >> refusal [
	"Why the boundary could not read this uair, or nil when it did."
	^ refusal
]

{ #category : 'cost' }
ZkfolUairGrid >> repFactor [
	"The linear code's inverse rate: a column encodes to this many times
	 its own length. Nil when the backend named none."
	^ self pcs ifNotNil: [ :p | p at: #rep_factor ifAbsent: [ nil ] ]
]

{ #category : 'layout' }
ZkfolUairGrid >> runsWithEllipsis: sortedPositions [
	"Weave an #ellipsis marker into a sorted position list wherever it
	 skips a run, so a picture can draw the gaps as it draws the cells."
	| out prev |
	out := OrderedCollection new.
	prev := 0.
	sortedPositions do: [ :p |
		p > (prev + 1) ifTrue: [ out add: #ellipsis ].
		out add: p.
		prev := p ].
	^ out asArray
]

{ #category : 'initialization' }
ZkfolUairGrid >> setFromPayload: data [
	"Take everything the grid holds from one payload, and with it the
	 display model, which arrives settled: the face named every row's
	 kind, so I only take them in. A grid is made one way and does not
	 change after, which is what lets the derived model be resolved here
	 rather than rebuilt by every question asked of it."
	payload := data.
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

{ #category : 'layout' }
ZkfolUairGrid >> shownPositionsUpTo: aBudget [
	"The 1-based positions a picture draws when the cube outruns its
	 budget: a contiguous head, the real-to-padding seam always kept so
	 the tint boundary shows, and the tail of the cube. #ellipsis marks
	 each elided run. A cube within budget shows whole."
	| cube len keep front |
	cube := self fullWidth.
	cube <= aBudget ifTrue: [ ^ (1 to: cube) asArray ].
	len := self len.
	keep := Set new.
	front := (aBudget - 6) max: 3.
	1 to: (front min: cube) do: [ :p | keep add: p ].
	(len - 1 to: len + 2) do: [ :p | (p between: 1 and: cube) ifTrue: [ keep add: p ] ].
	(cube - 1 to: cube) do: [ :p | keep add: p ].
	^ self runsWithEllipsis: keep asSortedCollection asArray
]

{ #category : 'accessing' }
ZkfolUairGrid >> toggleLabelMode [
	"Flip the ruler between the binary cube coordinate and its decimal
	 index."
	labelMode := self labelMode = #binary ifTrue: [ #decimal ] ifFalse: [ #binary ]
]

{ #category : 'accessing' }
ZkfolUairGrid >> valueAtRow: aRowIndex position: aPosition [
	"The committed value at grid row and 1-based position, nil off the
	 grid, so chains agree with what is drawn."
	(aRowIndex isInteger and: [ aPosition isInteger ]) ifFalse: [ ^ nil ].
	(aRowIndex between: 0 and: self displayColumns size - 1) ifFalse: [ ^ nil ].
	^ (self displayColumns at: aRowIndex + 1) in: [ :col |
		(col isCollection and: [ aPosition between: 1 and: col size ])
			ifTrue: [ col at: aPosition ]
			ifFalse: [ nil ] ]
]
