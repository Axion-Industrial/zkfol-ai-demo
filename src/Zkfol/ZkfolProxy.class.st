Class {
	#name : 'ZkfolProxy',
	#superclass : 'BeamProxyObject',
	#category : 'Zkfol-Proxies',
	#package : 'Zkfol',
	#tag : 'Proxies'
}

{ #category : 'accessing' }
ZkfolProxy class >> elixirClass [
	"I am abstract: no exclass dispatches to me, my subclasses name
	 theirs. The factory maps every subclass, so I answer inertly
	 rather than raising."
	^ nil
]

{ #category : 'boundary' }
ZkfolProxy class >> on: aProxy fetch: anElixirSource [
	"The answer as ordinary Smalltalk, in one round trip. A refusal
	 rather than nil when the node cannot answer, so a view can say why."
	| json |
	json := self on: aProxy evaluateOrNil: anElixirSource , ' |> GtBridge.Serializer.to_json() |> elem(1)'.
	json isString ifFalse: [ ^ ZkfolRefusal because: 'the node did not answer' ].
	^ [ self plainly: (BeamLinkDeserializer new decodeWire: (STONJSON fromString: json)) ]
		on: Error
		do: [ :anError | ZkfolRefusal because: anError messageText asString ]
]

{ #category : 'boundary' }
ZkfolProxy class >> plainly: aValue [
	"Decoded wire data as the grid reads it: an atom key arrives
	 unprefixed but still a String, the struct tag goes, and an atom
	 value -- which alone among wire values answers #symbol -- becomes
	 that Symbol, so tag matches like `= #define` hold. Asked by the
	 message it answers, not the bridge class it is, so nothing here needs
	 a bridge class in scope."
	(aValue isKindOf: Dictionary) ifTrue: [
		^ Dictionary new in: [ :out |
			aValue keysAndValuesDo: [ :key :each |
				key asSymbol = #__struct__ ifFalse: [
					out at: key asSymbol put: (self plainly: each) ] ].
			out ] ].
	(aValue respondsTo: #symbol) ifTrue: [ ^ aValue symbol ].
	(aValue isString or: [ aValue isSymbol ]) ifTrue: [ ^ aValue ].
	aValue isCollection ifTrue: [ ^ aValue collect: [ :each | self plainly: each ] ].
	^ aValue
]

{ #category : 'calling' }
ZkfolProxy class >> on: aBeamProxy evaluateOrNil: anElixirSource [
	"A remote call, guarded: nil rather than a raise when the session is
	 gone or the proxy is stale, so a view degrades to empty."
	(aBeamProxy application notNil and: [ aBeamProxy elixirVar notNil ])
		ifFalse: [ ^ nil ].
	^ [ aBeamProxy evaluateAndWait: anElixirSource ] on: Error do: [ :e | nil ]
]

{ #category : 'calling' }
ZkfolProxy >> evaluateOrNil: anElixirSource [
	"Send an already-built Elixir source through the guarded seam,
	 referencing myself. My callers splice my #resolve expression into
	 their source the bridge's way; I carry no template and no marker."
	^ self class on: self evaluateOrNil: anElixirSource
]

{ #category : 'views' }
ZkfolProxy >> forward: aView title: aTitle priority: aNumber view: aViewSelector [
	"The proxy-side view pattern ALObject set and every Zkfol proxy
	 repeats: forward to the image-side model, built fresh per view."
	^ aView forward
		title: aTitle;
		priority: aNumber;
		object: [ self viewModel ];
		view: aViewSelector
]

{ #category : 'views' }
ZkfolProxy >> viewModel [
	"The image-side model my forward views hand their tabs."
	^ self subclassResponsibility
]
