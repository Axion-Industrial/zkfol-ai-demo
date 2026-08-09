Class {
	#name : 'ZkfolLayPicture',
	#superclass : 'Object',
	#instVars : [
		'witness',
		'regions',
		'arrows',
		'rowLabels',
		'aims',
		'cellElements',
		'hovered',
		'arrowLayer',
		'statusElement',
		'labelWidth',
		'inOrder'
	],
	#category : 'Zkfol-Views',
	#package : 'Zkfol',
	#tag : 'Views'
}

{ #category : 'instance creation' }
ZkfolLayPicture class >> onFeed: aDictionary [
	"The judgement feed carries me whole: the witness columns, the
	 allocation's regions, the row introductions, and one arrow per
	 consumption edge."
	^ self new setFromFeed: aDictionary
]

{ #category : 'rendering' }
ZkfolLayPicture >> arrowLineFor: anArrow [
	"One consumption edge as a line between the very cells: from the
	 pointer cell to the consumed column's own bank, the arrowhead on
	 what is read, the pointer row's color throughout, dashed when the
	 pointer did not weld."
	| from to color line |
	from := cellElements at: (anArrow at: #ptr) @ (anArrow at: #from) ifAbsent: [ ^ nil ].
	to := cellElements at: (anArrow at: #to_row) @ (anArrow at: #to) ifAbsent: [ ^ nil ].
	color := ZkfolPalette readColor: (self ptrIndexOf: anArrow).
	line := (ZkfolElements connectorFrom: from to: to color: (color alpha: 0.85))
		id: #zkfolLayArrowLine;
		toHead: (BlArrowheadSimpleArrow new background: color);
		yourself.
	(anArrow at: #weld) ifNil: [
		line border: (line border copyWithStyle: BlStrokeStyle dashed) ].
	^ line
]

{ #category : 'rendering' }
ZkfolLayPicture >> asElement [
	"The lay: how the allocation placed the derivation. Rows grouped by
	 what they serve, a member's bank beside its pointers, seams
	 between groups; an arrow layer the cells anchor, and a boxed
	 status line the hover talks through."
	| container previous |
	cellElements := Dictionary new.
	hovered := nil.
	container := ZkfolElements gridContainer: #zkfolLay.
	container addChild: self headerRowElement.
	previous := nil.
	self displayGroups do: [ :pair |
		(previous notNil and: [ pair value ~= previous ]) ifTrue: [
			container addChild: (BlElement new size: 1 @ 6; yourself) ].
		previous := pair value.
		container addChild: (self rowElementFor: pair key) ].
	arrowLayer := ZkfolElements overlay: #zkfolLayArrowLayer.
	container addChild: arrowLayer.
	statusElement := BlTextElement new
		id: #zkfolLayStatus;
		text: '' asRopedText;
		yourself.
	container addChild: (BlElement new
		id: #zkfolLayStatusBox;
		layout: BlLinearLayout horizontal;
		padding: (BlInsets top: 8 right: 0 bottom: 0 left: 4);
		clipChildren: true;
		constraintsDo: [ :c |
			c horizontal exact: self labelWidth + 2 + (witness size * 26).
			c vertical exact: 26 ];
		addChild: statusElement;
		yourself).
	self refreshHover.
	^ container
]

{ #category : 'accessing' }
ZkfolLayPicture >> colorOfRow: aRow [
	"The shared palette by what the row's region is: the pointer bank
	 wears the pointer orange, the tag the scheduled violet, the slack
	 a guard binds the quiet bit blue, a member's index row the index
	 tan, its value rows the quiet default."
	| region name |
	region := self regionOf: aRow.
	region ifNil: [ ^ ZkfolPalette kindColor: #plain ].
	name := (region at: #name) asString.
	name = 'ptr' ifTrue: [ ^ ZkfolPalette kindColor: #pointer ].
	name = 'tag' ifTrue: [ ^ ZkfolPalette kindColor: #scheduled ].
	name = 'slack' ifTrue: [ ^ ZkfolPalette kindColor: #bit ].
	aRow = (region at: #first) ifTrue: [ ^ ZkfolPalette kindColor: #index ].
	^ ZkfolPalette kindColor: #plain
]

{ #category : 'accessing' }
ZkfolLayPicture >> beInOrder [
	"Rows in plain allocated order, seams between regions: the reading
	 the judgement wants beneath its columns, where read-off beats
	 grouping."
	inOrder := true
]

{ #category : 'accessing' }
ZkfolLayPicture >> displayGroups [
	"The rows beside their groups. In order: allocated rows as they
	 are, grouped by region. Otherwise semantically: a member's bank
	 with the pointers its clauses entail, the caller's claim in any
	 lay, then the tag and whatever remains, in row order."
	| used groups |
	inOrder == true ifTrue: [
		^ (1 to: self rowCount) collect: [ :r |
			r -> ((self regionOf: r)
				ifNil: [ r printString ]
				ifNotNil: [ :region | (region at: #name) asString ]) ] ].
	used := Set new.
	groups := OrderedCollection new.
	regions do: [ :region |
		| name |
		name := (region at: #name) asString.
		(#('ptr' 'tag') includes: name) ifFalse: [
			(region at: #first) to: (region at: #last) do: [ :r |
				groups add: r -> name.
				used add: r ].
			aims do: [ :aim |
				((aim at: #member) asString = name
					and: [ (used includes: (aim at: #ptr)) not ]) ifTrue: [
						groups add: (aim at: #ptr) -> name.
						used add: (aim at: #ptr) ] ] ] ].
	1 to: self rowCount do: [ :r |
		(used includes: r) ifFalse: [ groups add: r -> r printString ] ].
	^ groups
]

{ #category : 'rendering' }
ZkfolLayPicture >> elementOrError [
	"The grid element, its reason when it cannot draw, never a raise."
	^ ZkfolElements safely: [ self asElement ] as: #zkfolLayError
]

{ #category : 'rendering' }
ZkfolLayPicture >> headerRowElement [
	"The position ruler over the grid: a spacer the width of the row
	 labels, then one muted position number per trace column."
	| row |
	row := ZkfolElements gridRow.
	row addChild: (BlElement new size: (self labelWidth + 2) @ 16; yourself).
	1 to: witness size do: [ :position |
		row addChild: (ZkfolElements headerBox: position) ].
	^ row
]

{ #category : 'hover' }
ZkfolLayPicture >> hovered: aCellOrNil [
	"Which cell the mouse is over, and the whole of what hover state
	 is: the arrow layer, every border, and the status line follow me,
	 so nothing has to remember what it drew in order to take it back."
	hovered := aCellOrNil.
	self refreshHover
]

{ #category : 'accessing' }
ZkfolLayPicture >> labelFor: aRow [
	"The row's introduction off the judgement feed, which already names
	 members by their head variables and pointers by their aim."
	^ rowLabels at: aRow ifAbsent: [ 'r' , aRow printString ]
]

{ #category : 'rendering' }
ZkfolLayPicture >> labelWidth [
	"The grid's one label width, off the row introductions; a composer
	 may hand both stacked grids one width so their columns align."
	^ labelWidth ifNil: [ ZkfolElements labelWidthFor: rowLabels ]
]

{ #category : 'rendering' }
ZkfolLayPicture >> labelWidth: aNumber [
	labelWidth := aNumber
]

{ #category : 'hover' }
ZkfolLayPicture >> litArrows [
	"The arrows the hovered cell itself relates, as the pointer grid
	 scopes its hover: a pointer cell lights its own read, a bank cell
	 lights its readers, any other cell lights nothing."
	hovered ifNil: [ ^ #() ].
	^ arrows select: [ :each |
		(((each at: #ptr) = hovered x) and: [ (each at: #from) = hovered y ])
			or: [ ((each at: #to_row) = hovered x)
				and: [ (each at: #to) = hovered y ] ] ]
]

{ #category : 'accessing' }
ZkfolLayPicture >> ptrIndexOf: anArrow [
	"Which pointer of the bank the edge went through, zero-based, so
	 the palette's read colors name each pointer row apart."
	| bank |
	bank := regions
		detect: [ :region | (region at: #name) asString = 'ptr' ]
		ifNone: [ ^ 0 ].
	^ (anArrow at: #ptr) - (bank at: #first)
]

{ #category : 'hover' }
ZkfolLayPicture >> refreshHover [
	"Nothing at rest; the hovered cell shows what it alone relates, the
	 endpoints wearing their pointer's color, the hovered cell the
	 quiet border, and the status line saying its place."
	| lit |
	arrowLayer ifNil: [ ^ self ].
	arrowLayer removeChildren.
	lit := self litArrows.
	lit do: [ :arrow |
		(self arrowLineFor: arrow) ifNotNil: [ :line |
			arrowLayer addChild: line ] ].
	statusElement ifNotNil: [
		statusElement text: (self statusText asRopedText
			fontSize: 10;
			foreground: ZkfolPalette mutedTextColor;
			yourself) ].
	cellElements ifNil: [ ^ self ].
	cellElements valuesDo: [ :cell | cell border: BlBorder empty ].
	hovered ifNil: [ ^ self ].
	lit do: [ :arrow |
		| color |
		color := ZkfolPalette readColor: (self ptrIndexOf: arrow).
		(cellElements at: (arrow at: #ptr) @ (arrow at: #from) ifAbsent: [ nil ])
			ifNotNil: [ :cell | cell border: (BlBorder paint: color width: 2) ].
		(cellElements at: (arrow at: #to_row) @ (arrow at: #to) ifAbsent: [ nil ])
			ifNotNil: [ :cell | cell border: (BlBorder paint: color width: 2) ] ].
	(cellElements at: hovered ifAbsent: [ nil ])
		ifNotNil: [ :cell | cell border: (BlBorder paint: ZkfolPalette hoverColor width: 1) ]
]

{ #category : 'accessing' }
ZkfolLayPicture >> regionOf: aRow [
	"The allocation's bank the absolute row lies in, or nil."
	^ regions
		detect: [ :region |
			((region at: #first) <= aRow) and: [ aRow <= (region at: #last) ] ]
		ifNone: [ nil ]
]

{ #category : 'accessing' }
ZkfolLayPicture >> rowCount [
	"How many committed rows the witness carries."
	^ witness isEmpty ifTrue: [ 0 ] ifFalse: [ witness first size ]
]

{ #category : 'rendering' }
ZkfolLayPicture >> rowElementFor: aRow [
	"One committed row: its introduction off the feed, then a colored
	 square per trace column, values quiet since the judgement owns
	 them, each cell remembered so the arrows anchor and the hover speaks."
	| row |
	row := ZkfolElements gridRow.
	row addChild: (ZkfolElements rowLabel: (self labelFor: aRow) width: self labelWidth).
	1 to: witness size do: [ :position |
		| cell |
		cell := ZkfolElements
			box: 24 @ 20
			color: (self colorOfRow: aRow)
			text: ((ZkfolElements compactValue: ((witness at: position) at: aRow) upTo: 5)
				asRopedText
					foreground: ZkfolPalette mutedTextColor;
					yourself)
			fontSize: 9.
		cell addEventHandlerOn: BlMouseEnterEvent do: [ :evt | self hovered: aRow @ position ].
		cell addEventHandlerOn: BlMouseLeaveEvent do: [ :evt | self hovered: nil ].
		cellElements at: aRow @ position put: cell.
		row addChild: cell ].
	^ row
]

{ #category : 'accessing' }
ZkfolLayPicture >> setFromFeed: aDictionary [
	witness := aDictionary at: #witness ifAbsent: [ #() ].
	regions := aDictionary at: #regions ifAbsent: [ #() ].
	arrows := aDictionary at: #arrows ifAbsent: [ #() ].
	rowLabels := aDictionary at: #rows ifAbsent: [ #() ].
	aims := aDictionary at: #aims ifAbsent: [ #() ]
]

{ #category : 'hover' }
ZkfolLayPicture >> statusText [
	"What the hovered cell is, said plainly: its bank and rows, its
	 column, and its read's weld when it is a pointer's."
	| region parts |
	hovered ifNil: [ ^ '' ].
	region := self regionOf: hovered x.
	parts := OrderedCollection new.
	region ifNotNil: [
		parts add: (region at: #name) asString , ' bank · rows '
			, (region at: #first) printString , '–' , (region at: #last) printString ].
	parts add: 'column ' , hovered y printString.
	self litArrows
		detect: [ :each |
			((each at: #ptr) = hovered x) and: [ (each at: #from) = hovered y ] ]
		ifFound: [ :arrow |
			parts add: 'reads column ' , (arrow at: #to) printString.
			parts add: ((arrow at: #weld)
				ifNil: [ 'dynamic' ]
				ifNotNil: [ :k | 'weld k=' , k printString ]) ]
		ifNone: [ ].
	^ ' · ' join: parts
]
