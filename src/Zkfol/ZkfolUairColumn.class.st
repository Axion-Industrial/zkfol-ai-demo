Class {
	#name : 'ZkfolUairColumn',
	#superclass : 'Object',
	#instVars : [
		'position',
		'bits',
		'cells',
		'derefs'
	],
	#category : 'Zkfol-Grid',
	#package : 'Zkfol',
	#tag : 'Grid'
}

{ #category : 'instance creation' }
ZkfolUairColumn class >> position: aPosition bits: aBitString cells: aCellCollection derefs: aDerefCollection [
	^ self new
		setPosition: aPosition
		bits: aBitString
		cells: aCellCollection
		derefs: aDerefCollection
]

{ #category : 'accessing' }
ZkfolUairColumn >> derefs [
	^ derefs
]

{ #category : 'views' }
ZkfolUairColumn >> gtDerefsFor: aView [
	<gtView>
	derefs isEmpty ifTrue: [ ^ aView empty ].
	^ ZkfolElements
		canvasOn: aView title: 'Deref chain' priority: 5
		node: (derefs first grid picture
			emphasis: (derefs flatCollect: [ :each | each coords ]);
			connectors: (derefs flatCollect: [ :each | each threads ]);
			yourself)
]

{ #category : 'views' }
ZkfolUairColumn >> gtCellsFor: aView [
	"Every row's cell at this position, with its derived kind."
	<gtView>
	^ aView columnedList
		title: 'Cells';
		priority: 6;
		items: [ cells ];
		column: 'Row' text: [ :each | each row printString ] width: 60;
		column: 'Kind' text: [ :each | each kind ] width: 80;
		column: 'Address bit' text: [ :each | self addressBitLabelFor: each ] width: 110;
		column: 'Value' text: [ :each | each value printString ]
]

{ #category : 'accessing' }
ZkfolUairColumn >> addressBitLabelFor: aCell [
	"Which bit of which read a row spells here, and what the bits add up
	 to. The position's own hypercube point is a different number that
	 happens to be spelled in bits too, so the two are never both just
	 'bits' in the same view."
	^ String streamContents: [ :out |
		derefs do: [ :chain |
			| at |
			at := chain bitRowIndices indexOf: aCell row.
			at = 0 ifFalse: [
				out
					nextPutAll: 'b';
					print: at - 1;
					nextPutAll: ' of A=';
					print: chain address ] ] ]
]

{ #category : 'accessing' }
ZkfolUairColumn >> position [
	^ position
]

{ #category : 'printing' }
ZkfolUairColumn >> printOn: aStream [
	aStream
		nextPutAll: 'position ';
		print: position;
		nextPutAll: ' (point ';
		nextPutAll: bits;
		nextPutAll: '), ';
		print: cells size;
		nextPutAll: ' rows'.
	derefs isEmpty ifFalse: [
		aStream
			nextPutAll: ', ';
			print: derefs size;
			nextPutAll: ' reads' ]
]

{ #category : 'accessing' }
ZkfolUairColumn >> setPosition: aPosition bits: aBitString cells: aCellCollection derefs: aDerefCollection [
	position := aPosition.
	bits := aBitString.
	cells := aCellCollection.
	derefs := aDerefCollection
]
