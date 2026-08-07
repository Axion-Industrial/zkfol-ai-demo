Class {
	#name : 'ZkfolDerivation',
	#superclass : 'ZkfolProxy',
	#category : 'Zkfol-Proxies',
	#package : 'Zkfol',
	#tag : 'Proxies'
}

{ #category : 'accessing' }
ZkfolDerivation class >> elixirClass [
	"The proxy factory dispatches me for the derivation struct."
	^ 'Zkfol.Derivation'
]

{ #category : 'views' }
ZkfolDerivation >> gtGraphFor: aView [
	"Myself as the fact DAG: one node per established fact, one arc per
	 consumption in its read's color, shared subderivations shared by
	 fan-in. A node's click answers its own row; the statement's tab
	 adds the sub-statement click, which needs relations I do not hold."
	<gtView>
	<gtBeamView>
	| feed |
	feed := ZkfolProxy on: self fetch: 'Zkfol.Face.derivation(' , self resolve , ')'.
	((feed isKindOf: Dictionary)
		and: [ (feed at: #rows ifAbsent: [ #() ]) notEmpty ])
			ifFalse: [ ^ aView empty ].
	^ aView mondrian
		title: 'Graph';
		priority: 5;
		painting: [ :aMondrian |
			(ZkfolDerivationGraph onFeed: feed) paint: aMondrian ]
]
