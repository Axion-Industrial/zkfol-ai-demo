Class {
	#name : 'ZkfolUair',
	#superclass : 'BeamProxyObject',
	#instVars : [
		'viewModel'
	],
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
ZkfolUair >> gtCommitmentFor: aView [
	"What the commitment does to a committed column, built and rendered
	 image-side from the grid and the code's own parameters."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Commitment' priority: 8 view: #gtCommitmentFor:
]

{ #category : 'views' }
ZkfolUair >> gtCostFor: aView [
	"The emitted statement's proof cost, built and rendered image-side
	 from the grid I already fetched. First of my views: it is the whole
	 grid with the cost read off it, and it pans to fit."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Cost' priority: 7 view: #gtCostFor:
]

{ #category : 'views' }
ZkfolUair >> gtFailuresFor: aView [
	"I show the grid's contradictions, built and rendered image-side
	 from one payload fetched over the bridge."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Failures' priority: 12 view: #gtFailuresFor:
]

{ #category : 'views' }
ZkfolUair >> gtPointerGridFor: aView [
	"I show the emitted statement as the Uair pointer grid, built and
	 rendered image-side from one payload fetched over the bridge."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Pointer grid' priority: 11 view: #gtPointerGridFor:
]

{ #category : 'views' }
ZkfolUair >> gtTotalsFor: aView [
	"Every cost in one table, the fold and the commitment together."
	<gtView>
	<gtBeamView>
	^ self forward: aView title: 'Totals' priority: 10 view: #gtTotalsFor:
]

{ #category : 'accessing' }
ZkfolUair >> viewModel [
	"My grid, fetched once over the bridge and rendered image-side. Cached
	 so the label-mode toggle survives the view's own refresh: a fresh
	 grid each render would reset it."
	^ viewModel ifNil: [ viewModel := ZkfolUairGrid onUair: self ]
]
