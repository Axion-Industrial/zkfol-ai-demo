Class {
	#name : 'ZkfolPipelineStage',
	#superclass : 'Object',
	#instVars : [
		'index',
		'name',
		'verdict'
	],
	#category : 'Zkfol-Values',
	#package : 'Zkfol',
	#tag : 'Values'
}

{ #category : 'instance creation' }
ZkfolPipelineStage class >> index: aNumber name: aString verdict: aSymbol [
	^ self new setIndex: aNumber name: aString verdict: aSymbol
]

{ #category : 'instance creation' }
ZkfolPipelineStage class >> index: anInteger pair: aTuple [
	"An error verdict is a tuple; every other verdict is its atom."
	| verdict |
	verdict := aTuple itemAt: 1.
	^ self
		index: anInteger
		name: ((aTuple itemAt: 0) symbol asString substrings: '.') last
		verdict: ((verdict isKindOf: BeamTupleObject)
			ifTrue: [ #errors ]
			ifFalse: [ verdict symbol ])
]

{ #category : 'accessing' }
ZkfolPipelineStage >> index [
	^ index
]

{ #category : 'accessing' }
ZkfolPipelineStage >> label [
	"My name and verdict for the pipeline node."
	^ name , ' · ' , self verdictLabel
]

{ #category : 'accessing' }
ZkfolPipelineStage >> name [
	^ name
]

{ #category : 'printing' }
ZkfolPipelineStage >> printOn: aStream [
	aStream
		nextPutAll: 'stage ';
		print: index;
		nextPutAll: ' ';
		nextPutAll: name;
		nextPutAll: ' ';
		nextPutAll: self verdictLabel
]

{ #category : 'accessing' }
ZkfolPipelineStage >> setIndex: aNumber name: aString verdict: aSymbol [
	index := aNumber.
	name := aString.
	verdict := aSymbol
]

{ #category : 'accessing' }
ZkfolPipelineStage >> verdict [
	^ verdict
]

{ #category : 'accessing' }
ZkfolPipelineStage >> verdictColor [
	"My verdict's color from the one shared palette family: acted kinds
	 wear their kind's color, declines stay quiet."
	verdict = #lowers ifTrue: [ ^ ZkfolPalette kindColor: #bit ].
	(verdict = #rewrites or: [ verdict = #solves ])
		ifTrue: [ ^ ZkfolPalette kindColor: #result ].
	verdict = #expands ifTrue: [ ^ ZkfolPalette kindColor: #pointer ].
	verdict = #errors ifTrue: [ ^ ZkfolPalette failureColor ].
	^ ZkfolPalette kindColor: #plain
]

{ #category : 'accessing' }
ZkfolPipelineStage >> verdictLabel [
	"My verdict as text."
	^ verdict asString
]
