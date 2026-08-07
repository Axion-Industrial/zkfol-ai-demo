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

{ #category : 'views' }
ZkfolRefusal >> gtDerivationGraphFor: aView [
	"A refusal has no derivation; the forwarded tab hides."
	<gtView>
	^ aView empty
]

{ #category : 'views' }
ZkfolRefusal >> gtJudgementFor: aView [
	"A refusal has no judgement; the forwarded tab hides."
	<gtView>
	^ aView empty
]

{ #category : 'views' }
ZkfolRefusal >> gtLayFor: aView [
	"A refusal has no lay; the forwarded tab hides."
	<gtView>
	^ aView empty
]

{ #category : 'views' }
ZkfolRefusal >> gtGridFor: aView [
	"A refusal has no grid; the forwarded tab hides."
	<gtView>
	^ aView empty
]

{ #category : 'accessing' }
ZkfolRefusal >> interestingObjects [
	"A refusal holds nothing to conjure."
	^ #()
]
