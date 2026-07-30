Class {
	#name : 'ZkfolPipelineStage',
	#superclass : 'Object',
	#instVars : [
		'index',
		'name',
		'verdict',
		'extra'
	],
	#category : 'Zkfol-Values',
	#package : 'Zkfol',
	#tag : 'Values'
}

{ #category : 'instance creation' }
ZkfolPipelineStage class >> index: aNumber name: aString verdict: aSymbol extra: anObject [
	^ self new setIndex: aNumber name: aString verdict: aSymbol extra: anObject
]

{ #category : 'accessing' }
ZkfolPipelineStage >> index [
	^ index
]

{ #category : 'accessing' }
ZkfolPipelineStage >> label [
	"My name for the pipeline node, with the small delta a compound
	 verdict carries appended, already rendered by the face."
	^ extra ifNil: [ name ] ifNotNil: [ name , ' · ' , extra asString ]
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
ZkfolPipelineStage >> setIndex: aNumber name: aString verdict: aSymbol extra: anObject [
	index := aNumber.
	name := aString.
	verdict := aSymbol.
	extra := anObject
]

{ #category : 'accessing' }
ZkfolPipelineStage >> verdict [
	^ verdict
]

{ #category : 'accessing' }
ZkfolPipelineStage >> verdictColor [
	"My verdict's color from the one shared palette family: acted kinds
	 wear their kind's color, declines stay quiet, refusals warn."
	verdict = #lowers ifTrue: [ ^ ZkfolPalette kindColor: #bit ].
	(verdict = #rewrites or: [ verdict = #solves ])
		ifTrue: [ ^ ZkfolPalette kindColor: #result ].
	verdict = #expands ifTrue: [ ^ ZkfolPalette kindColor: #pointer ].
	verdict = #refuses ifTrue: [ ^ ZkfolPalette highlightColor ].
	verdict = #errors ifTrue: [ ^ ZkfolPalette failureColor ].
	^ ZkfolPalette kindColor: #plain
]

{ #category : 'accessing' }
ZkfolPipelineStage >> verdictLabel [
	"My verdict as text, a placeholder when a malformed piped entry
	 left it nil, so the chip and the prints never break on it."
	^ verdict ifNil: [ '?' ] ifNotNil: [ :v | v asString ]
]
