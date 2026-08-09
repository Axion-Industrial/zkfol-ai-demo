Class {
	#name : 'ZkfolUairCell',
	#superclass : 'Object',
	#instVars : [
		'row',
		'kind',
		'position',
		'bits',
		'value'
	],
	#category : 'Zkfol-Grid',
	#package : 'Zkfol',
	#tag : 'Grid'
}

{ #category : 'instance creation' }
ZkfolUairCell class >> bitsOf: aOneBasedPosition over: aNumVars [
	"The hypercube point the position names, spelled in num_vars bits."
	^ ((aOneBasedPosition - 1) printStringBase: 2)
		padLeftTo: ((aNumVars ifNil: [ 1 ]) max: 1)
		with: $0
]

{ #category : 'instance creation' }
ZkfolUairCell class >> row: aRowIndex kind: aKind position: aPosition bits: aBitString value: aValue [
	^ self new
		setRow: aRowIndex
		kind: aKind
		position: aPosition
		bits: aBitString
		value: aValue
]

{ #category : 'comparing' }
ZkfolUairCell >> = anObject [
	"I am a value: two cells naming the same row, kind, position and
	 value are the same cell, however they were built."
	self == anObject ifTrue: [ ^ true ].
	self class = anObject class ifFalse: [ ^ false ].
	^ row = anObject row
		and: [ kind = anObject kind
		and: [ position = anObject position
		and: [ bits = anObject bits
		and: [ value = anObject value ] ] ] ]
]

{ #category : 'accessing' }
ZkfolUairCell >> bits [
	^ bits
]

{ #category : 'views' }
ZkfolUairCell >> gtFactsFor: aView [
	"One cell of the trace, spelled out."
	<gtView>
	^ aView columnedList
		title: 'Facts';
		priority: 5;
		items: [ {
			'row' -> row.
			'kind' -> kind.
			'position' -> position.
			'position bits' -> bits.
			'value' -> value } ];
		column: 'Fact' text: [ :each | each key ] width: 100;
		column: 'Value' text: [ :each | each value printString ]
]

{ #category : 'comparing' }
ZkfolUairCell >> hash [
	"Equal cells hash alike, so a cell can key a dictionary or sit in a set."
	^ row hash bitXor: (kind hash bitXor: (position hash bitXor: (bits hash bitXor: value hash)))
]

{ #category : 'accessing' }
ZkfolUairCell >> kind [
	^ kind
]

{ #category : 'accessing' }
ZkfolUairCell >> position [
	^ position
]

{ #category : 'printing' }
ZkfolUairCell >> printOn: aStream [
	aStream
		nextPutAll: 'row ';
		print: row.
	kind = #plain ifFalse: [ aStream nextPutAll: ' ' , kind ].
	aStream
		nextPutAll: ' at ';
		print: position;
		nextPutAll: ' (';
		nextPutAll: bits;
		nextPutAll: '): ';
		print: value
]

{ #category : 'accessing' }
ZkfolUairCell >> row [
	^ row
]

{ #category : 'accessing' }
ZkfolUairCell >> setRow: aRowIndex kind: aKind position: aPosition bits: aBitString value: aValue [
	row := aRowIndex.
	kind := aKind.
	position := aPosition.
	bits := aBitString.
	value := aValue
]

{ #category : 'accessing' }
ZkfolUairCell >> value [
	^ value
]
