Class {
	#name : 'ZkfolUairPicture',
	#superclass : 'Object',
	#instVars : [
		'grid',
		'cellElements',
		'hovered',
		'hoverLayer',
		'emphasis',
		'connectors',
		'decorated'
	],
	#category : 'Zkfol-Grid',
	#package : 'Zkfol',
	#tag : 'Grid'
}

{ #category : 'instance creation' }
ZkfolUairPicture class >> on: aGrid [
	^ self new setGrid: aGrid; yourself
]

{ #category : 'initialization' }
ZkfolUairPicture >> setGrid: aGrid [
	grid := aGrid
]

{ #category : 'rendering' }
ZkfolUairPicture >> asElement [
	"The whole trace at a glance: a clickable position ruler, then one
	 row per committed column, colored by what the emitter derived it
	 for, claimed rows outlined, cells pointing where they point. Trace
	 order when the face marked the feed so, committed order with a
	 marker when it did not, so the reader is never shown the mirror as the trace. A
	 trace past the render cap shows its first positions and says so."
	| container |
	cellElements := Dictionary new.
	hovered := nil.
	decorated := nil.
	container := ZkfolElements gridContainer: #zkfolUairGrid.
	grid tracesOrder ifFalse: [ container addChild: self orientationMarkerElement ].
	self truncated ifTrue: [ container addChild: self truncationMarkerElement ].
	container addChild: self headerRowElement.
	grid displayColumns doWithIndex: [ :each :oneBased |
		container addChild: (self rowElementFor: each at: oneBased - 1) ].
	hoverLayer := ZkfolElements overlay: #zkfolUairHoverLayer.
	container addChild: hoverLayer.
	self refreshHover.
	^ container
]

{ #category : 'hover' }
ZkfolUairPicture >> borderFor: aCoord lit: aDictionary [
	"What a cell wears, derived: the hover outline if it is the one under
	 the mouse, its relation's colour if the hovered cell relates it, and
	 nothing otherwise."
	aCoord = hovered ifTrue: [ ^ BlBorder paint: ZkfolPalette hoverColor width: 1 ].
	^ (aDictionary at: aCoord ifAbsent: [ nil ])
		ifNil: [ BlBorder empty ]
		ifNotNil: [ :color | BlBorder paint: color width: 2 ]
]

{ #category : 'rendering' }
ZkfolUairPicture >> cellElementFor: aValue row: aRowIndex position: aPosition kind: aKind [
	"One colored square. Clicking it spawns the spelled-out cell in the
	 next pane; hovering sets which cell is hovered and every highlight
	 and connector follows from that. A value too big for the cell
	 compacts to its magnitude and carries its full self as a tooltip."
	| cell text |
	text := ZkfolElements compactValue: aValue upTo: 5.
	cell := (ZkfolElements
		box: 24 @ 20
		color: (ZkfolPalette kindColor: aKind)
		text: text
		fontSize: (text size > 4 ifTrue: [ 8 ] ifFalse: [ 9 ]))
		id: #zkfolUairCell;
		yourself.
	text = aValue printString
		ifFalse: [ cell aptitude: (BrWithExplicitTooltipAptitude text: aValue printString) ].
	cellElements ifNil: [ cellElements := Dictionary new ].
	cellElements at: aRowIndex @ aPosition put: cell.
	cell addEventHandlerOn: BlMouseEnterEvent do: [ :evt |
		self hovered: aRowIndex @ aPosition ].
	cell addEventHandlerOn: BlMouseLeaveEvent do: [ :evt | self hideHover ].
	^ ZkfolElements make: cell spawn: [ grid cellAtRow: aRowIndex position: aPosition ]
]

{ #category : 'hover' }
ZkfolUairPicture >> connectorFrom: aSource to: aTarget color: aColor [
	"One hover connector between the very cells, wearing the layer's id."
	^ (ZkfolElements connectorFrom: aSource to: aTarget color: aColor)
		id: #zkfolUairHoverLine;
		yourself
]

{ #category : 'accessing' }
ZkfolUairPicture >> connectors: aCollectionOfThreads [
	"The threads this rendering draws, each `(from -> to) -> colour`.
	 With none declared, hover draws its own."
	connectors := aCollectionOfThreads
]

{ #category : 'hover' }
ZkfolUairPicture >> drawStarOf: lit [
	"The cell under the mouse, to everything it lights."
	| source |
	source := hovered ifNotNil: [ :c | cellElements at: c ifAbsent: [ nil ] ].
	source ifNil: [ ^ self ].
	lit keysAndValuesDo: [ :coord :color |
		(cellElements at: coord ifAbsent: [ nil ]) ifNotNil: [ :target |
			hoverLayer addChild: (self connectorFrom: source to: target color: color) ] ]
]

{ #category : 'hover' }
ZkfolUairPicture >> drawThreads: aCollectionOfThreads [
	"Each declared thread, end to end."
	aCollectionOfThreads do: [ :thread |
		(cellElements at: thread key key ifAbsent: [ nil ]) ifNotNil: [ :from |
			(cellElements at: thread key value ifAbsent: [ nil ]) ifNotNil: [ :to |
				hoverLayer addChild: (self connectorFrom: from to: to color: thread value) ] ] ]
]

{ #category : 'accessing' }
ZkfolUairPicture >> emphasis: aCollectionOfCoords [
	"The cells this rendering is about. Everything else fades."
	emphasis := aCollectionOfCoords asSet
]

{ #category : 'rendering' }
ZkfolUairPicture >> headerElementFor: aPosition [
	"One position header: the trace position, clickable, spawning the
	 whole column at that position, deref chain included."
	| header |
	header := (ZkfolElements headerBox: aPosition)
		id: #zkfolUairHeader;
		yourself.
	header aptitude: (BrStyleCommonAptitude new
			default: [ :w | w border: BlBorder empty ];
			hovered: [ :w | w border: (BlBorder paint: ZkfolPalette hoverColor width: 1) ];
			yourself).
	^ ZkfolElements make: header spawn: [ grid columnAt: aPosition ]
]

{ #category : 'rendering' }
ZkfolUairPicture >> headerRowElement [
	"The position ruler over the grid: a spacer the width of the row
	 labels, then one clickable header per shown position."
	| row |
	row := ZkfolElements gridRow.
	row addChild: (BlElement new size: (self labelWidth + 2) @ 16; yourself).
	1 to: (self maxPositions min: grid fullWidth) do: [ :pos |
		row addChild: (self headerElementFor: pos) ].
	^ row
]

{ #category : 'hover' }
ZkfolUairPicture >> hideHover [
	"Nothing is hovered. Everything follows."
	self hovered: nil
]

{ #category : 'hover' }
ZkfolUairPicture >> hoverLit [
	"Coordinate -> colour for everything the hovered cell relates, empty
	 when nothing is hovered. The pairs already know their colours; I
	 only flatten them into a lookup."
	| lit |
	lit := Dictionary new.
	hovered ifNil: [ ^ lit ].
	(grid
		hoverPairsOf: hovered x
		position: hovered y
		value: (grid valueAtRow: hovered x position: hovered y))
			do: [ :pair | pair value do: [ :coord | lit at: coord put: pair key ] ].
	^ lit
]

{ #category : 'hover' }
ZkfolUairPicture >> hovered: aCoordOrNil [
	"Which cell the mouse is over, and the whole of what hover state is.
	 Every highlight and every connector is a function of me, so nothing
	 has to remember what it drew in order to take it back."
	hovered := aCoordOrNil.
	self refreshHover
]

{ #category : 'rendering' }
ZkfolUairPicture >> labelElementFor: aKind at: aZeroBasedIndex column: aColumn [
	"A row introduces itself: its index, kind or schedule, and claim.
	 Clicking it spawns the whole row in the next pane."
	| label |
	label := (ZkfolElements
		rowLabel: (grid labelTextFor: aKind at: aZeroBasedIndex)
		width: self labelWidth)
		id: #zkfolUairRowLabel;
		yourself.
	^ ZkfolElements make: label spawn: [ ZkfolUairRow
		index: aZeroBasedIndex
		kind: aKind
		claimed: aZeroBasedIndex < grid numPublic
		values: aColumn
		numVars: grid numVars ]
]

{ #category : 'rendering' }
ZkfolUairPicture >> labelWidth [
	"The grid's one label width, off every row's introduction."
	^ ZkfolElements labelWidthFor: ((0 to: grid displayColumns size - 1)
		collect: [ :each | grid labelTextFor: (grid kindOfRow: each) at: each ])
]

{ #category : 'rendering' }
ZkfolUairPicture >> markerElement: aString id: anId [
	"A line the grid says about itself, so what it cannot do is never
	 silent."
	^ BlTextElement new
		id: anId;
		text: (aString asRopedText
			fontSize: 9;
			foreground: ZkfolPalette highlightColor;
			yourself);
		padding: (BlInsets top: 4 right: 0 bottom: 4 left: 4);
		yourself
]

{ #category : 'rendering' }
ZkfolUairPicture >> maxPositions [
	"How many trace positions a row renders. The whole uair already
	 arrives in one JSON round trip, so this is a render bound, not a
	 fetch bound: every shown cell is an interactive element with its
	 own handlers, and a few thousand of them stay responsive while
	 tens of thousands would not. Five hundred twelve covers every
	 realistic trace in full and scrolls; a larger trace shows its
	 first 512 with an honest marker rather than a silent cut."
	^ 512
]

{ #category : 'rendering' }
ZkfolUairPicture >> orientationMarkerElement [
	"The face left the feed in committed order, so I show it that way and say
	 so rather than index the mirror cell with false confidence."
	^ self
		markerElement: 'committed order, orientation unknown'
		id: #zkfolOrientationMarker
]

{ #category : 'hover' }
ZkfolUairPicture >> refreshHover [
	"Only the decorations that actually change follow the mouse. The
	 emphasis dim and the declared thread connectors are static: a deref
	 chain's threads do not move as you hover, so they are drawn once, the
	 first time through. Every hover after touches only the border delta,
	 and, absent declared threads, the dynamic hover star. So a hover is
	 O(the few cells that change), not O(the grid) plus a rebuild of every
	 connector every frame."
	| lit now |
	lit := self hoverLit.
	now := lit keys asSet.
	hovered ifNotNil: [ now add: hovered ].
	cellElements ifNotNil: [
		decorated ifNil: [
			decorated := Set new.
			emphasis ifNotNil: [
				cellElements keysAndValuesDo: [ :coord :element |
					element opacity: ((emphasis includes: coord)
						ifTrue: [ 1.0 ]
						ifFalse: [ 0.25 ]) ] ].
			(hoverLayer notNil and: [ connectors notNil ]) ifTrue: [
				hoverLayer removeChildren.
				self drawThreads: connectors ] ].
		decorated do: [ :coord |
			(now includes: coord) ifFalse: [
				(cellElements at: coord ifAbsent: [ nil ])
					ifNotNil: [ :element | element border: BlBorder empty ] ] ].
		now do: [ :coord |
			(cellElements at: coord ifAbsent: [ nil ])
				ifNotNil: [ :element | element border: (self borderFor: coord lit: lit) ] ].
		decorated := now ].
	(hoverLayer notNil and: [ connectors isNil ]) ifTrue: [
		hoverLayer removeChildren.
		self drawStarOf: lit ]
]

{ #category : 'rendering' }
ZkfolUairPicture >> rowElementFor: aColumn at: aZeroBasedIndex [
	"One committed column as one grid row: a label, then a colored square
	 per trace position up to the render cap, every one spawning what it
	 names. The first numPublic rows are the claimed ones the verifier
	 reads in the clear, so they wear an outline. Past the cap the row
	 stops; the grid's truncation marker carries the honest count. A
	 malformed column renders as its own message; the grid never raises
	 mid-render."
	| row kind shown |
	kind := grid kindOfRow: aZeroBasedIndex.
	row := ZkfolElements gridRow.
	aZeroBasedIndex < grid numPublic
		ifTrue: [ row border: (BlBorder paint: ZkfolPalette outlineColor width: 2) ].
	aColumn isCollection
		ifFalse: [
			row addChild: (self labelElementFor: kind at: aZeroBasedIndex column: #()).
			^ row
				addChild: (BlTextElement new
					text: ('not a column: ' , aColumn printString) asRopedText;
					margin: (BlInsets all: 4);
					yourself);
				yourself ].
	row addChild: (self labelElementFor: kind at: aZeroBasedIndex column: aColumn).
	shown := self maxPositions min: aColumn size.
	(aColumn first: shown) doWithIndex: [ :each :pos |
		row addChild: (self cellElementFor: each row: aZeroBasedIndex position: pos kind: kind) ].
	^ row
]

{ #category : 'rendering' }
ZkfolUairPicture >> truncated [
	"Whether the trace is wider than the render cap, so the display shows
	 only its first maxPositions and must say so."
	^ grid fullWidth > self maxPositions
]

{ #category : 'rendering' }
ZkfolUairPicture >> truncationMarkerElement [
	"How many of how many positions are shown. A render bound, not a
	 fetch one."
	^ self
		markerElement: 'showing first ' , self maxPositions printString
			, ' of ' , grid fullWidth printString , ' positions'
		id: #zkfolTruncationMarker
]
