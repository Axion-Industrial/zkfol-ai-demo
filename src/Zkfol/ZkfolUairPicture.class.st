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
		'decorated',
		'budget',
		'rulerAtBottom'
	],
	#category : 'Zkfol-Grid',
	#package : 'Zkfol',
	#tag : 'Grid'
}

{ #category : 'instance creation' }
ZkfolUairPicture class >> on: aGrid [
	^ self new setGrid: aGrid; yourself
]

{ #category : 'rendering' }
ZkfolUairPicture >> asElement [
	"The whole trace at a glance: a binary position ruler over the cube,
	 then one row per committed column, colored by what the emitter
	 derived it for, claimed rows outlined, the padding past the real
	 trace faded, cells pointing where they point. A cube past the render
	 cap shows its head, the real/padding seam, and its tail, and says so.
	 The ruler rides under the rows instead when I am asked to."
	| container |
	cellElements := Dictionary new.
	hovered := nil.
	decorated := nil.
	container := ZkfolElements gridContainer: #zkfolUairGrid.
	self truncated ifTrue: [ container addChild: self truncationMarkerElement ].
	self rulerAtBottom ifFalse: [ container addChild: self headerRowElement ].
	grid displayColumns doWithIndex: [ :each :oneBased |
		container addChild: (self rowElementFor: each at: oneBased - 1) ].
	self rulerAtBottom ifTrue: [ container addChild: self headerRowElement ].
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

{ #category : 'accessing' }
ZkfolUairPicture >> budget: aNumber [
	"How many positions this rendering draws before it truncates to head,
	 the real/padding seam, and tail. The cost picture sets a tight one;
	 the grid keeps the render cap."
	budget := aNumber
]

{ #category : 'rendering' }
ZkfolUairPicture >> cellElementFor: aValue row: aRowIndex position: aPosition kind: aKind [
	"One colored square. Clicking it spawns the spelled-out cell in the
	 next pane; hovering sets which cell is hovered and every highlight
	 and connector follows from that. A position past the real trace is
	 base-case padding the cube is filled to, so it fades. A value too
	 big for the cell compacts to its magnitude and tooltips its full self."
	| cell text color |
	text := ZkfolElements compactValue: aValue upTo: 5.
	color := aPosition > grid len
		ifTrue: [ (ZkfolPalette kindColor: aKind) alpha: 0.3 ]
		ifFalse: [ ZkfolPalette kindColor: aKind ].
	cell := (ZkfolElements
		box: 24 @ 20
		color: color
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

{ #category : 'rendering' }
ZkfolUairPicture >> ellipsisTile: anExtent [
	"The gap between two kept runs: a muted ellipsis the width of a
	 cell, so the ruler and every row stay in step across the skip."
	^ ZkfolElements
		box: anExtent
		color: nil
		text: ('...' asRopedText foreground: ZkfolPalette mutedTextColor; yourself)
		fontSize: 9
]

{ #category : 'accessing' }
ZkfolUairPicture >> emphasis: aCollectionOfCoords [
	"The cells this rendering is about. Everything else fades."
	emphasis := aCollectionOfCoords asSet
]

{ #category : 'rendering' }
ZkfolUairPicture >> headerElementFor: aPosition [
	"One position header: the cube coordinate in the current label mode,
	 the other mode one hover away, clickable, spawning the whole column
	 at that position, deref chain included."
	| header |
	header := (ZkfolElements
		box: 24 @ 16
		color: nil
		text: ((self positionLabel: aPosition) asRopedText
			foreground: ZkfolPalette mutedTextColor;
			yourself)
		fontSize: 9)
		id: #zkfolUairHeader;
		yourself.
	header addAptitude: (BrGlamorousWithTooltipAptitude content: [
		BlTextElement new text: (self positionTooltip: aPosition) asRopedText; padding: (BlInsets all: 4); yourself ]).
	header addAptitude: (BrStyleCommonAptitude new
		default: [ :w | w border: BlBorder empty ];
		hovered: [ :w | w border: (BlBorder paint: ZkfolPalette hoverColor width: 1) ];
		yourself).
	^ ZkfolElements make: header spawn: [ grid columnAt: aPosition ]
]

{ #category : 'rendering' }
ZkfolUairPicture >> headerRowElement [
	"The position ruler over the grid: a spacer the width of the row
	 labels, then one clickable header per shown position, an ellipsis
	 where a run is skipped."
	| row |
	row := ZkfolElements gridRow.
	row addChild: (BlElement new size: (grid labelWidth + 2) @ 16; yourself).
	self shownPositions do: [ :pos |
		pos = #ellipsis
			ifTrue: [ row addChild: (self ellipsisTile: 24 @ 16) ]
			ifFalse: [ row addChild: (self headerElementFor: pos) ] ].
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
		width: grid labelWidth)
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
	 realistic trace in full and scrolls; a larger cube shows its head,
	 the real/padding seam, and its tail with an honest marker rather
	 than a silent cut."
	^ 512
]

{ #category : 'rendering' }
ZkfolUairPicture >> positionLabel: aPosition [
	"The position in the grid's current mode: the binary cube coordinate,
	 or its decimal index."
	^ grid labelMode = #binary
		ifTrue: [ ZkfolUairCell bitsOf: aPosition over: grid numVars ]
		ifFalse: [ (aPosition - 1) printString ]
]

{ #category : 'rendering' }
ZkfolUairPicture >> positionTooltip: aPosition [
	"The other mode, for the hover: decimal when the ruler shows binary,
	 binary when it shows decimal."
	^ grid labelMode = #binary
		ifTrue: [ (aPosition - 1) printString ]
		ifFalse: [ ZkfolUairCell bitsOf: aPosition over: grid numVars ]
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
	 per shown trace position, an ellipsis where a run is skipped, every
	 cell spawning what it names. The first numPublic rows are the claimed
	 ones the verifier reads in the clear, so they wear an outline. A
	 malformed column renders as its own message; the grid never raises
	 mid-render."
	| row kind |
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
	self shownPositions do: [ :pos |
		pos = #ellipsis
			ifTrue: [ row addChild: (self ellipsisTile: 24 @ 20) ]
			ifFalse: [ row addChild: (self
				cellElementFor: (aColumn at: pos ifAbsent: [ 0 ])
				row: aZeroBasedIndex
				position: pos
				kind: kind) ] ].
	^ row
]

{ #category : 'accessing' }
ZkfolUairPicture >> rulerAtBottom [
	"Whether the position ruler is drawn under the rows rather than over
	 them. The grid keeps it on top; the cost picture flips it so the
	 numbering answers the annotations above."
	^ rulerAtBottom == true
]

{ #category : 'accessing' }
ZkfolUairPicture >> rulerAtBottom: aBoolean [
	"Draw the position ruler under the rows instead of over them."
	rulerAtBottom := aBoolean
]

{ #category : 'initialization' }
ZkfolUairPicture >> setGrid: aGrid [
	grid := aGrid
]

{ #category : 'rendering' }
ZkfolUairPicture >> shownPositions [
	"The positions this rendering draws: the grid's truncation at my
	 budget, head and the real/padding seam and tail, #ellipsis marking
	 each elided run. The budget defaults to the render cap."
	^ grid shownPositionsUpTo: (budget ifNil: [ self maxPositions ])
]

{ #category : 'rendering' }
ZkfolUairPicture >> truncated [
	"Whether the trace is wider than the render cap, so the display shows
	 only its first maxPositions and must say so."
	^ grid fullWidth > self maxPositions
]

{ #category : 'rendering' }
ZkfolUairPicture >> truncationMarkerElement [
	"How many of how many positions are shown, and that the shown ones
	 are the head, the real/padding seam, and the tail rather than a
	 flat prefix. A render bound, not a fetch one."
	| shown |
	shown := (self shownPositions reject: [ :p | p = #ellipsis ]) size.
	^ self
		markerElement: 'showing ' , shown printString , ' of '
			, grid fullWidth printString , ' positions: head, the real/padding seam, and tail'
		id: #zkfolTruncationMarker
]
