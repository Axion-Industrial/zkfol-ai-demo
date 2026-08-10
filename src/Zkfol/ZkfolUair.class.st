Class {
	#name : 'ZkfolUair',
	#superclass : 'BeamProxyObject',
	#category : 'Zkfol-Proxies',
	#package : 'Zkfol',
	#tag : 'Proxies'
}

{ #category : 'accessing' }
ZkfolUair class >> elixirClass [
	"The proxy factory dispatches me for the emitted statement struct."
	^ 'Zkfol.Uair'
]

{ #category : 'views' }
ZkfolUair >> gtFailuresFor: aView [
	"I show the grid's contradictions, built and rendered image-side
	 from one payload fetched over the bridge."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Failures' priority: 9 view: #gtFailuresFor:
]

{ #category : 'views' }
ZkfolUair >> gtPointerGridFor: aView [
	"I show the emitted statement as the Uair pointer grid, built and
	 rendered image-side from one payload fetched over the bridge."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Pointer grid' priority: 8 view: #gtPointerGridFor:
]

{ #category : 'accessing' }
ZkfolUair >> viewModel [
	"My grid, fetched once over the bridge and rendered image-side."
	^ ZkfolUairGrid onUair: self
]
