Class {
	#name : 'ZkfolCostPicture',
	#superclass : 'Object',
	#instVars : [
		'grid'
	],
	#category : 'Zkfol-Grid',
	#package : 'Zkfol',
	#tag : 'Grid'
}

{ #category : 'instance creation' }
ZkfolCostPicture class >> on: aGrid [
	^ self new setGrid: aGrid; yourself
]

{ #category : 'rendering' }
ZkfolCostPicture >> asElement [
	"The cost as a picture: the rows bar down the right and the cube bar
	 over the top, each tinted to a factor of the formula, framing the
	 committed strip the pointer grid draws at a tight budget with its
	 ruler flipped beneath the tiles, and the sumcheck formula last. The
	 strip is the grid's own tiles, so a cost cell is the same cell as in
	 the grid and nothing is drawn twice."
	| positions strip column |
	positions := self displayPositions.
	strip := (ZkfolUairPicture on: grid) budget: self budget; rulerAtBottom: true; yourself.
	column := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		padding: (BlInsets all: 8);
		yourself.
	column addChild: (self braceStack: positions).
	column addChild: (self bodyRowWith: strip asElement).
	column addChild: self formulaElement.
	^ column
]

{ #category : 'rendering' }
ZkfolCostPicture >> bodyRowWith: aStripElement [
	"The rows bar hard against the right of the reused strip, so the blue
	 axis sits by the very tiles it counts rather than across the labels."
	| layout |
	layout := BlLinearLayout horizontal.
	^ BlElement new
		layout: layout;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		addChild: aStripElement;
		addChild: self rowsBar;
		yourself
]

{ #category : 'rendering' }
ZkfolCostPicture >> braceStack: aPositions [
	"Two tiers over the strip: the cube bar spanning the whole, and
	 under it the solid real run labelled len beside the faded run
	 labelled pad, their slots (ellipses included) summing to the bar
	 above. The leading spacer clears the row labels; the left padding
	 matches the reused grid container's inset, so the bars sit square
	 over the tiles."
	| len slots realCount padCount top bottom lead |
	len := grid len.
	slots := self regionSlotsOf: aPositions.
	realCount := slots first.
	padCount := slots second.
	lead := grid labelWidth + 2.
	top := ZkfolElements gridRow.
	top addChild: (BlElement new size: lead @ 16; yourself).
	top addChild: (self cubeBar: aPositions).
	bottom := ZkfolElements gridRow.
	bottom addChild: (BlElement new size: lead @ 16; yourself).
	realCount > 0 ifTrue: [
		bottom addChild: (self span: realCount label: ('len ', len printString) color: (Color r: 0.35 g: 0.35 b: 0.35)) ].
	padCount > 0 ifTrue: [
		bottom addChild: (self span: padCount label: ('pad ', (grid fullWidth - len) printString) color: (Color gray)) ].
	^ BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		padding: (BlInsets left: 10);
		addChild: top;
		addChild: bottom;
		yourself
]

{ #category : 'layout' }
ZkfolCostPicture >> budget [
	"How many positions the cost strip draws before it truncates: tight,
	 since the cost is understood from a small cube shown whole, not from
	 exploring a large one."
	^ 16
]

{ #category : 'rendering' }
ZkfolCostPicture >> cubeBar: aPositions [
	"The bar over the whole strip: the cube the sumcheck folds, 2^mu,
	 tinted to the formula's cube factor. It spans every drawn slot,
	 ellipses included, so it reaches the strip's end however it is
	 truncated; the len and pad segments below it partition the same span."
	| n cube cubeColor mu |
	n := aPositions size.
	cube := grid fullWidth.
	cubeColor := Color r: 0.75 g: 0.48 b: 0.19.
	mu := String with: (Character value: 956).
	^ ZkfolElements
		box: ((n * 26) - 2) @ 16
		color: (cubeColor alpha: 0.16)
		text: (('2^', mu, ' = ', cube printString) asRopedText fontName: self unicodeFont; foreground: cubeColor; yourself)
		fontSize: 8
]

{ #category : 'layout' }
ZkfolCostPicture >> displayPositions [
	"The positions the cost strip draws: the grid's truncation at my
	 budget, so a small cube shows whole and a large one shows head, seam,
	 and tail. The reused strip draws the very same positions."
	^ grid shownPositionsUpTo: self budget
]

{ #category : 'rendering' }
ZkfolCostPicture >> formulaElement [
	"The sumcheck cost, both factors named then valued, each tinted to
	 its bar: rows the committed rows down the right, 2^mu the padded cube
	 across the top. Centered under the picture by matching my parent's
	 width. The coloured values carry what the bars already say, so
	 nothing has to spell mu out."
	| rows cube rowsColor cubeColor rt mu times layout |
	rows := grid displayColumns size.
	cube := grid fullWidth.
	rowsColor := Color r: 0.17 g: 0.44 b: 0.7.
	cubeColor := Color r: 0.75 g: 0.48 b: 0.19.
	mu := String with: (Character value: 956).
	times := String with: (Character value: 215).
	rt := 'sumcheck  =  ' asRopedText.
	rt := rt , ('rows' asRopedText foreground: rowsColor; yourself).
	rt := rt , ((' ', times, ' ') asRopedText).
	rt := rt , (('2^', mu) asRopedText foreground: cubeColor; yourself).
	rt := rt , ('  =  ' asRopedText).
	rt := rt , (rows printString asRopedText foreground: rowsColor; yourself).
	rt := rt , ((' ', times, ' ') asRopedText).
	rt := rt , (cube printString asRopedText foreground: cubeColor; yourself).
	rt := rt , (('  =  ', (rows * cube) printString) asRopedText).
	layout := BlLinearLayout horizontal.
	layout alignCenter.
	^ BlElement new
		layout: layout;
		constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ];
		padding: (BlInsets top: 10 left: 4 bottom: 2 right: 4);
		addChild: (BlTextElement new text: ((rt fontName: self unicodeFont) fontSize: 13); yourself);
		yourself
]

{ #category : 'views' }
ZkfolCostPicture >> gtCostFor: aView [
	"The cost picture on the grid's canvas, with its pan and zoom."
	<gtView>
	^ ZkfolElements canvasOn: aView title: 'Cost' priority: 3 node: self
]

{ #category : 'layout' }
ZkfolCostPicture >> regionSlotsOf: aPositions [
	"Tile-slot counts for the real and pad zones with the elided runs
	 counted in: since the real/padding seam is never elided, an ellipsis
	 sits wholly in one zone, the zone of the next shown position. So the
	 two counts sum to every drawn slot, ellipses and all."
	| len size real pad |
	len := grid len.
	size := aPositions size.
	real := 0.
	pad := 0.
	aPositions doWithIndex: [ :p :i |
		| where |
		where := p = #ellipsis
			ifTrue: [ (aPositions copyFrom: i + 1 to: size) detect: [ :q | q ~= #ellipsis ] ifNone: [ grid fullWidth ] ]
			ifFalse: [ p ].
		where <= len ifTrue: [ real := real + 1 ] ifFalse: [ pad := pad + 1 ] ].
	^ { real. pad }
]

{ #category : 'rendering' }
ZkfolCostPicture >> rowsBar [
	"The bar down the right of the strip: the committed rows the sumcheck
	 folds, tinted to the formula's rows factor. Sized and offset to the
	 tile rows exactly (each row 22 high, under the grid container's 10
	 top inset), so it spans the grid, not the ruler or the padding."
	| rowsColor n layout |
	rowsColor := Color r: 0.17 g: 0.44 b: 0.7.
	n := grid displayColumns size.
	layout := BlLinearLayout horizontal.
	layout alignCenter.
	^ BlElement new
		layout: layout;
		margin: (BlInsets top: 10 left: 1 bottom: 1 right: 1);
		constraintsDo: [ :c | c horizontal exact: 46. c vertical exact: n * 22 ];
		background: (rowsColor alpha: 0.16);
		addChild: (BlTextElement new
			text: (('rows ', n printString) asRopedText foreground: rowsColor; fontSize: 8; yourself);
			yourself);
		yourself
]

{ #category : 'rendering' }
ZkfolCostPicture >> rowsBarWidth [
	"The footprint of the left rows bar, so the cube bar over the tiles
	 clears it just as it clears the row labels."
	^ 48
]

{ #category : 'initialization' }
ZkfolCostPicture >> setGrid: aGrid [
	grid := aGrid
]

{ #category : 'rendering' }
ZkfolCostPicture >> span: aCount label: aString color: aColor [
	"A tinted bar the width of aCount tiles, its count centered: the
	 brace that ties a region of the strip to a factor in the formula.
	 Sized to the reused grid cell pitch so it lines up over the tiles."
	^ ZkfolElements
		box: ((aCount * 26) - 2) @ 16
		color: (aColor alpha: 0.16)
		text: (aString asRopedText foreground: aColor; yourself)
		fontSize: 8
]

{ #category : 'rendering' }
ZkfolCostPicture >> unicodeFont [
	"A font family that carries the formula's glyphs, since the default
	 does not render them. Prefer DejaVu Sans, fall back to Noto Sans,
	 else whatever the default is."
	| fams |
	fams := SkiaFontManager default familyNames.
	(fams includes: 'DejaVu Sans') ifTrue: [ ^ 'DejaVu Sans' ].
	(fams includes: 'Noto Sans') ifTrue: [ ^ 'Noto Sans' ].
	^ BlFontFamily defaultFontFamilyName
]
