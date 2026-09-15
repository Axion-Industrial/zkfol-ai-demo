Class {
	#name : 'ZkfolLayJoin',
	#superclass : 'Object',
	#instVars : [
		'feed',
		'facts',
		'sites',
		'arcs',
		'spawner'
	],
	#category : 'Zkfol-Views',
	#package : 'Zkfol',
	#tag : 'Views'
}

{ #category : 'instance creation' }
ZkfolLayJoin class >> onFeed: aDictionary [
	"The join feed: the derivation's facts, the alloc's members with their sites, and the stands between."
	^ self new setFeed: aDictionary
]

{ #category : 'painting' }
ZkfolLayJoin >> arc: aColor into: aModel [
	"An arc into a pair, hidden until the pair is hovered."
	| arc |
	arc := BlParabollaArcElement new
		zIndex: -1;
		curvatureFraction: 0.15;
		visibility: BlVisibility hidden;
		border: (BlBorder paint: aColor width: 1.5);
		toHead: (BlArrowheadSimpleArrow new
			arrowLengthFraction: 5;
			arrowNoseAngle: 60;
			border: (BlBorder paint: aColor width: 1.5)).
	(arcs at: aModel ifAbsentPut: [ OrderedCollection new ]) add: arc.
	^ arc
]

{ #category : 'painting' }
ZkfolLayJoin >> box: aText [
	^ self box: aText color: ZkfolPalette nodeBackgroundColor
]

{ #category : 'painting' }
ZkfolLayJoin >> box: aText color: aColor [
	^ BlTextElement new
		text: (aText fontSize: 11);
		background: aColor;
		padding: (BlInsets all: 6);
		margin: (BlInsets all: 3);
		border: (BlBorder paint: ZkfolPalette nodeBorderColor);
		geometry: (BlRoundedRectangleGeometry cornerRadius: 4)
]

{ #category : 'colouring' }
ZkfolLayJoin >> factColor: aFact [
	"A fact wears one hue wherever it appears."
	^ Color h: aFact second * 137 \\ 360 s: 0.3 v: 0.95
]

{ #category : 'colouring' }
ZkfolLayJoin >> factText: aFact [
	^ aFact last asRopedText background: (self factColor: aFact)
]

{ #category : 'painting' }
ZkfolLayJoin >> frame: aText [
	"A box that holds nodes of its own, headed by its name."
	^ BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		padding: (BlInsets all: 6);
		margin: (BlInsets all: 4);
		border: (BlBorder paint: ZkfolPalette outlineColor width: 1);
		geometry: (BlRoundedRectangleGeometry cornerRadius: 6);
		addChild: (BlTextElement new
			text: (aText fontSize: 11; foreground: ZkfolPalette mutedTextColor);
			padding: (BlInsets all: 3))
]

{ #category : 'painting' }
ZkfolLayJoin >> hover: anElement for: aModel [
	"The arcs into a pair show while the mouse is over it."
	anElement
		when: BlMouseEnterEvent do: [ :event | self show: true arcsOf: aModel ];
		when: BlMouseLeaveEvent do: [ :event | self show: false arcsOf: aModel ].
	^ anElement
]

{ #category : 'painting' }
ZkfolLayJoin >> paint: aMondrian [
	"The two streams meeting. Left, the derivation's facts, each in its
	 own hue; right, the alloc's members with their sites, each in its
	 read colour; between, each stand at the column it was laid, its
	 uses inside, every pair wearing the colours of the two it joins.
	 Hovering a pair draws the arcs that brought its halves in; a click
	 opens the datum itself."
	| stands members |
	stands := feed at: #stands.
	members := feed at: #members.
	aMondrian nodes
		shape: [ :column | self frame: column key asRopedText ];
		with: { 'Derivation' -> facts. 'Stands' -> stands. 'Alloc' -> members };
		forEach: [ :column |
			column key = 'Derivation' ifTrue: [
				aMondrian nodes
					shape: [ :fact |
						self spawn: (self box: fact last asRopedText color: (self factColor: fact))
							as: 'Enum.at(lay.derivation.facts, ' , fact second printString , ')' ];
					with: facts ].
			column key = 'Stands' ifTrue: [
				aMondrian nodes
					shape: [ :stand |
						self spawn: (self hover: (self frame: (self
							pair: (self factText: (facts at: (stand at: #fact) + 1))
							with: (stand at: #member) asString asRopedText
							at: (stand at: #laid))) for: stand)
							as: (self standPath: stand) ];
					with: stands;
					forEach: [ :stand |
						aMondrian nodes
							shape: [ :use |
								self spawn: (self hover: (self box: (self
									pair: (self siteText: ((sites at: (use at: #site) first) at: (use at: #site) second + 1))
									with: (self factText: (facts at: (use at: #fact) + 1))
									at: (use at: #laid))) for: use)
									as: 'Enum.at(' , (self standPath: stand) , '.uses, ' , (((stand at: #uses) identityIndexOf: use) - 1) printString , ')' ];
							with: (stand at: #uses).
						aMondrian layout vertical ] ].
			column key = 'Alloc' ifTrue: [
				aMondrian nodes
					shape: [ :member | self frame: (member at: #name) asString asRopedText ];
					with: members;
					forEach: [ :member |
						aMondrian nodes
							shape: [ :site |
								self spawn: (self box: site last asRopedText color: (self siteColor: site))
									as: 'Enum.at(Enum.uniq(Enum.concat(Map.values(Zkfol.Alloc.member(lay.alloc, :' , site second asString , ').sites))), ' , site third printString , ')' ];
							with: (sites at: (member at: #name)).
						aMondrian layout vertical ] ].
			aMondrian layout vertical ].
	aMondrian edges
		stencil: [ :edge | self arc: (Color gray alpha: 0.6) into: edge value ];
		connect: (stands collect: [ :stand | (facts at: (stand at: #fact) + 1) -> stand ])
			from: [ :edge | edge key ] to: [ :edge | edge value ].
	aMondrian edges
		stencil: [ :edge | self arc: (Color gray alpha: 0.6) into: edge value ];
		connect: (stands flatCollect: [ :stand |
				(stand at: #uses) collect: [ :use | (facts at: (use at: #fact) + 1) -> use ] ])
			from: [ :edge | edge key ] to: [ :edge | edge value ].
	aMondrian edges
		stencil: [ :edge | self arc: ((ZkfolPalette readColor: (edge key at: 3)) alpha: 0.8) into: edge value ];
		connect: (stands flatCollect: [ :stand |
				(stand at: #uses) collect: [ :use |
					((sites at: (use at: #site) first) at: (use at: #site) second + 1) -> use ] ])
			from: [ :edge | edge key ] to: [ :edge | edge value ].
	aMondrian layout custom: (BlLinearLayout horizontal cellSpacing: 120)
]

{ #category : 'colouring' }
ZkfolLayJoin >> pair: leftText with: rightText at: aColumn [
	^ '{' asRopedText , leftText , ', ' asRopedText , rightText , ('} at ' , aColumn) asRopedText
]

{ #category : 'accessing' }
ZkfolLayJoin >> setFeed: aDictionary [
	"One model object per fact and per site, so an edge finds the node it names."
	feed := aDictionary.
	arcs := IdentityDictionary new.
	facts := (feed at: #facts) collect: [ :fact | Array with: #fact with: (fact at: #index) with: (fact at: #label) ].
	sites := Dictionary new.
	(feed at: #members) do: [ :member |
		sites at: (member at: #name) put: ((member at: #sites)
			collectWithIndex: [ :label :k | Array with: #site with: (member at: #name) with: k - 1 with: label ]) ]
]

{ #category : 'painting' }
ZkfolLayJoin >> show: aBoolean arcsOf: aModel [
	(arcs at: aModel ifAbsent: [ #() ]) do: [ :arc |
		arc visibility: (aBoolean ifTrue: [ BlVisibility visible ] ifFalse: [ BlVisibility hidden ]) ]
]

{ #category : 'colouring' }
ZkfolLayJoin >> siteColor: aSite [
	"A site wears its read colour, the one the grid's arrows wear."
	^ (ZkfolPalette readColor: aSite third) alpha: 0.35
]

{ #category : 'colouring' }
ZkfolLayJoin >> siteText: aSite [
	^ aSite last asRopedText background: (self siteColor: aSite)
]

{ #category : 'painting' }
ZkfolLayJoin >> spawn: anElement as: anExpression [
	"Clicking the element opens the datum the expression names in the lay."
	spawner ifNil: [ ^ anElement ].
	^ ZkfolElements make: anElement spawn: [ spawner value: anExpression ]
]

{ #category : 'accessing' }
ZkfolLayJoin >> spawner: aBlock [
	"The block a click answers through, taking an Elixir expression over `lay`; without one, nothing spawns."
	spawner := aBlock
]

{ #category : 'painting' }
ZkfolLayJoin >> standPath: aStand [
	^ 'Enum.at(lay.stands, ' , (((feed at: #stands) identityIndexOf: aStand) - 1) printString , ')'
]
