Class {
	#name : 'ZkfolUairRow',
	#superclass : 'Object',
	#instVars : [
		'index',
		'kind',
		'claimed',
		'values',
		'numVars'
	],
	#category : 'Zkfol-Grid',
	#package : 'Zkfol',
	#tag : 'Grid'
}

{ #category : 'instance creation' }
ZkfolUairRow class >> index: aRowIndex kind: aKind claimed: aBoolean values: aCollection numVars: aNumber [
	^ self new
		setIndex: aRowIndex
		kind: aKind
		claimed: aBoolean
		values: aCollection
		numVars: aNumber
]

{ #category : 'accessing' }
ZkfolUairRow >> claimed [
	^ claimed
]

{ #category : 'views' }
ZkfolUairRow >> gtValuesFor: aView [
	"The whole committed column, position by position, each row a cell."
	<gtView>
	^ aView columnedList
		title: 'Values';
		priority: 5;
		items: [ values asOrderedCollection withIndexCollect: [ :each :pos |
			ZkfolUairCell
				row: index
				kind: kind
				position: pos
				bits: (ZkfolUairCell bitsOf: pos over: numVars)
				value: each ] ];
		column: 'Position' text: [ :each | each position printString ] width: 70;
		column: 'Bits' text: [ :each | each bits ] width: 70;
		column: 'Value' text: [ :each | each value printString ]
]

{ #category : 'printing' }
ZkfolUairRow >> printOn: aStream [
	aStream
		nextPutAll: 'row ';
		print: index.
	kind = #plain ifFalse: [ aStream nextPutAll: ' ' , kind ].
	claimed ifTrue: [ aStream nextPutAll: ' claimed' ].
	aStream
		nextPutAll: ', ';
		print: values size;
		nextPutAll: ' values'
]

{ #category : 'accessing' }
ZkfolUairRow >> setIndex: aRowIndex kind: aKind claimed: aBoolean values: aCollection numVars: aNumber [
	index := aRowIndex.
	kind := aKind.
	claimed := aBoolean.
	values := aCollection.
	numVars := aNumber
]
