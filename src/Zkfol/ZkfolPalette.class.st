Class {
	#name : 'ZkfolPalette',
	#superclass : 'Object',
	#category : 'Zkfol-Views',
	#package : 'Zkfol',
	#tag : 'Views'
}

{ #category : 'palette' }
ZkfolPalette class >> failureColor [
	"The one colour a contradiction wears, in the grid and on the hover
	 connector alike, so a failure never reads as just another read."
	^ Color r: 0.8 g: 0.1 b: 0.1
]

{ #category : 'palette' }
ZkfolPalette class >> highlightColor [
	"The hover and emphasis orange, shared by the grid's highlight
	 border, the connector line, and the cells a walk names."
	^ Color fromHexString: 'D9822B'
]

{ #category : 'palette' }
ZkfolPalette class >> hoverColor [
	"The quiet border a hovered cell wears itself."
	^ Color fromHexString: '666666'
]

{ #category : 'palette' }
ZkfolPalette class >> kindColor: aKind [
	"The one palette every Zkfol view speaks: pointer bits blue,
	 dereference results green, looked-up pointers orange, scheduled
	 rows violet, the index column tan, the rest quiet. Grid cells,
	 chain chips, verdict chips, and miniature walks all ask me."
	aKind = #bit ifTrue: [ ^ Color fromHexString: 'AECBFA' ].
	aKind = #result ifTrue: [ ^ Color fromHexString: 'B7E1CD' ].
	aKind = #pointer ifTrue: [ ^ Color fromHexString: 'FDE1B0' ].
	aKind = #scheduled ifTrue: [ ^ Color fromHexString: 'DDD2F0' ].
	aKind = #index ifTrue: [ ^ Color fromHexString: 'EAE0CC' ].
	^ Color fromHexString: 'EDEDED'
]

{ #category : 'palette' }
ZkfolPalette class >> mutedTextColor [
	"The ruler's gray."
	^ Color fromHexString: '888888'
]

{ #category : 'palette' }
ZkfolPalette class >> nodeBackgroundColor [
	"The quiet fill of a pipeline node."
	^ Color fromHexString: 'FAFAFA'
]

{ #category : 'palette' }
ZkfolPalette class >> nodeBorderColor [
	"The quiet border a pipeline node wears at rest."
	^ Color fromHexString: 'DDDDDD'
]

{ #category : 'palette' }
ZkfolPalette class >> outlineColor [
	"The claimed rows' outline."
	^ Color fromHexString: '444444'
]

{ #category : 'palette' }
ZkfolPalette class >> readColor: aZeroBasedReadIndex [
	"Read k's own color, cycling gracefully past the palette's end."
	| colors |
	colors := self readColors.
	^ colors at: (aZeroBasedReadIndex \\ colors size) + 1
]

{ #category : 'palette' }
ZkfolPalette class >> readColors [
	"One color per composed read, so grid-hover and the deref chain
	 agree at a glance which read owns a target and its result. Read one
	 is the shared highlight orange; the rest are distinct hues. More
	 reads than colors cycle back, which only softens the distinction,
	 never breaks it."
	^ {
		self highlightColor.
		Color fromHexString: '3F7FBF'.
		Color fromHexString: '8E44AD'.
		Color fromHexString: '2E8B57' }
]
