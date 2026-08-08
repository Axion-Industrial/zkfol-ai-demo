Class {
	#name : 'ZkfolStatement',
	#superclass : 'BeamProxyObject',
	#category : 'Zkfol-Proxies',
	#package : 'Zkfol',
	#tag : 'Proxies'
}

{ #category : 'accessing' }
ZkfolStatement class >> elixirClass [
	"The proxy factory dispatches me for the statement struct."
	^ 'Zkfol.Statement'
]

{ #category : 'accessing' }
ZkfolStatement >> alloc [
	"My stage's allocation as the bridged struct, wearing its own
	 regions view; nil while nothing is solved. The node owns the
	 unwrap."
	^ self evaluateOrNil: 'Zkfol.Statement.alloc(' , self resolve , ')'
]

{ #category : 'views' }
ZkfolStatement >> gtLayFor: aView [
	"The lay owns its grid; I only forward to the value."
	<gtView>
	<gtBeamView>
	^ aView forward
		title: 'Lay';
		priority: 10;
		object: [ self lay ];
		view: #gtGridFor:
]

{ #category : 'accessing' }
ZkfolStatement >> derivation [
	"My stage's derivation as the bridged struct; nil while nothing is
	 solved."
	^ self evaluateOrNil: 'Zkfol.Statement.derivation(' , self resolve , ')'
]

{ #category : 'accessing' }
ZkfolStatement >> lay [
	"My stage's lay as the bridged struct, wearing its own views; a
	 refusal while nothing is solved, so a forward degrades to hidden."
	| lay |
	lay := self evaluateOrNil: 'Zkfol.Statement.lay(' , self resolve , ')'.
	^ (lay isKindOf: ZkfolLay)
		ifTrue: [ lay ]
		ifFalse: [ ZkfolRefusal because: 'no lay: nothing is solved' ]
]

{ #category : 'accessing' }
ZkfolStatement >> underAt: aOneBasedIndex [
	"The statement beneath the derivation's k-th fact: its
	 subderivation re-laid through my allocation, the bridged struct
	 wearing every view; nil when there is no such fact."
	^ self evaluateOrNil:
		'Zkfol.Face.under(' , self resolve , ', ' , aOneBasedIndex printString , ')'
]

{ #category : 'views' }
ZkfolStatement >> gtObjectsFor: aView [
	"My interesting objects, one send each: a launcher, not a view."
	<gtView>
	<gtBeamView>
	^ aView columnedList
		title: 'Objects';
		priority: 12;
		items: [ self interestingObjects ];
		column: 'Object' text: [ :each | each key ];
		send: [ :each | each value value ]
]

{ #category : 'accessing' }
ZkfolStatement >> interestingObjects [
	"My conjurable structures, each name beside the block answering it:
	 the one list my own Objects view shows and the receipt reads off
	 its final stage, so neither maintains the other's."
	^ {
		'lay' -> [ self lay ].
		'allocation' -> [ self alloc ].
		'derivation' -> [ self derivation ] }
]

{ #category : 'views' }
ZkfolStatement >> gtDerivationGraphFor: aView [
	"The derivation's own graph, enriched with what only I can add:
	 clicking a fact opens the statement beneath it, re-rooted at the
	 fact's relation, which needs my relations. A stage that kept no
	 derivation hides the tab."
	<gtView>
	<gtBeamView>
	| feed |
	feed := self plainFetch: 'Zkfol.Face.derivation(' , self resolve , ')'.
	((feed isKindOf: Dictionary)
		and: [ (feed at: #rows ifAbsent: [ #() ]) notEmpty ])
			ifFalse: [ ^ aView empty ].
	^ aView mondrian
		title: 'Derivation';
		priority: 11;
		painting: [ :aMondrian |
			((ZkfolDerivationGraph onFeed: feed)
				spawner: [ :k | self underAt: k ];
				yourself) paint: aMondrian ]
]

{ #category : 'views' }
ZkfolStatement >> gtJudgementFor: aView [
	"My branches judged column by column, the lay beneath them -- two
	 renderings of the one feed in one grid vocabulary, sharing one
	 label width so the columns align down the page."
	<gtView>
	<gtBeamView>
	| feed |
	feed := self plainFetch: 'Zkfol.Face.judgement(' , self resolve , ')'.
	((feed isKindOf: Dictionary)
		and: [ (feed at: #evals ifAbsent: [ #() ]) notEmpty ])
			ifFalse: [ ^ aView empty ].
	^ aView mondrian
		title: 'Judgement';
		priority: 9;
		painting: [ :aMondrian |
			aMondrian nodes
				stencil: [ :each |
					| judgement lay width box |
					judgement := ZkfolJudgement onFeed: each.
					lay := (ZkfolLayPicture onFeed: each) beInOrder; yourself.
					width := judgement labelWidth max: lay labelWidth.
					judgement labelWidth: width.
					lay labelWidth: width.
					box := BlElement new
						layout: BlLinearLayout vertical;
						clipChildren: false;
						constraintsDo: [ :c |
							c horizontal fitContent.
							c vertical fitContent ];
						yourself.
					box addChild: judgement elementOrError.
					box addChild: (BlElement new size: 1 @ 12; yourself).
					box addChild: lay elementOrError.
					box ];
				with: { feed } ]
]
