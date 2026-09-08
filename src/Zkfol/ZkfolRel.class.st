Class {
	#name : 'ZkfolRel',
	#superclass : 'BeamProxyObject',
	#category : 'Zkfol-Proxies',
	#package : 'Zkfol',
	#tag : 'Proxies'
}

{ #category : 'accessing' }
ZkfolRel class >> elixirClass [
	"The proxy factory dispatches me for the surface relation."
	^ 'Zkfol.Lang.Rel'
]

{ #category : 'views' }
ZkfolRel >> gtClausesFor: aView [
	"The clauses as the surface writes them, and evaluation one click
	 away: play opens the free query on this relation."
	<gtView>
	<gtBeamView>
	| feed |
	feed := self plainFetch: 'Zkfol.Face.rel(' , self resolve , ')'.
	((feed isKindOf: Dictionary) and: [ (feed at: #clauses ifAbsent: [ #() ]) notEmpty ])
		ifFalse: [ ^ aView empty ].
	^ aView columnedList
		title: 'Clauses';
		priority: 1;
		items: [ feed at: #clauses ];
		column: '#' text: [ :each :i | i printString ] width: 30;
		column: 'Clause' text: [ :each | each ];
		actionButtonIcon: BrGlamorousVectorIcons play
			tooltip: 'Eval free'
			action: [ :aButton :aTab |
				aButton phlow spawnObject: (self evaluateOrNil:
					'Zkfol.eval!(' , self resolve , ', List.duplicate(:_, '
						, (feed at: #arity) printString , '))') ]
]

{ #category : 'views' }
ZkfolRel >> gtShapeFor: aView [
	"The compiled shape summarized: members, pointers, widths, and the
	 branch count; a shape that refuses reads as its reason."
	<gtView>
	<gtBeamView>
	| shape |
	shape := self plainFetch: 'Zkfol.Face.shape(' , self resolve , ')'.
	(shape isKindOf: Dictionary) ifFalse: [ ^ aView empty ].
	^ aView columnedList
		title: 'Shape';
		priority: 2;
		items: [ shape associations ];
		column: 'What' text: [ :each | each key ];
		column: 'Value' text: [ :each | each value printString ]
]
