# Injection templates, as tested

Not yet tested against a live model. `bin/harness probe-injections` runs each template
against the model named by `ZKFOL_MODEL` (default `claude-opus-5-5`) and rewrites this file
with what happened: the model's resolved identifier, whether it tried to send data off the
allowlist, and how many actions the gate blocked.

Do not rely on a template until a row for it appears here, from a run on the day.
