Class {
	#name : 'ZkfolJudgementPane',
	#superclass : 'Object',
	#instVars : [
		'judgement'
	],
	#category : 'Zkfol',
	#package : 'Zkfol'
}

{ #category : 'views' }
ZkfolJudgementPane >> equationTreeOn: aView title: aTitle items: aBlock [
	"The shared tree: each node its value beside its term, its side of
	 the equation named, cells hopping to the columns that justify them."
	^ aView columnedTree
		title: aTitle;
		priority: 1;
		items: aBlock;
		children: [ :node | node at: #children ifAbsent: [ #() ] ];
		column: 'Value' text: [ :node |
			| v scoring |
			v := node at: #value.
			scoring := ((node at: #text) includesSubstring: ' = ') and: [ v ~= 0 ].
			scoring
				ifTrue: [ v asRopedText foreground: Color red darker; bold ]
				ifFalse: [ v asRopedText foreground: Color darkGray ] ] width: 90;
		column: 'Side' text: [ :node |
			(node at: #role ifAbsent: [ '' ]) asRopedText foreground: Color gray ] width: 60;
		column: 'Term' text: [ :node | node at: #text ] weight: 3;
		send: [ :node | self hopFrom: node ]
]

{ #category : 'views' }
ZkfolJudgementPane >> formulaLineFor: aNode [
	"An equation inline with the witness pushed through it:
	 the formula, then left = right as evaluated, then the score when
	 it objects. A header line is a branch, bold with its total."
	| rope v left right |
	v := aNode at: #value ifAbsent: [ nil ].
	(aNode at: #header ifAbsent: [ false ]) ifTrue: [
		rope := (aNode at: #text) asRopedText bold foreground: Color black.
		(v notNil and: [ v ~= 0 ]) ifTrue: [
			rope append: (('  (' , v printString , ')') asRopedText
				foreground: Color gray) ].
		^ rope ].
	rope := (aNode at: #text) asRopedText foreground: Color darkGray.
	left := (aNode at: #children ifAbsent: [ #() ])
		detect: [ :c | (c at: #role ifAbsent: [ '' ]) = 'left' ] ifNone: [ nil ].
	right := (aNode at: #children ifAbsent: [ #() ])
		detect: [ :c | (c at: #role ifAbsent: [ '' ]) = 'right' ] ifNone: [ nil ].
	(left notNil and: [ right notNil ]) ifTrue: [
		rope append: ('   ->   ' asRopedText foreground: Color gray).
		rope append: (((left at: #value) printString , ' = ' , (right at: #value) printString)
			asRopedText foreground: (v = 0
				ifTrue: [ Color darkGray ]
				ifFalse: [ Color red darker ])) ].
	(v notNil and: [ v ~= 0 ]) ifTrue: [
		rope append: (('   (' , v printString , ')') asRopedText
			foreground: Color red darker) ].
	^ rope
]

{ #category : 'views' }
ZkfolJudgementPane >> formulaListOn: aView title: aTitle items: aBlock [
	"The formulas inline, one readable line each, hopping as the tree does."
	^ aView columnedList
		title: aTitle;
		priority: 2;
		items: aBlock;
		column: 'Formula' text: [ :node | self formulaLineFor: node ];
		send: [ :node | self hopFrom: node ]
]

{ #category : 'navigation' }
ZkfolJudgementPane >> hopFrom: aNode [
	"A cell reads some column; selecting it hops to that column judged.
	 Anything else spawns as itself."
	^ ((aNode isKindOf: Dictionary)
		and: [ (aNode at: #at ifAbsent: [ nil ]) notNil and: [ judgement notNil ] ])
		ifTrue: [ ZkfolJudgementColumn new
			setJudgement: judgement column: (aNode at: #at); yourself ]
		ifFalse: [ aNode ]
]
