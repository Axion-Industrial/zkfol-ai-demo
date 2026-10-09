for module <-
      [
        Examples.ENoDash,
        Examples.EDemo,
        Examples.EMailbox,
        Examples.ECanon,
        Examples.EGate,
        Examples.EGrounding,
        Examples.ETrace,
        Examples.ETools
      ] do
  Module.create(
    Module.concat(module, Test),
    quote(do: use(ExExample.ExUnit, for: unquote(module))),
    __ENV__
  )
end
