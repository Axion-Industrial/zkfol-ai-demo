Class {
	#name : 'ZkfolRefusal',
	#superclass : 'Object',
	#instVars : [
		'reason'
	],
	#category : 'Zkfol-Values',
	#package : 'Zkfol',
	#tag : 'Values'
}

{ #category : 'instance creation' }
ZkfolRefusal class >> because: aString [
	"A refusal carrying why."
	^ self new setReason: aString
]

{ #category : 'printing' }
ZkfolRefusal >> printOn: aStream [
	aStream nextPutAll: 'refused: '; nextPutAll: reason asString
]

{ #category : 'accessing' }
ZkfolRefusal >> reason [
	^ reason
]

{ #category : 'accessing' }
ZkfolRefusal >> setReason: aString [
	reason := aString
]
