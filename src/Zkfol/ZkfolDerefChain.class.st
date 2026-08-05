Class {
	#name : 'ZkfolDerefChain',
	#superclass : 'Object',
	#instVars : [
		'grid',
		'position',
		'read',
		'address',
		'target',
		'addressBits',
		'valueRow',
		'resultRow',
		'index'
	],
	#category : 'Zkfol-Values',
	#package : 'Zkfol',
	#tag : 'Values'
}

{ #category : 'instance creation' }
ZkfolDerefChain class >> onGrid: aGrid position: aPosition read: aRead index: aOneBasedIndex [
	"One composed read's chain at a position, recovered from the read's
	 own bit rows so the story is the one the circuit tells. The index is
	 the read's place among the grid's composed reads, which is what
	 gives me my colour."
	^ self new setGrid: aGrid position: aPosition read: aRead index: aOneBasedIndex
]

{ #category : 'accessing' }
ZkfolDerefChain >> address [
	"The number the pointer bits spell, 0-based in the reversed
	 committed layout."
	^ address
]

{ #category : 'queries' }
ZkfolDerefChain >> addressCells [
	"The pointer bit cells that spell my address, as cells rather than
	 bits, so each one opens onto its own row and position."
	| bitRows |
	bitRows := (read at: #bit_rows ifAbsent: [ nil ]) ifNil: [ #() ].
	^ bitRows collect: [ :r | grid cellAtRow: r position: position ]
]

{ #category : 'queries' }
ZkfolDerefChain >> agrees [
	"Whether following my address lands on my result: the invariant a
	 composed read exists to enforce, asked as a question rather than
	 recovered by matching fact names."
	^ self valueAtTarget = self resultHere
]

{ #category : 'queries' }
ZkfolDerefChain >> bitRowIndices [
	"The grid rows whose bits spell my address."
	^ (read at: #bit_rows ifAbsent: [ nil ]) ifNil: [ #() ]
]

{ #category : 'queries' }
ZkfolDerefChain >> cells [
	"Both ends of the chain and the bits between, every one an object
	 that opens onto its own row and position."
	^ (self addressCells asOrderedCollection
		addAll: { self targetCell. self resultCell };
		yourself) reject: [ :each | each isNil ]
]

{ #category : 'drawing' }
ZkfolDerefChain >> threads [
	"One thread from each address bit into the cell those bits spell,
	 then one from that cell to the result it must equal."
	| colour |
	self targetCell ifNil: [ ^ #() ].
	colour := self displayColor.
	^ (self bitRowIndices collect: [ :bitRow |
		(bitRow @ position -> (valueRow @ target)) -> colour ]) ,
		(self resultCell
			ifNil: [ #() ]
			ifNotNil: [ :ignored |
				{ (valueRow @ target -> (resultRow @ position)) -> colour } ])
]

{ #category : 'accessing' }
ZkfolDerefChain >> color [
	"The colour the grid lights this read in on hover, so chain and grid
	 agree which read is which at a glance."
	^ ZkfolPalette readColor: index - 1
]

{ #category : 'accessing' }
ZkfolDerefChain >> coords [
	"Where my cells sit, for whoever draws by coordinate."
	^ self cells collect: [ :each | each row @ each position ]
]

{ #category : 'accessing' }
ZkfolDerefChain >> displayColor [
	"My read's own colour, or the failure colour when I contradict
	 myself, so a broken dereference is never mistaken for ordinary
	 pointer traffic wherever I am drawn."
	^ self agrees
		ifTrue: [ self color ]
		ifFalse: [ ZkfolPalette failureColor ]
]

{ #category : 'queries' }
ZkfolDerefChain >> facts [
	"My chain spelled out: what my bits say, the displayed position that
	 number names, what is actually there, and what my result row claims
	 instead."
	^ {
		'address bits' -> (', ' join: (addressBits collect: [ :b | b printString ])).
		'address' -> address.
		'target position' -> target.
		'value row' -> valueRow.
		'value at target' -> self valueAtTarget.
		'result row' -> resultRow.
		'result here' -> self resultHere }
]

{ #category : 'queries' }
ZkfolDerefChain >> failureSummary [
	"Why I do not add up, in one line: what my bits spell, what actually
	 sits at the address they spell, and what my result row claims
	 instead. A red arrow asserts a failure; this says what it is."
	^ String streamContents: [ :s |
		s nextPutAll: 'read '; print: index;
		  nextPutAll: ' at position '; print: position;
		  nextPutAll: ': bits ';
		  nextPutAll: (', ' join: (addressBits collect: [ :b | b printString ]));
		  nextPutAll: ' spell address '; print: address;
		  nextPutAll: ', position '; print: target;
		  nextPutAll: '  ->  row '; print: valueRow;
		  nextPutAll: ' there holds '; print: self valueAtTarget;
		  nextPutAll: ', but row '; print: resultRow;
		  nextPutAll: ' here holds '; print: self resultHere ]
]

{ #category : 'views' }
ZkfolDerefChain >> gtCellsFor: aView [
	"Both ends of the chain and the address bits between, as cells: the
	 chain opens onto the grid rather than ending in a printed number."
	<gtView>
	^ aView columnedList
		title: 'Cells';
		priority: 6;
		items: [ self cells ];
		column: 'Row' text: [ :each | each row printString ] width: 60;
		column: 'Kind' text: [ :each | each kind ] width: 80;
		column: 'Position' text: [ :each | each position printString ] width: 70;
		column: 'Value' text: [ :each | each value printString ]
]

{ #category : 'views' }
ZkfolDerefChain >> gtFactsFor: aView [
	"My chain spelled out, fact by fact."
	<gtView>
	^ aView columnedList
		title: 'Facts';
		priority: 5;
		items: [ self facts ];
		column: 'Fact' text: [ :each | each key ] width: 130;
		column: 'Value' text: [ :each | each value ]
]

{ #category : 'views' }
ZkfolDerefChain >> gtWalkFor: aView [
	<gtView>
	grid ifNil: [ ^ aView empty ].
	^ (grid picture
		emphasis: self coords;
		connectors: self threads;
		yourself)
		canvasOn: aView title: 'Walk' priority: 3
]

{ #category : 'accessing' }
ZkfolDerefChain >> grid [
	"The trace I walk, so whoever draws several of us can lay it out once."
	^ grid
]

{ #category : 'accessing' }
ZkfolDerefChain >> index [
	"My place among the grid's composed reads, one-based."
	^ index
]

{ #category : 'accessing' }
ZkfolDerefChain >> position [
	"The trace position I dereference from."
	^ position
]

{ #category : 'printing' }
ZkfolDerefChain >> printOn: aStream [
	aStream
		nextPutAll: 'deref at ';
		print: position;
		nextPutAll: ' -> ';
		print: target.
	self agrees ifFalse: [ aStream nextPutAll: ' (disagrees)' ]
]

{ #category : 'queries' }
ZkfolDerefChain >> resultCell [
	"The cell the dereference lands in, here at my own position."
	^ resultRow ifNotNil: [ :r | grid cellAtRow: r position: position ]
]

{ #category : 'queries' }
ZkfolDerefChain >> resultHere [
	"What the result row carries at my own position."
	^ resultRow ifNotNil: [ :r | grid valueAtRow: r position: position ]
]

{ #category : 'accessing' }
ZkfolDerefChain >> resultRow [
	"The grid row carrying the dereference result at my position."
	^ resultRow
]

{ #category : 'accessing' }
ZkfolDerefChain >> setGrid: aGrid position: aPosition read: aRead index: aOneBasedIndex [
	"The address is spelled little-endian from the read's own bit rows
	 at this position, so a missing or non-integer bit contributes
	 nothing rather than raising; it counts 0-based in the reversed
	 committed layout."
	| bitRows |
	grid := aGrid.
	position := aPosition.
	read := aRead.
	index := aOneBasedIndex.
	bitRows := (aRead at: #bit_rows ifAbsent: [ nil ]) ifNil: [ #() ].
	addressBits := bitRows collect: [ :row | aGrid valueAtRow: row position: aPosition ].
	address := 0.
	addressBits doWithIndex: [ :bit :nu |
		bit isInteger ifTrue: [ address := address + (bit bitShift: nu - 1) ] ].
	target := aGrid tracesOrder
		ifTrue: [ aGrid fullWidth - address ]
		ifFalse: [ address + 1 ].
	valueRow := aRead at: #value_row ifAbsent: [ nil ].
	resultRow := aRead at: #result_row ifAbsent: [ nil ]
]

{ #category : 'accessing' }
ZkfolDerefChain >> target [
	"The displayed position my address names."
	^ target
]

{ #category : 'queries' }
ZkfolDerefChain >> targetCell [
	"The cell my address points at: the far end of the chain."
	^ valueRow ifNotNil: [ :r | grid cellAtRow: r position: target ]
]

{ #category : 'queries' }
ZkfolDerefChain >> valueAtTarget [
	"What sits in the value row at the position my address names."
	^ valueRow ifNotNil: [ :r | grid valueAtRow: r position: target ]
]

{ #category : 'accessing' }
ZkfolDerefChain >> valueRow [
	"The grid row my address indexes into."
	^ valueRow
]
