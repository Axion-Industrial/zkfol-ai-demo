Class {
	#name : 'ZkfolJudgementCell',
	#superclass : 'ZkfolJudgementPane',
	#instVars : [
		'title',
		'rows',
		'column'
	],
	#category : 'Zkfol',
	#package : 'Zkfol'
}

{ #category : 'views' }
ZkfolJudgementCell >> gtColumnFor: aView [
	"The witness cells the equations read: this column, row by row,
	 each row wearing its meaning when the judgement knows it."
	<gtView>
	column ifNil: [ ^ aView empty ].
	^ aView columnedList
		title: 'Column';
		priority: 2;
		items: [ column withIndexCollect: [ :v :i | { i. v } ] ];
		column: 'Row' text: [ :pair |
			| names |
			names := judgement ifNotNil: [ judgement rowLabels ].
			(names notNil and: [ pair first <= names size ])
				ifTrue: [ names at: pair first ]
				ifFalse: [ 'C' , pair first printString ] ] width: 110;
		column: 'Value' text: [ :pair | pair second printString ]
]

{ #category : 'views' }
ZkfolJudgementCell >> gtEquationsFor: aView [
	"My branch's clause as the root, unfolding into the equations it
	 lowered to, down to the witness cells."
	<gtView>
	rows ifNil: [ ^ aView empty ].
	^ self equationTreeOn: aView title: 'Equation' items: [ rows ]
]

{ #category : 'views' }
ZkfolJudgementCell >> gtFormulasFor: aView [
	"My equations inline, each with the witness pushed through it."
	<gtView>
	rows ifNil: [ ^ aView empty ].
	^ self formulaListOn: aView title: 'Formulas' items: [
		rows first at: #children ifAbsent: [ #() ] ]
]

{ #category : 'printing' }
ZkfolJudgementCell >> printOn: aStream [
	aStream nextPutAll: (title ifNil: [ 'judgement cell' ])
]

{ #category : 'accessing' }
ZkfolJudgementCell >> setTitle: aTitle rows: somePairs [
	"Each pair: the equation as the paper writes it, and its value at
	 this column. Zero satisfied; anything else the objection."
	title := aTitle.
	rows := somePairs
]

{ #category : 'accessing' }
ZkfolJudgementCell >> setTitle: aTitle rows: somePairs column: witnessCells [
	"Each row: the equation, its two evaluated sides where it is an
	 equality, and its score. The column: the witness cells the
	 equations read, row by row."
	title := aTitle.
	rows := somePairs.
	column := witnessCells
]

{ #category : 'accessing' }
ZkfolJudgementCell >> setTitle: aTitle rows: someTrees column: witnessCells judgement: aJudgement [
	title := aTitle.
	rows := someTrees.
	column := witnessCells.
	judgement := aJudgement
]
