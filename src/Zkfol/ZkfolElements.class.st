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
