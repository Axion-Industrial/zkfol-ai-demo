Class {
	#name : 'ZkfolElements',
	#superclass : 'Object',
	#category : 'Zkfol-Views',
	#package : 'Zkfol',
	#tag : 'Views'
}

{ #category : 'building' }
ZkfolElements class >> box: anExtent color: aColorOrNil text: aTextOrNil fontSize: aNumber [
	"The one colored square everything in this package is drawn from:
	 grid cells, miniatures, ruler ticks, and header cells
	 are all me at some size, with centered small text when they have
	 something to say."
	| box layout |
	layout := BlLinearLayout horizontal.
	layout alignCenter.
	box := BlElement new
		size: anExtent;
		margin: (BlInsets all: 1);
		layout: layout;
		yourself.
	aColorOrNil ifNotNil: [ box background: aColorOrNil ].
	aTextOrNil ifNotNil: [
		box addChild: (BlTextElement new
			text: (aTextOrNil asRopedText fontSize: aNumber);
			yourself) ].
	^ box
]

{ #category : 'building' }
ZkfolElements class >> safely: aBlock as: anIdSymbol [
	"A stencil that raises during an async forward build trips phlow's
	 double entity assertion and ends in a debugger, never an error
	 view, so no Zkfol stencil may raise: it renders its reason instead."
	^ [ aBlock value ]
		on: Error
		do: [ :anError |
			BlTextElement new
				id: anIdSymbol;
				text: ('cannot render: ' , anError messageText asString) asRopedText;
				padding: (BlInsets all: 10);
				yourself ]
]

{ #category : 'building' }
ZkfolElements class >> swatch: aColorOrNil [
	"The small square legend chip every row tag, fact line, and delta
	 row wears: a kind's shared color, or transparent for none. Callers
	 add their own margin, since the chip sits differently in each."
	^ BlElement new
		size: 10 @ 10;
		background: (aColorOrNil ifNil: [ Color transparent ]);
		yourself
]

{ #category : 'building' }
ZkfolElements class >> compactValue: aNumber upTo: aCount [
	"A value that cannot say itself in aCount characters says its two
	 leading digits and its magnitude, honest and terse: 1.2e20 is a
	 21 digit number. The full value stays a hover or a click away,
	 wherever the caller keeps it."
	| s |
	s := aNumber printString.
	s size <= aCount ifTrue: [ ^ s ].
	aNumber isInteger ifFalse: [ ^ (s first: aCount - 1) , '…' ].
	^ s first asString , '.' , s second asString , 'e' , (s size - 1) printString
]

{ #category : 'building' }
ZkfolElements class >> connectorFrom: aSource to: aTarget color: aColor [
	"One connector, anchored to both cells so the layout places it;
	 callers restyle the border or add heads for their own dialect."
	^ BlLineElement new
		fromAnchor: (BlElementCenterAnchor element: aSource);
		toAnchor: (BlElementCenterAnchor element: aTarget);
		border: (BlBorder paint: aColor width: 2);
		constraintsDo: [ :c | c ignoreByLayout ];
		yourself
]

{ #category : 'building' }
ZkfolElements class >> gridContainer: anId [
	"The vertical container every grid picture stacks its ruler and
	 rows in: fit-content both ways, unclipped so overlay connectors
	 may leave the frame."
	^ BlElement new
		id: anId;
		layout: BlLinearLayout vertical;
		padding: (BlInsets all: 10);
		clipChildren: false;
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ];
		yourself
]

{ #category : 'building' }
ZkfolElements class >> gridRow [
	"One horizontal grid row, sized by what it holds."
	^ BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ];
		yourself
]

{ #category : 'building' }
ZkfolElements class >> headerBox: aPosition [
	"One muted position number of the ruler over a grid."
	^ self
		box: 24 @ 16
		color: nil
		text: (aPosition printString asRopedText
			foreground: ZkfolPalette mutedTextColor;
			yourself)
		fontSize: 9
]

{ #category : 'building' }
ZkfolElements class >> labelWidthFor: someStrings [
	"One bounded width for every row label, keeping the cells beside their names."
	^ 74 max: (280 min: 16 + ((someStrings inject: 0 into: [ :max :each | max max: each size ]) * 6))
]

{ #category : 'building' }
ZkfolElements class >> overlay: anId [
	"The layer connectors draw on: ignored by the grid's layout,
	 unclipped, added last so its lines ride over the cells."
	^ BlElement new
		id: anId;
		clipChildren: false;
		constraintsDo: [ :c | c ignoreByLayout ];
		yourself
]

{ #category : 'building' }
ZkfolElements class >> rowLabel: aString width: aNumber [
	"A row's introduction, elided to its width with the full name on hover."
	| layout |
	layout := BlLinearLayout horizontal.
	layout alignCenterLeft.
	^ BlElement new
		size: aNumber @ 20;
		margin: (BlInsets all: 1);
		padding: (BlInsets left: 4);
		layout: layout;
		addAptitude: (BrGlamorousWithLabelTooltipAptitude new text: aString);
		addChild: (BlShrinkingTextElement new
			constraintsDo: [ :c | c horizontal matchParent ];
			text: (aString asRopedText fontSize: 10);
			yourself);
		yourself
]
