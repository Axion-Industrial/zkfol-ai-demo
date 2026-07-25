"
Metacello baseline for the Zkfol GToolkit tooling. `load` (fresh / CI) pins the BEAM bridge (Gt4beam v0.19.0), rides AL's tooling in on top via its own dev group so the AL GUI displays alongside the Uair grid, then loads Zkfol. `load: #dev` loads only Zkfol against an already-present, possibly work-in-progress gt4beam and AL, so hacking either never hits a pin.
"
Class {
	#name : 'BaselineOfZkfol',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfZkfol',
	#package : 'BaselineOfZkfol'
}

{ #category : 'baseline' }
BaselineOfZkfol >> baseline: spec [
	<baseline>
	spec
		for: #common
		do: [ spec
				baseline: 'Gt4beam'
				with: [ spec repository: 'github://mariari/ElixirGtBridge:v0.19.0/src' ].
			spec
				baseline: 'AL'
				with: [ spec
						repository: 'github://anoma/anoma-level-elixir-prototype:mariari/zkfol-backend/src';
						loads: #('dev') ].
	"AL rides in via its own dev group: AL-only, no v0.17.3 pin, so the one
	 Gt4beam above is the single source of truth. `load: #dev` drops AL and
	 the bridge entirely and loads only Zkfol against what is already present,
	 so hacking a work-in-progress gt4beam or AL never hits a pin."
			spec package: 'Zkfol'.
			spec
				group: 'default' with: #('Gt4beam' 'AL' 'Zkfol');
				group: 'dev' with: #('Zkfol') ]
]
