Class {
	#name : 'ZkfolCommitPicture',
	#superclass : 'Object',
	#instVars : [
		'grid'
	],
	#category : 'Zkfol-Grid',
	#package : 'Zkfol',
	#tag : 'Grid'
}

{ #category : 'instance creation' }
ZkfolCommitPicture class >> on: aGrid [
	^ self new setGrid: aGrid; yourself
]

{ #category : 'rendering' }
ZkfolCommitPicture >> arrowLabelled: aStringOrNil [
	"The step between two stages: an arrow wearing what the step does,
	 the caption's lines stacked beside the line, centred on it and set
	 to its right. No caption, a bare arrow."
	| color arrow label |
	color := ZkfolPalette mutedTextColor alpha: 0.7.
	arrow := BlLineElement new
		zIndex: -1;
		clipChildren: false;
		layout: BlFrameLayout new;
		border: (BlBorder paint: color width: 1.5);
		toHead: (BlArrowheadSimpleArrow new
			arrowLengthFraction: 5;
			arrowNoseAngle: 60;
			border: (BlBorder paint: color width: 1.5));
		yourself.
	aStringOrNil ifNil: [ ^ arrow ].
	label := BrVerticalPane new
		fitContent;
		margin: (BlInsets left: 8);
		constraintsDo: [ :c |
			c frame vertical alignCenter.
			c frame horizontal alignLeft ];
		yourself.
	aStringOrNil lines do: [ :line |
		label addChild: ((self caption: line color: ZkfolPalette mutedTextColor)
			margin: BlInsets empty;
			yourself) ].
	^ arrow addChild: label; yourself
]

{ #category : 'rendering' }
ZkfolCommitPicture >> asElement [
	"What the commitment does to one committed column, drawn down the
	 page because every one of these is long: the column's own cells,
	 the length the code makes of them, the tree the columns hang under,
	 and what a draw takes out of it, each step an arrow saying what it
	 does. Each stage clicks through to the mechanism. Beneath the graph,
	 in its own frame, what the whole trace costs. Absent the backend's
	 parameters I say only what the trace itself knows, and say that I
	 do."
	| pane |
	pane := BrVerticalPane new
		fitContent;
		padding: (BlInsets all: 10);
		addChild: (self graph asElement
			constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
			yourself);
		yourself.
	grid repFactor
		ifNil: [ pane addChild: (self caption: 'the backend named no code parameters' color: ZkfolPalette mutedTextColor) ]
		ifNotNil: [ pane addChild: self totalFrame ].
	^ pane
]

{ #category : 'rendering' }
ZkfolCommitPicture >> caption: aString color: aColor [
	"One stage's line of text, tinted to the block it names."
	^ BlTextElement new
		text: ((aString asRopedText fontName: self unicodeFont) fontSize: 9; foreground: aColor; yourself);
		margin: (BlInsets top: 3);
		yourself
]

{ #category : 'rendering' }
ZkfolCommitPicture >> colorOf: aQuantity [
	"One colour per quantity, everywhere it appears: the committed rows,
	 the cube a column holds, the rate and what it encodes to, and the
	 draws an opening takes. A number is the same colour in a caption, in
	 a total, and in any other view that counts the same thing."
	aQuantity = #rows ifTrue: [ ^ Color r: 0.17 g: 0.44 b: 0.7 ].
	aQuantity = #cube ifTrue: [ ^ Color r: 0.75 g: 0.48 b: 0.19 ].
	aQuantity = #rate ifTrue: [ ^ Color r: 0.2 g: 0.55 b: 0.4 ].
	aQuantity = #draws ifTrue: [ ^ Color r: 0.55 g: 0.3 b: 0.6 ].
	^ ZkfolPalette mutedTextColor
]

{ #category : 'facts' }
ZkfolCommitPicture >> factsFor: aName [
	"What a stage is, as an object to open rather than a picture to
	 squint at: its own numbers, the sentence a hover shows, and the
	 telling a click opens."
	| cube rep opens rows depth d |
	cube := grid fullWidth.
	rep := grid repFactor.
	opens := grid columnOpenings.
	rows := grid displayColumns size.
	depth := self merkleDepth rounded.
	d := Dictionary new.
	d at: #stage put: aName.
	aName = 'evals' ifTrue: [
		d at: #cells put: cube;
			at: #formula put: '2^mu';
			at: #hint put: 'The column''s ', cube printString, ' values on the cube: the message the code encodes.';
			at: #what put: 'One committed column as the sumcheck leaves it: the multilinear polynomial''s value at each of the 2^mu points of the cube. This is the message the code encodes.' ].
	aName = 'encode' ifTrue: [
		d at: #messageCells put: cube;
			at: #codewordCells put: rep * cube;
			at: #rate put: '1/', rep printString;
			at: #formula put: 'codeword_len = row_len x rep_factor';
			at: #hint put: cube printString, ' cells become ', (rep * cube) printString, ', every output mixing every input, so a change anywhere shows almost everywhere.';
			at: #what put: 'The linear code (IPRS) sends the ', cube printString, ' message cells to ', (rep * cube) printString, ' codeword cells. The x', rep printString, ' is a count of cells, NOT bits per cell: it is redundancy, the inverse rate 1/', rep printString, '. Separately the codeword''s cell type is wider than the message''s (i64 -> i128 at the narrow tier), so the growth is in both count and width.';
			at: #whyRedundant put: 'Two codewords of a linear code differ in many positions, so a prover who cheats anywhere must differ almost everywhere. That is what lets a few sampled positions catch it.' ].
	aName = 'commit' ifTrue: [
		d at: #leaves put: grid codewordLength;
			at: #depth put: depth;
			at: #sent put: 'one root';
			at: #hint put: 'Each codeword column, all ', rows printString, ' rows at one position, is a leaf; the verifier is sent one root over ', grid codewordLength printString, '.';
			at: #what put: 'Every codeword column, all ', rows printString, ' committed rows at that position, is hashed to a leaf; the leaves are hashed pairwise up to one root over ', grid codewordLength printString, ' columns, ', depth printString, ' levels deep. The verifier is sent the root alone: the whole matrix is bound by one hash.' ].
	aName = 'open' ifTrue: [
		d at: #columnOpenings put: opens;
			at: #combinedRowCells put: cube;
			at: #revealedCells put: (opens ifNil: [ 0 ]) * rows;
			at: #hint put: (opens ifNil: [ 0 ]) printString, ' drawn columns of ', rows printString, ' cells and ', depth printString, ' hashes, plus one combined row the verifier re-encodes and checks at every draw.';
			at: #what put: 'The verifier gets a Merkle root at commit time. To open, the prover writes one combined row (a random linear combination of the committed rows, ', cube printString, ' cells; with a single row the coefficient is 1), then answers ', (opens ifNil: [ 0 ]) printString, ' sampled column indices with that column''s values in every polynomial plus a Merkle proof.';
			at: #verifierChecks put: #('evaluation consistency' 'coherence' 'proximity: re-encode the combined row and check it agrees at the sampled columns' 'Merkle: the revealed columns are under the committed root') ].
	^ d
]

{ #category : 'rendering' }
ZkfolCommitPicture >> graph [
	"The stages as one column of nodes with the steps drawn as arrows
	 between them, each arrow labelled by what its step does. Mondrian's
	 edges carry no label of their own, so the caption rides the line
	 element, centred on it and set to its right."
	| chain mondrian |
	chain := self stages.
	mondrian := GtMondrian new.
	mondrian nodes
		shape: [ :each | each key ];
		with: chain.
	mondrian edges
		stencil: [ :edge | self arrowLabelled: edge key value ];
		connect: (chain allButLast with: chain allButFirst collect: [ :from :to | from -> to ])
			from: #key
			to: #value.
	mondrian layout custom: (GtGradVerticalDominanceTreeLayout new
		levelDistance: 36;
		nodeDistance: 10).
	^ mondrian
]

{ #category : 'views' }
ZkfolCommitPicture >> gtCommitmentFor: aView [
	"The commitment picture on the grid's canvas, with its pan and zoom."
	<gtView>
	^ ZkfolElements canvasOn: aView title: 'Commitment' priority: 5 node: self
]

{ #category : 'rendering' }
ZkfolCommitPicture >> lengthBarsElement [
	"The rate as a length rather than a word: the message's bar, and the
	 codeword's bar drawn as many times longer as the code makes it. No
	 cells are drawn here because none of these are cells -- the bars are
	 lengths, and the length is the whole of what the rate does."
	| rep unit pane cube |
	rep := grid repFactor.
	cube := grid fullWidth.
	unit := 34.
	pane := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		margin: (BlInsets top: 2 bottom: 2);
		yourself.
	pane addChild: (ZkfolElements gridRow
		addChild: (ZkfolElements box: unit @ 13 color: ((self colorOf: #cube) alpha: 0.55) text: nil fontSize: 7);
		addChild: (self tintedCaption: ((self run: '  ', cube printString color: (self colorOf: #cube))
			, (self run: ' cells in' color: nil)));
		yourself).
	pane addChild: (ZkfolElements gridRow
		addChild: (ZkfolElements box: (unit * rep) @ 13 color: ((self colorOf: #rate) alpha: 0.55) text: nil fontSize: 7);
		addChild: (self tintedCaption: ((self run: '  ', (rep * cube) printString color: (self colorOf: #rate))
			, (self run: ' cells out' color: nil)));
		yourself).
	^ pane
]

{ #category : 'rendering' }
ZkfolCommitPicture >> merkleDepth [
	"How many hashes a path from a leaf to the root carries: the tree is
	 built over the codeword's columns, so its depth is their log."
	^ (grid codewordLength max: 2) log: 2
]

{ #category : 'rendering' }
ZkfolCommitPicture >> merkleTreeElement [
	"The root as a root of something: a tree over the codeword's columns,
	 drawn to four levels whatever its true depth, the leaves being the
	 columns themselves. One draw opens one leaf and carries the hashes
	 up its path, which is why an opening costs a column and a depth
	 rather than a column alone. The lit path is illustrative: which leaf
	 a draw lands on is the transcript's business."
	| pane layout |
	layout := BlLinearLayout vertical.
	layout alignCenter.
	pane := BlElement new
		layout: layout;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		margin: (BlInsets top: 2 bottom: 2);
		yourself.
	#(1 2 4 8) doWithIndex: [ :count :level |
		| row |
		row := ZkfolElements gridRow.
		1 to: count do: [ :i |
			row addChild: (ZkfolElements
				box: ((64 / count) rounded max: 8) @ 11
				color: ((self colorOf: #draws) alpha: (i = 1 ifTrue: [ 0.65 ] ifFalse: [ 0.18 ]))
				text: nil
				fontSize: 6) ].
		pane addChild: row ].
	pane addChild: (self tintedCaption: ((self run: 'root over ' color: nil)
		, (self run: grid codewordLength printString color: (self colorOf: #rate))
		, (self run: ' columns; a draw carries ' color: nil)
		, (self run: self merkleDepth rounded printString color: (self colorOf: #draws))
		, (self run: ' hashes up its path' color: nil))).
	^ pane
]

{ #category : 'rendering' }
ZkfolCommitPicture >> messageStripElement [
	"The committed column as it really is: its own cells with their own
	 values, as many as fit, the rest elided and counted. This is the
	 trace read off the grid, not a drawing standing in for one."
	| cube shown row |
	cube := grid fullWidth.
	shown := cube min: 14.
	row := ZkfolElements gridRow.
	1 to: shown do: [ :i |
		row addChild: (ZkfolElements
			box: 24 @ 18
			color: ((self colorOf: #cube) alpha: 0.45)
			text: (ZkfolElements compactValue: (grid valueAtRow: 0 position: i) upTo: 3)
			fontSize: 7) ].
	cube > shown ifTrue: [
		row addChild: (ZkfolElements box: 18 @ 18 color: nil text: '...' fontSize: 8).
		row addChild: (ZkfolElements
			box: 24 @ 18
			color: ((self colorOf: #cube) alpha: 0.45)
			text: (ZkfolElements compactValue: (grid valueAtRow: 0 position: cube) upTo: 3)
			fontSize: 7) ].
	^ row
]

{ #category : 'rendering' }
ZkfolCommitPicture >> openingElement [
	"What an opening sends: the drawn columns of the codeword matrix, each
	 a stack of every committed row's cell at that position, and above it
	 the hashes up its path to the root. A few are drawn and the rest
	 counted. Over them, the share of the codeword the draws cover: they
	 are with replacement, so the bar says how many distinct positions to
	 expect and how much of the whole that is, rather than inventing which;
	 which columns are drawn is the transcript's business."
	| draws rows depth total distinct share shown row bar |
	draws := grid columnOpenings.
	rows := grid displayColumns size.
	depth := self merkleDepth rounded.
	total := grid codewordLength.
	distinct := total * (1 - ((total - 1) / total raisedTo: draws)).
	share := distinct / total.
	bar := ZkfolElements gridRow.
	bar addChild: (ZkfolElements box: ((400 * share) rounded max: 2) @ 8 color: ((self colorOf: #draws) alpha: 0.7) text: nil fontSize: 6).
	bar addChild: (ZkfolElements box: (400 - ((400 * share) rounded max: 2)) @ 8 color: ((self colorOf: #rate) alpha: 0.2) text: nil fontSize: 6).
	shown := draws min: 8.
	row := ZkfolElements gridRow.
	1 to: shown do: [ :i |
		| column |
		column := BrVerticalPane new fitContent; margin: (BlInsets left: 3 right: 3); yourself.
		depth timesRepeat: [
			column addChild: (ZkfolElements box: 10 @ 3 color: ((self colorOf: #draws) alpha: 0.35) text: nil fontSize: 6) ].
		rows timesRepeat: [
			column addChild: (ZkfolElements box: 10 @ 5 color: ((self colorOf: #rows) alpha: 0.5) text: nil fontSize: 6) ].
		row addChild: column ].
	draws > shown ifTrue: [
		row addChild: (ZkfolElements box: 18 @ 18 color: nil text: '...' fontSize: 8) ].
	^ BrVerticalPane new
		fitContent;
		margin: (BlInsets top: 2 bottom: 2);
		addChild: bar;
		addChild: (self tintedCaption: ((self run: draws printString color: (self colorOf: #draws))
			, (self run: ' draws, with replacement: about ' color: nil)
			, (self run: (distinct asFloat printShowingDecimalPlaces: 0) color: (self colorOf: #draws))
			, (self run: ' of ' color: nil)
			, (self run: total printString color: (self colorOf: #rate))
			, (self run: ' positions (' , ((share * 100) asFloat printShowingDecimalPlaces: 0) , '%)' color: nil)));
		addChild: (row margin: (BlInsets top: 6); yourself);
		addChild: (self tintedCaption: ((self run: 'each a column of ' color: nil)
			, (self run: rows printString color: (self colorOf: #rows))
			, (self run: ' cells under the ' color: nil)
			, (self run: depth printString color: (self colorOf: #draws))
			, (self run: ' hashes up its path' color: nil)));
		yourself
]

{ #category : 'rendering' }
ZkfolCommitPicture >> run: aString color: aColorOrNil [
	| rt |
	rt := aString asRopedText.
	aColorOrNil ifNotNil: [ rt := rt foreground: aColorOrNil; yourself ].
	^ rt
]

{ #category : 'initialization' }
ZkfolCommitPicture >> setGrid: aGrid [
	grid := aGrid
]

{ #category : 'rendering' }
ZkfolCommitPicture >> stageBlock: aTitle body: anElement facts: aFactName color: aColor [
	"One stage down the page: its title, the thing itself, one sentence
	 on hover, and a click into what it does. Vertical, because these
	 strips are long and the page is not."
	| pane |
	pane := BrVerticalPane new
		fitContent;
		padding: (BlInsets all: 6);
		border: (BlBorder paint: (aColor alpha: 0.25) width: 1);
		margin: (BlInsets top: 2 bottom: 2);
		yourself.
	pane addChild: (self caption: aTitle color: ZkfolPalette mutedTextColor).
	pane addChild: anElement.
	pane addAptitude: (BrGlamorousWithTooltipAptitude content: [
		BrEditor new
			aptitude: BrGlamorousRegularEditorAptitude new;
			text: ((self factsFor: aFactName) at: #hint) asRopedText;
			beReadOnlyWithoutSelection;
			padding: (BlInsets all: 6);
			constraintsDo: [ :c | c horizontal exact: 260. c vertical fitContent ];
			yourself ]).
	^ ZkfolElements make: pane spawn: [ self factsFor: aFactName ]
]

{ #category : 'rendering' }
ZkfolCommitPicture >> stageTitled: aTitle blocks: aBlockList color: aColor caption: aCaption [
	"One stage of the commitment: a title, a row of tinted blocks
	 standing for what it holds, and the count beneath."
	| pane row |
	pane := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		padding: (BlInsets all: 6);
		yourself.
	pane addChild: (self caption: aTitle color: ZkfolPalette mutedTextColor).
	row := ZkfolElements gridRow.
	aBlockList do: [ :each | row addChild: each ].
	pane addChild: row.
	pane addChild: (self caption: aCaption color: aColor).
	^ pane
]

{ #category : 'rendering' }
ZkfolCommitPicture >> stageTitled: aTitle blocks: aBlockList color: aColor caption: aCaptionText facts: aFactName [
	"One stage of the commitment: a title, a row of tinted blocks
	 standing for what it holds, and its caption beneath, whose numbers
	 wear the colour of what they count. Clicking it spawns what the
	 stage actually does, so the picture is a way in rather than the
	 whole of the telling."
	| pane row |
	pane := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		padding: (BlInsets all: 6);
		border: (BlBorder paint: (aColor alpha: 0.25) width: 1);
		margin: (BlInsets all: 2);
		yourself.
	pane addChild: (self caption: aTitle color: ZkfolPalette mutedTextColor).
	row := ZkfolElements gridRow.
	aBlockList do: [ :each | row addChild: each ].
	pane addChild: row.
	pane addChild: (self tintedCaption: aCaptionText).
	pane addAptitude: (BrGlamorousWithTooltipAptitude content: [
		BlTextElement new
			text: ((self factsFor: aFactName) at: #what) asRopedText;
			constraintsDo: [ :c | c horizontal exact: 340 ];
			padding: (BlInsets all: 6);
			yourself ]).
	^ ZkfolElements make: pane spawn: [ self factsFor: aFactName ]
]

{ #category : 'rendering' }
ZkfolCommitPicture >> stages [
	"The chain down the page as (stage -> caption of the step out of it)
	 pairs, the last stage the opening itself. A caption is two short
	 lines, so it fits beside its arrow. Absent the backend's parameters
	 the chain stops where the trace's own knowledge does."
	| chain |
	chain := OrderedCollection new.
	chain add: (self
		stageBlock: 'one committed column, as it is'
		body: self messageStripElement
		facts: 'evals'
		color: (self colorOf: #cube))
			-> ('encode: one pseudo-NTT over the row,', String cr, 'every cell out mixing every cell in').
	grid repFactor ifNil: [ ^ chain ].
	chain add: (self
		stageBlock: 'codeword: the same row, longer'
		body: self lengthBarsElement
		facts: 'encode'
		color: (self colorOf: #rate))
			-> ('commit: hash each column into a tree,', String cr, 'send only its root').
	grid columnOpenings ifNil: [ ^ chain ].
	chain add: (self
		stageBlock: 'the tree the verifier holds the root of'
		body: self merkleTreeElement
		facts: 'commit'
		color: (self colorOf: #draws))
			-> ('open: draw column indices, answer each', String cr, 'with its cells and its path').
	^ chain
		add: (self
			stageBlock: 'the opening the verifier is sent'
			body: self openingElement
			facts: 'open'
			color: (self colorOf: #draws)) -> nil;
		yourself
]

{ #category : 'rendering' }
ZkfolCommitPicture >> tintedCaption: aRopedText [
	"One stage's caption, its numbers each the colour of what they count."
	^ BlTextElement new
		text: ((aRopedText fontName: self unicodeFont) fontSize: 9; yourself);
		margin: (BlInsets top: 3);
		yourself
]

{ #category : 'rendering' }
ZkfolCommitPicture >> totalElement [
	"What the whole trace costs the commitment, each factor keeping the
	 colour it wears in the stages above. The opening's two halves are
	 both counted: the cells the drawn columns carry, and the hashes
	 their paths up the tree carry with them."
	| rows cube rep opens rt times depth |
	rows := grid displayColumns size.
	cube := grid fullWidth.
	rep := grid repFactor.
	opens := grid columnOpenings.
	times := String with: (Character value: 215).
	rt := '' asRopedText.
	rep ifNotNil: [
		rt := rt , (self run: 'encode  ' color: nil).
		rt := rt , (self run: rows printString color: (self colorOf: #rows)).
		rt := rt , (self run: ' ', times, ' ' color: nil).
		rt := rt , (self run: rep printString color: (self colorOf: #rate)).
		rt := rt , (self run: ' ', times, ' ' color: nil).
		rt := rt , (self run: cube printString color: (self colorOf: #cube)).
		rt := rt , (self run: ' = ', (rows * rep * cube) printString, ' cells' color: (self colorOf: #rate)) ].
	opens ifNotNil: [
		depth := self merkleDepth rounded.
		rt := rt , (self run: '      open  ' color: nil).
		rt := rt , (self run: opens printString color: (self colorOf: #draws)).
		rt := rt , (self run: ' ', times, ' ' color: nil).
		rt := rt , (self run: rows printString color: (self colorOf: #rows)).
		rt := rt , (self run: ' = ', (rows * opens) printString, ' cells' color: (self colorOf: #draws)).
		rt := rt , (self run: '  +  ' color: nil).
		rt := rt , (self run: opens printString color: (self colorOf: #draws)).
		rt := rt , (self run: ' ', times, ' ' color: nil).
		rt := rt , (self run: depth printString color: (self colorOf: #draws)).
		rt := rt , (self run: ' = ', (opens * depth) printString, ' hashes' color: (self colorOf: #draws)) ].
	^ BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		padding: (BlInsets top: 10 left: 4 bottom: 2 right: 4);
		addChild: (BlTextElement new text: ((rt fontName: self unicodeFont) fontSize: 11); yourself);
		yourself
]

{ #category : 'rendering' }
ZkfolCommitPicture >> totalFrame [
	"The total in a frame of its own beneath the graph: it sums the
	 stages, it is not one of them."
	^ BrVerticalPane new
		fitContent;
		margin: (BlInsets top: 12);
		border: (BlBorder paint: (ZkfolPalette mutedTextColor alpha: 0.25) width: 1);
		addChild: self totalElement;
		yourself
]

{ #category : 'rendering' }
ZkfolCommitPicture >> unicodeFont [
	"A font family carrying the caption's glyphs, since the default does
	 not render them."
	| fams |
	fams := SkiaFontManager default familyNames.
	(fams includes: 'DejaVu Sans') ifTrue: [ ^ 'DejaVu Sans' ].
	(fams includes: 'Noto Sans') ifTrue: [ ^ 'Noto Sans' ].
	^ BlFontFamily defaultFontFamilyName
]
