Class {
	#name : 'ZkfolLay',
	#superclass : 'BeamProxyObject',
	#category : 'Zkfol-Proxies',
	#package : 'Zkfol',
	#tag : 'Proxies'
}

{ #category : 'accessing' }
ZkfolLay class >> elixirClass [
	"The proxy factory dispatches me for the lay struct."
	^ 'Zkfol.Lay'
]

{ #category : 'views' }
ZkfolLay >> gtDerivationGraphFor: aView [
	"The derivation I placed, as its graph."
	<gtView>
	<gtBeamView>
	| feed |
	feed := self plainFetch: 'Zkfol.Face.derivation(' , self resolve , '.derivation)'.
	((feed isKindOf: Dictionary)
		and: [ (feed at: #rows ifAbsent: [ #() ]) notEmpty ])
			ifFalse: [ ^ aView empty ].
	^ aView mondrian
		title: 'Derivation';
		priority: 11;
		painting: [ :aMondrian | (ZkfolDerivationGraph onFeed: feed) paint: aMondrian ]
]

{ #category : 'views' }
ZkfolLay >> gtGridFor: aView [
	"Myself as the grid: banks behind seams, pointers grouped with the
	 caller entailing them, hover speaking each cell's place. I am the
	 value the picture draws; nothing here is conjured past me."
	<gtView>
	<gtBeamView>
	| feed |
	feed := self plainFetch: 'Zkfol.Face.lay(' , self resolve , ')'.
	((feed isKindOf: Dictionary)
		and: [ (feed at: #witness ifAbsent: [ #() ]) notEmpty ])
			ifFalse: [ ^ aView empty ].
	^ ZkfolElements
		canvasOn: aView title: 'Grid' priority: 5
		node: (ZkfolLayPicture onFeed: feed)
]

{ #category : 'views' }
ZkfolLay >> gtJoinFor: aView [
	"The join I am, for reading the implementation: the derivation's
	 facts and the alloc's sites meeting in my stands. A click opens
	 the datum a box stands for."
	<gtView>
	<gtBeamView>
	| feed |
	feed := self plainFetch: 'Zkfol.Face.stands(' , self resolve , ')'.
	((feed isKindOf: Dictionary)
		and: [ (feed at: #stands ifAbsent: [ #() ]) notEmpty ])
			ifFalse: [ ^ aView empty ].
	^ aView mondrian
		title: 'Join';
		priority: 40;
		painting: [ :aMondrian |
			((ZkfolLayJoin onFeed: feed)
				spawner: [ :expression |
					self evaluateOrNil: '(fn lay -> ' , expression , ' end).(' , self resolve , ')' ];
				yourself) paint: aMondrian ]
]
