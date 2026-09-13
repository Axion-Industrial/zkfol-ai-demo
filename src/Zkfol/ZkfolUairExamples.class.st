Class {
	#name : 'ZkfolUairExamples',
	#superclass : 'Object',
	#category : 'Zkfol-Examples',
	#package : 'Zkfol',
	#tag : 'Examples'
}

{ #category : 'accessing' }
ZkfolUairExamples >> assumedFields [
	"The face's grid feed keys, and so what the drift guard holds
	 reality to: the grid draws exactly these and derives nothing."
	^ #(columns len degree kinds num_vars num_public shifts reads origins)
]

{ #category : 'examples' }
ZkfolUairExamples >> bignumCells [
	"I assert big values stay honest: the cell compacts a 21 digit
	 number to its magnitude, carries the full value as its tooltip,
	 and the spawned cell object speaks the whole number, never the
	 truncation."
	<gtExample>
	<return: #ZkfolUairCell>
	| grid big element cell |
	big := 573147844013817084101.
	grid := ZkfolUairGrid onUair: Dictionary new.
	self assert: (ZkfolElements compactValue: big upTo: 5) equals: '5.7e20'.
	self assert: (ZkfolElements compactValue: 12345 upTo: 5) equals: '12345'.
	element := grid picture cellElementFor: big row: 0 position: 1 kind: #plain.
	self
		assert: ((self textsUnder: element) includes: '5.7e20')
		description: 'the cell shows the magnitude'.
	self
		assert: (element aptitude class = BrWithExplicitTooltipAptitude)
		description: 'the full value rides the tooltip'.
	cell := ZkfolUairCell row: 0 kind: #plain position: 1 bits: '000' value: big.
	self
		assert: (cell printString endsWith: big printString)
		description: 'the spawned cell speaks the full number'.
	self
		assert: ((cell gtFactsFor: GtPhlowView empty) isKindOf: GtPhlowColumnedListView).
	^ cell
]

{ #category : 'examples' }
ZkfolUairExamples >> cellClickSpawnsCell [
	"I click the first cell of the claimed row under a scripter and
	 assert the phlow spawn: a ZkfolUairCell naming its row, kind,
	 position with bit spelling, and value."
	<gtExample>
	<return: #BlScripter>
	| scripter spawned |
	scripter := self clickScripterOn: self gridFromFixture picture asElement id: #zkfolUairCell index: 1.
	spawned := self spawnedObjectsOf: scripter.
	self assert: spawned size equals: 1.
	self assert: (spawned first isKindOf: ZkfolUairCell).
	"the printString carries row, position, bit spelling, and value together"
	self assert: spawned first printString equals: 'row 0 at 1 (000): 6'.
	^ scripter
]

{ #category : 'fixtures' }
ZkfolUairExamples >> classicAffine [
	"The pre-Section-4 shape: every read affine, so no composed reads and
	 no lookups; the face settled it to committed order and named the
	 kinds, the index column earning its tint."
	<gtExample>
	<return: #Dictionary>
	^ {
		#num_public -> 1.
		#num_vars -> 3.
		#kinds -> #(#plain #scheduled #index).
		#reads -> #().
		#shifts -> { #(1 1). #(1 2) }.
		#columns -> {
			#(1 1 1 2 3 5 354224848179261915075 573147844013817084101).
			#(1 1 1 1 1 1 2 3).
			#(1 2 3 4 5 6 7 8) } } asDictionary
]

{ #category : 'examples' }
ZkfolUairExamples >> classicStatementTags [
	"I read the classic all-affine fixture, no composed reads or lookups,
	 and assert the settled kinds render: the claimed row tags its label,
	 scheduled rows tint violet and name their offsets, the index column
	 earns its tint, and hover follows every scheduled offset forward
	 through the committed trace."
	<gtExample>
	<return: #ZkfolUairGrid>
	| grid picture element |
	grid := ZkfolUairGrid onUair: self classicAffine.
	picture := grid picture.
	self
		assert: ((0 to: 2) collect: [ :each | grid kindOfRow: each ]) asArray
		equals: #(#plain #scheduled #index).
	self
		assert: (grid labelTextFor: #plain at: 0) equals: '0 · claimed'.
	self
		assert: (grid labelTextFor: #scheduled at: 1) equals: '1 · shifts 1, 2'.
	self
		assert: (grid labelTextFor: #index at: 2) equals: '2 · index'.
	"hover follows a scheduled row forward through the trace, at each
	 offset it carries. Asserted on hoverLit, which is what the grid
	 actually lights."
	picture hovered: 1 @ 5.
	self assert: picture hoverLit keys asSet equals: { 1 @ 6. 1 @ 7 } asSet.
	picture hideHover.
	element := picture asElement.
	self
		assert: ((self textsUnder: element) includes: '1 · shifts 1, 2')
		description: 'the tags the model spells reach the rendered element'.
	^ grid
]

{ #category : 'private' }
ZkfolUairExamples >> clickScripterOn: anElement id: anIdSymbol index: anIndex [
	"The click choreography every spawn example repeats: an element
	 under a scripter, one click on the nth element wearing the id."
	| scripter |
	scripter := BlScripter new.
	scripter element: anElement.
	scripter click
		label: 'Click ' , anIdSymbol printString , ' at ' , anIndex printString;
		id: anIdSymbol index: anIndex;
		play.
	^ scripter
]

{ #category : 'examples' }
ZkfolUairExamples >> derefMiniCellClickSpawnsCell [
	"A cell stays clickable through the deref view, which reaches it
	 inside a Mondrian node rather than at the top of an element."
	<gtExample>
	<return: #BlScripter>
	| chain view element scripter spawned |
	chain := self miniatureChain.
	view := chain gtWalkFor: GtPhlowView empty.
	element := nil.
	view asElementDo: [ :each | element := each ].
	element forceLayout.
	scripter := self clickScripterOn: element id: #zkfolUairCell index: 1.
	spawned := self spawnedObjectsOf: scripter.
	self assert: spawned size equals: 1.
	self assert: (spawned first isKindOf: ZkfolUairCell).
	^ scripter
]

{ #category : 'examples' }
ZkfolUairExamples >> derefWalkDrawsItsClaims [
	"The threads a read draws: one from each address bit into the cell
	 those bits spell, then one from that cell to the result it claims it
	 equals. Asserted on what the grid is handed, not on a parallel list."
	<gtExample>
	<return: #ZkfolDerefChain>
	| chain target threads |
	chain := self miniatureChain.
	self assert: chain agrees.
	target := chain valueRow @ chain target.
	threads := chain threads.
	self
		assert: (threads collect: [ :each | each key ]) asArray
		equals: (chain bitRowIndices collect: [ :row | row @ chain position -> target ]) asArray
			, { target -> (chain resultRow @ chain position) }.
	self
		assert: (threads collect: [ :each | each value ]) asSet
		equals: { chain displayColor } asSet.
	^ chain
]

{ #category : 'private' }
ZkfolUairExamples >> elementWithId: anIdSymbol in: anElement [
	"The first descendant carrying the id, nil when none does."
	anElement withAllChildrenBreadthFirstDo: [ :each |
		each id asSymbol = anIdSymbol ifTrue: [ ^ each ] ].
	^ nil
]

{ #category : 'private' }
ZkfolUairExamples >> elementsWithId: anIdSymbol in: anElement [
	"Every descendant carrying the id, in order. The trace cells, the
	 pipeline nodes: several examples counted these by hand with the
	 same four lines."
	| found |
	found := OrderedCollection new.
	anElement withAllChildrenBreadthFirstDo: [ :each |
		each id asSymbol = anIdSymbol ifTrue: [ found add: each ] ].
	^ found
]

{ #category : 'fixtures' }
ZkfolUairExamples >> emittedFibonacci [
	"Zkfol.Face.grid of the emitted fibonacci at witness 8: the compiler
	 output settled at the source, columns in committed order."
	<gtExample>
	<return: #Dictionary>
	^ {
		#num_public -> 0.
		#num_vars -> 3.
		#kinds -> #(#scheduled #scheduled #plain #plain #scheduled #scheduled).
		#reads -> #().
		#shifts -> { #(0 1). #(0 2). #(1 1). #(1 2). #(4 1). #(5 1). #(5 1) }.
		#columns -> {
			#(1 2 3 4 5 6 7 8).
			#(1 1 2 3 5 8 13 21).
			#(1 1 2 3 4 5 6 7).
			#(1 1 1 2 3 4 5 6).
			#(1 2 3 4 5 6 7 8).
			#(1 1 1 1 1 1 1 1) } } asDictionary
]

{ #category : 'examples' }
ZkfolUairExamples >> emittedFibonacciRenders [
	"Compiler output, where the other fixtures are miniatures: the
	 scheduler's shifts land as scheduled rows, and the whole of it
	 renders with those rows' tags in the tree."
	<gtExample>
	<return: #ZkfolUairGrid>
	| grid element |
	grid := ZkfolUairGrid onUair: self emittedFibonacci.
	self assert: (grid kindOfRow: 0) equals: #scheduled.
	element := grid picture asElement.
	self
		assert: ((self textsUnder: element) includes: (grid labelTextFor: #scheduled at: 0))
		description: 'a scheduled row tag reaches the rendered element'.
	^ grid
]

{ #category : 'examples' }
ZkfolUairExamples >> failuresAreSilentUntilTheTraceContradictsItself [
	"I assert the failure list says nothing when nothing is wrong. Every
	 sound fixture lists no failure and offers no tab at all; the broken
	 hop contradicts at four of its five reads. A view that is empty when
	 all is well is one whose presence means something."
	<gtExample>
	<return: #ZkfolUairGrid>
	| broken |
	#(miniatureHop hopWithTwoReads) do: [ :fx |
		| grid |
		grid := ZkfolUairGrid onUair: (self perform: fx).
		self assert: grid failingChains isEmpty.
		"a sound trace offers no failure view at all"
		self
			assert: (grid gtFailuresFor: GtPhlowView empty) class
			equals: GtPhlowEmptyView ].
	broken := ZkfolUairGrid onUair: self hopReversed.
	self assert: broken failingChains size equals: 4.
	self
		assert: (broken gtFailuresFor: GtPhlowView empty) class
		equals: GtPhlowColumnedListView.
	broken failingChains do: [ :chain |
		self assert: chain agrees not.
		"its ends are the trace's own cells, by value: what lets a graph
		 pair them up, and what the drawing silently needs"
		self
			assert: (broken cellAtRow: chain valueRow position: chain target)
			equals: chain targetCell ].
	self
		assert: (broken hoverPairsOf: 1 position: 1 value: 3) first key
		equals: ZkfolPalette failureColor.
	^ broken
]

{ #category : 'examples' }
ZkfolUairExamples >> failuresBeyondThePicture [
	"The drawing cap never limits the verdict or the target of a read."
	<gtExample>
	<return: #ZkfolUairGrid>
	| grid values results feed |
	values := Array new: 1024 withAll: 3.
	results := values copy at: 700 put: 4; yourself.
	feed := {
		#num_public -> 0.
		#num_vars -> 10.
		#len -> 1024.
		#kinds -> #(#plain #bit #result).
		#columns -> { values. Array new: 1024 withAll: 0. results }.
		#reads -> { { #row -> 1. #value_row -> 0. #bit_rows -> #(1). #result_row -> 2 } asDictionary }
	} asDictionary.
	grid := ZkfolUairGrid onUair: feed.
	self assert: grid displayedPositions < 700.
	self assert: grid failingChains size equals: 1.
	self assert: grid failingChains first position equals: 700.
	self assert: (grid gtFailuresFor: GtPhlowView empty) class equals: GtPhlowColumnedListView.
	^ grid
]

{ #category : 'examples' }
ZkfolUairExamples >> gridElement [
	"I render the fixture grid: the position ruler, then one row element
	 per committed column, the claimed row outlined, and last the
	 connector layer the hover connectors are drawn into, always present
	 and empty at rest. A miniature within the render budget carries no
	 truncation marker."
	<gtExample>
	<return: #BlElement>
	| grid element claimed layer |
	grid := self gridFromFixture.
	element := grid picture asElement.
	self assert: element children size equals: grid numCols + 2.
	self
		assert: (self elementWithId: #zkfolTruncationMarker in: element) isNil
		description: 'a miniature within budget carries no truncation marker'.
	claimed := element children detect: [ :each | each border width > 0 ] ifNone: [ nil ].
	self assert: claimed notNil description: 'the claimed row should be outlined'.
	layer := self elementWithId: #zkfolUairHoverLayer in: element.
	self assert: layer notNil description: 'the connector layer is always present'.
	self assert: layer children isEmpty description: 'and empty until something is hovered'.
	^ element
]

{ #category : 'examples' }
ZkfolUairExamples >> gridFromFixture [
	"I read the miniature fixture and assert every grid row wears the
	 kind the face named, so a drifting fixture fails here rather than
	 somewhere downstream."
	<gtExample>
	<return: #ZkfolUairGrid>
	| grid |
	grid := ZkfolUairGrid onUair: self miniatureHop.
	self
		assert: ((0 to: 6) collect: [ :i | grid kindOfRow: i ]) asArray
		equals: #(#plain #pointer #plain #bit #bit #bit #result).
	^ grid
]

{ #category : 'examples' }
ZkfolUairExamples >> headerClickSpawnsColumn [
	"I click the position ruler under a scripter and assert the phlow
	 spawn: a ZkfolUairColumn carrying every row's cell at position 2
	 and the composed read's deref chain, address 3 spelled from its
	 bit rows, agreeing with the result row."
	<gtExample>
	<return: #BlScripter>
	| scripter spawned |
	scripter := self clickScripterOn: self gridFromFixture picture asElement id: #zkfolUairHeader index: 2.
	spawned := self spawnedObjectsOf: scripter.
	self assert: spawned size equals: 1.
	self assert: (spawned first isKindOf: ZkfolUairColumn).
	self assert: spawned first position equals: 2.
	self assert: spawned first derefs size equals: 1.
	self
		assert: spawned first derefs first agrees
		description: 'following the address lands on the value the result row holds'.
	^ scripter
]

{ #category : 'fixtures' }
ZkfolUairExamples >> hopReversed [
	"A committed hop whose deref chain contradicts itself: the addresses
	 its pointer holds do not land on cells that agree, which is exactly
	 what the failures view is for."
	<gtExample>
	<return: #Dictionary>
	^ {
		#num_public -> 0.
		#num_vars -> 2.
		#kinds -> #(#plain #pointer #bit #bit #result).
		#shifts -> #().
		#reads -> { { #row -> 1. #value_row -> 0. #bit_rows -> #(2 3). #result_row -> 4 } asDictionary }.
		#columns -> self reversedHopColumns } asDictionary
]

{ #category : 'fixtures' }
ZkfolUairExamples >> hopWithTwoReads [
	"A length 3 hop with TWO composed reads sharing one pointer, in
	 committed order: value rows 0 and 1, the pointer row 2 with its two
	 bit rows, and a result row per read, 5 and 6. Hover on the pointer
	 lights each read's target and result in its own color, so the two
	 greens at rest split into two hues on hover."
	<gtExample>
	<return: #Dictionary>
	^ {
			#num_public -> 0.
			#num_vars -> 2.
			#kinds -> #(#plain #plain #pointer #bit #bit #result #result).
			#shifts -> #().
			#reads -> {
				{ #row -> 2. #value_row -> 0. #bit_rows -> #(3 4). #result_row -> 5 } asDictionary.
				{ #row -> 2. #value_row -> 1. #bit_rows -> #(3 4). #result_row -> 6 } asDictionary }.
			#columns -> {
				#(10 20 30).
				#(40 50 60).
				#(2 1 3).
				#(1 0 0).
				#(0 1 0).
				#(20 30 10).
				#(50 60 40) } } asDictionary
]

{ #category : 'examples' }
ZkfolUairExamples >> hoverIsOneValueAndEverythingFollows [
	"I assert hover holds nothing but which cell the mouse is over. Every
	 highlight and connector is recomputed from that one value, so moving
	 straight from one cell to another with no leave event in between
	 strands nothing."
	<gtExample>
	<return: #ZkfolUairGrid>
	| grid picture element layer |
	grid := self gridFromFixture.
	picture := grid picture.
	element := picture asElement.
	layer := self elementWithId: #zkfolUairHoverLayer in: element.
	self assert: picture hoverLit isEmpty.
	self assert: layer children isEmpty.
	picture hovered: 1 @ 2.
	self assert: picture hoverLit size equals: 5.
	self assert: layer children size equals: 5.
	"straight to another cell, no leave event in between"
	picture hovered: 1 @ 5.
	self assert: picture hoverLit size equals: 5.
	self assert: layer children size equals: 5.
	picture hideHover.
	self assert: picture hoverLit isEmpty.
	self assert: layer children isEmpty.
	^ grid
]

{ #category : 'examples' }
ZkfolUairExamples >> hoverPairsColorPerRead [
	"I hover the shared pointer of a two-read hop and assert each read
	 lights BOTH ends, its target and its result, in its own colour: two
	 distinct colours across four lit cells, so the uniform green results
	 split by read on hover. I name the four, so this also asserts the
	 addresses resolve where they should. Moving off clears all of it.

	 The colouring and the resolution used to be two examples. They hover
	 the same cell through the same code; the two-read grid just says
	 more while doing it."
	<gtExample>
	<return: #BlScripter>
	| scripter grid picture element cellsPerRow |
	grid := ZkfolUairGrid onUair: self hopWithTwoReads.
	picture := grid picture.
	element := picture asElement.
	scripter := BlScripter new.
	scripter element: element.
	cellsPerRow := grid displayColumns first size.
	scripter mouseMoveOver
		label: 'Hover the shared pointer cell at position 1';
		id: #zkfolUairCell index: (2 * cellsPerRow) + 1;
		play.
	self
		assert: (picture hoverLit keys asSortedCollection: [ :a :b |
			a x = b x ifTrue: [ a y < b y ] ifFalse: [ a x < b x ] ]) asArray
		equals: { 0 @ 2. 1 @ 2. 3 @ 1. 4 @ 1. 5 @ 1. 6 @ 1 }.
	self
		assert: picture hoverLit values asSet
		equals: { ZkfolPalette readColor: 0. ZkfolPalette readColor: 1 } asSet.
	self
		assert: (self elementWithId: #zkfolUairHoverLine in: element) notNil
		description: 'connectors should appear'.
	"Drawn is not the same as seen: the layer holding the connectors sizes
	 itself to nothing, so it must not clip, or the lines are laid out
	 correctly and then cut away and the grid looks like it draws none."
	self
		assert: (self elementWithId: #zkfolUairHoverLayer in: element) clipChildren not
		description: 'the hover layer must not clip the connectors it holds'.
	scripter mouseMoveOver
		label: 'Move off to a plain cell';
		id: #zkfolUairCell index: 1;
		play.
	self assert: picture hoverLit isEmpty description: 'moving off clears every highlight'.
	self
		assert: (self elementWithId: #zkfolUairHoverLine in: element) isNil
		description: 'and every connector'.
	^ scripter
]

{ #category : 'examples' }
ZkfolUairExamples >> liveUairFieldsConform [
	"I turn the drift worry into a failing test: I fetch the face's grid
	 feed of a real emitted uair and assert its key set is exactly what
	 the fixtures and grid assume, so if the feed grows, renames, or
	 drops a key, THIS trips red instead of the fixtures drifting
	 silently from reality. I need the live node, so I do not run
	 headless."
	<gtExample>
	<noTest>
	<return: #Set>
	| app uair fields assumed |
	app := BeamLinkApplication uniqueInstance.
	self
		assert: (app notNil and: [ app isRunning ])
		description: 'a gt_bridge session must be running'.
	self
		assert: (app evaluateAndWait: 'function_exported?(Examples.EAl, :composed_hop_emits, 0)')
		description: 'the node must run the lookup/uair-struct stack'.
	uair := app evaluateAndWait: 'Examples.EAl.composed_hop_emits()'.
	fields := (uair plainFetch: 'Zkfol.Face.grid(' , uair resolve , ')') keys asSet.
	assumed := self assumedFields asSet.
	self
		assert: fields = assumed
		description: 'the face feed drifted from what the grid draws: '
			, ((fields difference: assumed) , (assumed difference: fields)) asArray printString.
	^ fields
]

{ #category : 'examples' }
ZkfolUairExamples >> miniatureChain [
	"The composed read of the miniature hop, at the position its examples
	 all use. Three examples built this same chain three times before it
	 had a name: the walk's claims, the walk's grid language, and the
	 click that spawns a cell from it."
	<gtExample>
	<return: #ZkfolDerefChain>
	| chain |
	chain := (self gridFromFixture columnAt: 2) derefs first.
	self assert: chain agrees.
	self assert: chain address equals: 5.
	^ chain
]

{ #category : 'fixtures' }
ZkfolUairExamples >> miniatureHop [
	"A miniature grid feed the way the face hands it, in committed order:
	 lists as arrays, maps as dictionaries, tuples as arrays. Column 0
	 carries the claimed value row, column 1 a dynamic pointer under a
	 Word lookup, columns 3 to 5 its bit rows, column 6 the dereference
	 results, column 2 stays plain.
	 A plain Dictionary: a live uair arrives as one settled feed from the
	 face and is parsed straight into one of these."
	<gtExample>
	<return: #Dictionary>
	^ {
			#num_public -> 1.
			#num_vars -> 3.
			#kinds -> #(#plain #pointer #plain #bit #bit #bit #result).
			#shifts -> #().
			#reads -> { { #row -> 1. #value_row -> 0. #bit_rows -> #(3 4 5). #result_row -> 6 } asDictionary }.
			#columns -> {
				#(6 2 9 5 1 4 1 3).
				#(1 3 2 5 4 1 2 1).
				#(0 1 1 2 3 5 8 13).
				#(1 1 0 1 0 1 0 1).
				#(1 0 1 1 0 1 1 1).
				#(1 1 1 0 1 1 1 1).
				#(3 4 1 5 1 3 1 3) } } asDictionary
]

{ #category : 'examples' }
ZkfolUairExamples >> pipelineElement [
	"I render the act as its vertical Mondrian graph and assert the flow:
	 the source node, one node per pass, the prove tail, the report at the
	 bottom, all as nodes on the canvas."
	<gtExample>
	<return: #GtPhlowMondrianView>
	| view element nodes |
	view := self pipelineModel gtPipelineFor: GtPhlowView empty.
	view asElementDo: [ :e | element := e ].
	(BlScripter new element: element; yourself)
		wait forEmptySpaceTaskQueue;
		play.
	self assert: (self elementWithId: #zkfolPipelineSource in: element) notNil.
	nodes := self elementsWithId: #zkfolPipelineNode in: element.
	self assert: nodes size equals: 4.
	self assert: (self elementWithId: #zkfolPipelineIntent in: element) notNil.
	self assert: (self elementWithId: #zkfolPipelineReport in: element) notNil.
	self
		assert: ((self textsUnder: element) includes: 'source · composed_hop')
		description: 'the source node names the route'.
	self
		assert: ((self textsUnder: element) anySatisfy: [ :each | each beginsWith: 'proved · prove' ])
		description: 'the report line carries the timings'.
	^ view
]

{ #category : 'examples' }
ZkfolUairExamples >> pipelineModel [
	"I read the fixture trail into the pipeline model and assert the
	 act's shape: the route named by its define, one stage per piped
	 verdict with the shared palette color its verdict earns, the
	 intent, and the settled report."
	<gtExample>
	<return: #ZkfolPipelineModel>
	| model |
	model := ZkfolPipelineModel example.
	self assert: model routeName equals: #composed_hop.
	self
		assert: (model passes collect: [ :each | each verdict ]) asArray
		equals: #(#rewrites #solves #lowers #expands).
	self assert: model intentName equals: #composed_hop.
	self assert: (model report at: #backend ifAbsent: [ nil ]) equals: 'zinc+ i64'.
	self assert: model trail size equals: 4.
	^ model
]

{ #category : 'examples' }
ZkfolUairExamples >> pipelineStageClickSpawnsTransform [
	"I click a stage node on the Mondrian pipeline under a scripter and
	 assert the phlow spawn: the stage transform holding before and after
	 states, its delta showing how Doubling rewrote the statement."
	<gtExample>
	<return: #BlScripter>
	| view element scripter spawned delta |
	view := self pipelineModel gtPipelineFor: GtPhlowView empty.
	view asElementDo: [ :e | element := e ].
	scripter := BlScripter new.
	scripter element: element.
	scripter wait forEmptySpaceTaskQueue.
	scripter click id: #zkfolPipelineNode index: 2; play.
	spawned := self spawnedObjectsOf: scripter.
	self assert: spawned size equals: 1.
	self assert: (spawned first isKindOf: ZkfolStageTransform).
	self assert: spawned first printString
		equals: 'composed_hop stage 1 to 2: Witness solves'.
	delta := spawned first delta.
	self assert: (delta detect: [ :each | each first = #branches ]) allButFirst
		equals: #(3 5 true).
	self assert: (delta detect: [ :each | each first = #claims ]) allButFirst
		equals: #(0 2 true).
	self assert: (delta detect: [ :each | each first = #rels ]) last not.
	^ scripter
]

{ #category : 'examples' }
ZkfolUairExamples >> pipelineViews [
	"I build both pipeline views from the fixture model: the Mondrian
	 flow renders its stage nodes on a pannable canvas, and the trail
	 view lists the journaled events as a columned list."
	<gtExample>
	<return: #ZkfolPipelineModel>
	| model flow trailView element |
	model := self pipelineModel.
	flow := model gtPipelineFor: GtPhlowView empty.
	self assert: (flow isKindOf: GtPhlowMondrianView).
	flow asElementDo: [ :e | element := e ].
	(BlScripter new element: element; yourself)
		wait forEmptySpaceTaskQueue;
		play.
	self
		assert: (self elementWithId: #zkfolPipelineSource in: element) notNil
		description: 'the flow view should carry the pipeline nodes'.
	trailView := model gtTrailFor: GtPhlowView empty.
	self assert: (trailView isKindOf: GtPhlowColumnedListView).
	^ model
]

{ #category : 'examples' }
ZkfolUairExamples >> pointerGridForwardBuildsAsync [
	"I run the proxy-side forward wiring over the real future pool, the
	 path a live inspector takes, with both endings: a healthy grid
	 arrives, and a grid that cannot render arrives as its error element.
	 A raising stencil on this path used to trip phlow's double entity
	 assertion and hand the worker a raw pane: the BrHorizontalPane DNU."
	<gtExample>
	<return: #BlScripter>
	| healthy poisoned container scripter |
	healthy := GtPhlowView empty forward
		title: 'Pointer grid';
		object: [ ZkfolUairGrid onUair: self miniatureHop ];
		view: #gtPointerGridFor:;
		yourself.
	poisoned := GtPhlowView empty forward
		title: 'Pointer grid';
		object: [ ZkfolUairGrid onUair: {
			#num_public -> 'not a number'. #columns -> { #(1 2) } } asDictionary ];
		view: #gtPointerGridFor:;
		yourself.
	container := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal exact: 900.
			c vertical exact: 700 ];
		yourself.
	healthy asElementDo: [ :e | container addChild: e ].
	poisoned asElementDo: [ :e | container addChild: e ].
	scripter := BlScripter new.
	scripter element: container.
	scripter wait
		forElementCondition: [ :el |
			(self elementWithId: #zkfolUairGrid in: el) notNil
				and: [ (self elementWithId: #zkfolStencilError in: el) notNil ] ]
		timeout: 10 seconds.
	scripter play.
	self
		assert: (self elementWithId: #zkfolUairGrid in: container) notNil
		description: 'the healthy forward should render the grid'.
	self
		assert: (self elementWithId: #zkfolStencilError in: container) notNil
		description: 'the failing forward should render the grid error, not reject'.
	^ scripter
]

{ #category : 'examples' }
ZkfolUairExamples >> pointerGridRendersInInspector [
	"I put the grid in a real inspector under a scripter, let the space
	 settle, and assert the Pointer grid tab is offered and its grid
	 element actually rendered: the ruler, one row per committed column,
	 and the connector layer, so numCols + 2 children."
	<gtExample>
	<return: #BlScripter>
	| scripter expected |
	expected := self gridFromFixture numCols + 2.
	scripter := BlScripter new.
	scripter element: (GtInspectorTool new object: self gridFromFixture) asElement.
	scripter wait forEmptySpaceTaskQueue.
	scripter play.
	scripter assertStep: [ :s |
		s
			label: 'The grid rendered the ruler and one row per committed column';
			value: [ :el | el children size ] equals: [ expected ];
			// #zkfolUairGrid ].
	scripter assertStep: [ :s |
		s
			label: 'The Pointer grid tab is present';
			value: [ :el | | texts |
				texts := OrderedCollection new.
				el withAllChildrenBreadthFirstDo: [ :c |
					(c isKindOf: BrTab) ifTrue: [
						c withAllChildrenBreadthFirstDo: [ :t |
							(t isKindOf: BlTextElement) ifTrue: [ texts add: t text asString ] ] ] ].
				texts includes: 'Pointer grid' ]
			equals: [ true ] ].
	^ scripter
]

{ #category : 'examples' }
ZkfolUairExamples >> pointerGridView [
	"I build the Pointer grid phlow view from the grid: a Mondrian view
	 carrying the whole trace as one node, so it inherits the canvas's
	 pan and zoom. I assert the view is a Mondrian view and the grid
	 element, with its cells, renders inside it."
	<gtExample>
	<return: #GtPhlowMondrianView>
	| view element |
	view := self gridFromFixture gtPointerGridFor: GtPhlowView empty.
	self assert: (view isKindOf: GtPhlowMondrianView).
	view asElementDo: [ :e | element := e ].
	(BlScripter new model: view; element: element; yourself)
		wait forEmptySpaceTaskQueue;
		play.
	self
		assert: (self elementWithId: #zkfolUairGrid in: element) notNil
		description: 'the grid is one node on the Mondrian canvas'.
	self
		assert: (element withAllChildren anySatisfy: [ :each | each id asSymbol = #zkfolUairCell ])
		description: 'its colored cells render'.
	^ view
]

{ #category : 'examples' }
ZkfolUairExamples >> refusedUairSaysWhy [
	"A uair the boundary cannot read shows why; an empty one shows no
	 tab, because nothing is wrong. Both answered nil before, so a
	 failure and an absence looked the same."
	<gtExample>
	<return: #ZkfolUairGrid>
	| refused honest element |
	refused := ZkfolUairGrid onUair: ZkfolUair new.
	self assert: (refused refusal reason includesSubstring: 'uair payload').
	self
		assert: (refused gtPointerGridFor: GtPhlowView empty) class
		equals: GtPhlowExplicitView.
	(refused gtPointerGridFor: GtPhlowView empty) asElementDo: [ :e | element := e ].
	self assert: ((self textsUnder: element) anySatisfy: [ :t | t includesSubstring: 'uair payload' ]).
	honest := ZkfolUairGrid onUair: Dictionary new.
	self assert: honest refusal isNil.
	self
		assert: (honest gtPointerGridFor: GtPhlowView empty) class
		equals: GtPhlowEmptyView.
	^ refused
]

{ #category : 'fixtures' }
ZkfolUairExamples >> reversedHopColumns [
	"The committed columns of a length 3 composed hop padded to 2^2 the
	 way the emitter ships them: w = [7, 8, 9], pointer A = [2, 1, 3]
	 with its two bit rows, and a result row that does not match what
	 the addresses select, so every deref in this trace contradicts
	 itself. Every value is asymmetric, so no coincidence hides it."
	<gtExample>
	<return: #Array>
	^ {
		#(9 8 7 7).
		#(3 1 2 2).
		#(1 1 0 0).
		#(1 0 1 1).
		#(9 7 8 8) }
]

{ #category : 'examples' }
ZkfolUairExamples >> rowLabelClickSpawnsRow [
	"I click a row label under a scripter and assert the phlow spawn:
	 a ZkfolUairRow carrying kind, claim, and the whole column."
	<gtExample>
	<return: #BlScripter>
	| scripter spawned |
	scripter := self clickScripterOn: self gridFromFixture picture asElement id: #zkfolUairRowLabel index: 1.
	spawned := self spawnedObjectsOf: scripter.
	self assert: spawned size equals: 1.
	self assert: (spawned first isKindOf: ZkfolUairRow).
	self assert: spawned first claimed.
	self assert: spawned first printString equals: 'row 0 claimed, 8 values'.
	^ scripter
]

{ #category : 'private' }
ZkfolUairExamples >> spawnedObjectsOf: aScripter [
	"The objects the scripter saw phlow asked to spawn."
	^ (aScripter events
		select: [ :each | each class = GtPhlowObjectToSpawn ])
		collect: [ :each | each object ]
]

{ #category : 'examples' }
ZkfolUairExamples >> stageDiffView [
	"I build the transform's Diff view, the detail beside Delta's
	 glance, and assert the word diff marks the changed regions and
	 the coders' Elixir styler rides the view when the SmaCC parser is
	 loaded. The styler is optional, so what it does is asserted only
	 where it exists rather than asserting a different thing per image."
	<gtExample>
	<return: #ZkfolStageTransform>
	| model transform view element change styled |
	model := ZkfolPipelineModel example.
	transform := model transformFor: (model passes at: 1).
	view := transform gtDiffFor: GtPhlowView empty.
	self assert: (view fromLabel includesSubstring: 'before Doubling').
	self assert: (view toLabel includesSubstring: 'after Doubling rewrites').
	view asElementDo: [ :e | element := e ].
	self assert: element notNil description: 'the diff view should build its element'.
	change := GtDiffBuilder
		computeDifferencesFrom: transform beforeText
		to: transform afterText
		using: view defaultSplitter.
	self
		assert: (change changes anySatisfy: [ :each | each isReplacement ])
		description: 'the changed facts should read as replacements'.
	transform elixirStyler ifNotNil: [ :aStyler |
		styled := '%Zkfol.Statement{args: [100], witness: nil}' asRopedText.
		aStyler style: styled.
		self
			assert: ((1 to: styled size) anySatisfy: [ :each | (styled attributesAt: each) notEmpty ])
			description: 'inspect output should carry style attributes'.
		aStyler style: transform beforeText asRopedText ].
	^ transform
]

{ #category : 'fixtures' }
ZkfolUairExamples >> syntheticGridOfLength: aLength vars: aNumVars rows: aRowCount [
	"A trace of a size no fixture should carry, settled the way the face
	 hands it: committed order, the cube filled to its width."
	^ self syntheticGridOfLength: aLength vars: aNumVars rows: aRowCount extra: Dictionary new
]

{ #category : 'fixtures' }
ZkfolUairExamples >> syntheticGridOfLength: aLength vars: aNumVars rows: aRowCount extra: aDictionary [
	"As above, with more payload fields folded in: a caller wanting
	 public rows or shifts states them as payload, not by reaching for a
	 setter afterwards."
	| payload |
	payload := Dictionary new.
	payload at: #num_vars put: aNumVars.
	payload at: #columns put: ((1 to: aRowCount) collect: [ :row |
		(1 to: aLength) asArray ]).
	aDictionary keysAndValuesDo: [ :k :v | payload at: k put: v ].
	^ ZkfolUairGrid onUair: payload
]

{ #category : 'private' }
ZkfolUairExamples >> textsUnder: anElement [
	"Every text string rendered anywhere under an element."
	| texts |
	texts := OrderedCollection new.
	anElement withAllChildrenBreadthFirstDo: [ :each |
		(each isKindOf: BlTextElement) ifTrue: [ texts add: each text asString ] ].
	^ texts
]

{ #category : 'examples' }
ZkfolUairExamples >> wideGridRendersInMondrian [
	"I build a forty-position trace and assert the Mondrian view carries
	 the whole of it as one node with its row labels present, so the
	 canvas's pan and zoom reach every column and nothing is cut off.
	 This is the fibonacci-trace case that once overflowed a fixed
	 pannable; on Mondrian it fits to the canvas and zooms for detail."
	<gtExample>
	<return: #GtPhlowMondrianView>
	| grid view element firstLabel |
	grid := self syntheticGridOfLength: 40 vars: 6 rows: 3 extra: {
		#num_public -> 1.
		#shifts -> { #(1 1). #(1 2) } } asDictionary.
	self assert: grid displayColumns first size equals: 40.
	firstLabel := grid labelTextFor: (grid kindOfRow: 0) at: 0.
	view := grid gtPointerGridFor: GtPhlowView empty.
	self assert: (view isKindOf: GtPhlowMondrianView).
	view asElementDo: [ :e | element := e ].
	element constraintsDo: [ :c | c horizontal exact: 600. c vertical exact: 200 ].
	(BlScripter new model: view; element: element; yourself)
		wait forEmptySpaceTaskQueue;
		play.
	self
		assert: (self elementWithId: #zkfolUairGrid in: element) notNil
		description: 'the wide trace is one node on the canvas'.
	self
		assert: ((self textsUnder: element) includes: firstLabel)
		description: 'its row labels are in the rendered tree'.
	^ view
]

{ #category : 'examples' }
ZkfolUairExamples >> wideGridTruncatesHonestly [
	"I assert the render cap is honest, not silent: under it every
	 position renders unmarked, past it only the head, the real/padding
	 seam, and the tail render, the marker names the true numbers, and
	 both ends are present so it is no flat prefix. The uair already
	 arrives in one fetch, so this bounds rendering, never fetching."
	<gtExample>
	<return: #ZkfolUairGrid>
	| within over overPic overElement shown |
	within := self syntheticGridOfLength: 200 vars: 8 rows: 1.
	self
		assert: (self elementsWithId: #zkfolUairCell in: within picture asElement) size
		equals: 200.
	self
		assert: (self elementWithId: #zkfolTruncationMarker in: within picture asElement) isNil
		description: 'a fitting trace carries no marker'.
	over := self syntheticGridOfLength: 700 vars: 10 rows: 1.
	overPic := over picture.
	overElement := overPic asElement.
	self
		assert: (self elementsWithId: #zkfolUairCell in: overElement) size <= overPic maxPositions
		description: 'past the cap the render is bounded'.
	shown := overPic shownPositions.
	self assert: (shown includes: 1) description: 'the head renders'.
	self assert: (shown includes: 700) description: 'the tail renders'.
	self assert: (shown includes: #ellipsis) description: 'a run is elided between them'.
	self
		assert: ((self elementWithId: #zkfolTruncationMarker in: overElement) text asString
			includesSubstring: 'of 700 positions')
		description: 'the marker names the true cube width'.
	^ over
]
