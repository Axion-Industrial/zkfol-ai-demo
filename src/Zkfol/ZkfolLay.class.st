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
