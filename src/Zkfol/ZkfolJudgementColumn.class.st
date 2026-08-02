Class {
	#name : 'ZkfolJudgementColumn',
	#superclass : 'ZkfolJudgementPane',
	#instVars : [
		'x'
	],
	#category : 'Zkfol',
	#package : 'Zkfol'
}

{ #category : 'accessing' }
ZkfolJudgementColumn >> branchNodes [
	"Every branch scored at my column: the zero the one that fired,
	 each carrying its equation trees as children."
	^ (1 to: judgement labels size) collect: [ :b |
		Dictionary new
			at: #text put: (judgement labels at: b);
			at: #value put: ((judgement evals at: b) at: x);
			at: #children put: (judgement trees
				ifNil: [ #() ]
				ifNotNil: [ :ts | (ts at: b) at: x ]);
			yourself ]
]

{ #category : 'views' }
ZkfolJudgementColumn >> gtFormulasFor: aView [
	"Every branch inline at my column: its label bold with its total,
	 then each of its equations with the witness pushed through."
	<gtView>
	judgement ifNil: [ ^ aView empty ].
	^ self formulaListOn: aView title: 'Formulas' items: [
		self branchNodes inject: OrderedCollection new into: [ :acc :branch |
			acc add: (Dictionary new
				at: #header put: true;
				at: #text put: (branch at: #text);
				at: #value put: (branch at: #value);
				yourself).
			(branch at: #children) do: [ :conjunct | acc add: conjunct ].
			acc ] ]
]

{ #category : 'views' }
ZkfolJudgementColumn >> gtJudgedFor: aView [
	"Why this column's cells hold their values: every branch scored
	 here, unfolding to its equations, hopping onward."
	<gtView>
	judgement ifNil: [ ^ aView empty ].
	^ self equationTreeOn: aView title: 'Judged' items: [ self branchNodes ]
]

{ #category : 'printing' }
ZkfolJudgementColumn >> printOn: aStream [
	aStream nextPutAll: 'x=' , x printString , ' judged'
]

{ #category : 'accessing' }
ZkfolJudgementColumn >> setJudgement: aJudgement column: aColumn [
	judgement := aJudgement.
	x := aColumn
]
