Extension { #name : 'BeamProxyObject' }

{ #category : '*Zkfol' }
BeamProxyObject class >> plainFetch: anElixirSource through: anApplication [
	"The node's answer as plain Smalltalk, in one round trip: the
	 bridge fetches and decodes, then the struct tags go and the keys
	 become Symbols. A failed eval arrives as the node's own banner, a
	 dead session as a refusal too, so a view degrades to hidden."
	| fetched |
	fetched := [ self fetch: anElixirSource through: anApplication ]
		on: Error
		do: [ :anError | ^ ZkfolRefusal because: anError messageText asString ].
	(fetched isKindOf: BeamBridgeEvalError) ifTrue: [
		^ ZkfolRefusal because: fetched messageText ].
	^ self plainly: fetched
]

{ #category : '*Zkfol' }
BeamProxyObject class >> plainly: aValue [
	"Decoded wire data as the views read it: the struct tag goes, and
	 every map key becomes a Symbol. The symbolizing is a policy, not a
	 decode: the deserializer strips the atom marker, so an atom key
	 and a genuine String key arrive alike, and turning both into
	 Symbols is correct only because zkfol owns both ends of its feeds.
	 An atom value -- which alone among wire values answers #symbol --
	 becomes that Symbol, so tag matches like `= #define` hold. Asked
	 by the message it answers, not the bridge class it is, so nothing
	 here needs a bridge class in scope."
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

{ #category : '*Zkfol' }
BeamProxyObject >> evaluateOrNil: anElixirSource [
	"A remote call, guarded: nil rather than a raise when the session
	 is gone or the proxy is stale, so a view degrades to empty. My
	 callers splice my #resolve expression into their source the
	 bridge's way; I carry no template and no marker."
	(self application notNil and: [ self elixirVar notNil ])
		ifFalse: [ ^ nil ].
	^ [ self evaluateAndWait: anElixirSource ] on: Error do: [ :e | nil ]
]

{ #category : '*Zkfol' }
BeamProxyObject >> forward: aView title: aTitle priority: aNumber view: aViewSelector [
	"The proxy-side view pattern ALObject set and every Zkfol proxy
	 repeats: forward to the image-side model, built fresh per view."
	^ aView forward
		title: aTitle;
		priority: aNumber;
		object: [ self viewModel ];
		view: aViewSelector
]

{ #category : '*Zkfol' }
BeamProxyObject >> plainFetch: anElixirSource [
	"The class-side seam through my own session; stale, I refuse
	 rather than raise, so a view degrades to hidden."
	(self application notNil and: [ self elixirVar notNil ])
		ifFalse: [ ^ ZkfolRefusal because: 'the session is gone' ].
	^ self class plainFetch: anElixirSource through: self application
]
