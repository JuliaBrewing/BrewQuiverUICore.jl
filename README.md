# BrewQuiverUICore

[![CI](https://github.com/JuliaBrewing/BrewQuiverUICore.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JuliaBrewing/BrewQuiverUICore.jl/actions/workflows/ci.yml)

The frontend-neutral core of the user interfaces of
[BrewQuiver.jl](https://github.com/JuliaBrewing/BrewQuiver.jl): plain Julia data and
functions, with no terminal or graphics dependencies, shared by the terminal interface
(BrewQuiverTerm.jl) and the graphical one (BrewQuiverApp.jl).

This package is **under development** and not registered. It takes BrewQuiver and its
siblings from GitHub through the `[sources]` of `Project.toml` (Julia 1.11 or later).

Brewing itself is not here: what is useful without an interface belongs in BrewQuiver, and
formulas in BrewingFormulas.jl.

## Sessions

A `Session` holds a quiver being edited, the path of its file, its latest brew, the state of
the brew, the nodes whose results changed in the last step, the warnings of the brew and the
selection.

```julia
using BrewQuiverUICore

s = open_session("bitter.quiver.json")       # or Session(q), or import_recipe("recipe.json")
result(s)[:bottles]                           # the latest BrewResult
status(s)                                     # Brewed() or BrewFailed(exception)
changed(s)                                    # nodes whose results changed in the last step
warnings(s, :kettle)                          # e.g. the vessel is overfilled
select!(s, NodeRef(:kettle))                  # or ArrowRef(:hops => :kettle, 2)
select!(s, Add(), NodeRef(:wort))             # add to the selection
save!(s)                                      # or save!(s, path)
```

- After an edit, the brew is updated with `rebrew!` from the earliest affected nodes,
  falling back to a whole `brew`, on a copy of the previous result: an edit after which the
  quiver no longer brews is refused, and the session keeps its previous quiver and brew. A
  quiver loaded in a state that does not brew opens with `BrewFailed`, and can be edited
  until it brews.
- `changed(s)` lists the nodes whose contents or leftover differ (`≈`) from the previous
  brew, not all the nodes that were recomputed.
- The warnings logged by BrewQuiver (e.g. by the import of a recipe) are collected into
  `warnings(s)`, as `BrewWarning(node, message)`, instead of going to the terminal.
- Arrows are referred to by `ArrowRef(source, destination, index)`: there may be several
  arrows between the same two nodes, kept in order.

## Edit commands

Interfaces change the quiver only through commands, applied with `apply!(s, cmd)`. A command
is a plain value: it validates itself (a refused command throws a `CommandError` with its
description and the reason, and changes nothing), knows the nodes it affects (from which
the brew is updated), describes itself for menus and history lists, and records what
reverts it exactly.

```julia
apply!(s, SetAmount(:pale, 4.8u"kg"))                         # "Set :pale to 4.8 kg"
apply!(s, SetArrowField(:kettle => :wort, 1, :time, 70u"minute"))
apply!(s, Connect(:goldings => :kettle, Transfer(20u"g"; remaining = 5u"minute")))
apply!(s, MoveNode(:kettle, [3, 1]))                          # layout only: no rebrew
sol = apply!(s, Solve(:fermentor => gravity => 1.050u"sg", Amount(:pale, :crystal)))
```

| command | change | reverted by |
|---|---|---|
| `SetInitial(label, initial)` | the initial contents of a node | inverse |
| `SetAmount(label, amount)` | the mass or count of a lot of one ingredient; the volume or mass of a liquor, scaled | inverse |
| `SetIngredient(label, ingredient)` | the ingredient of a lot, of the same kind, keeping its amount | inverse |
| `SetArrow(source, destination, index, arrow)` | one arrow | inverse |
| `SetArrowField(source, destination, index, field, value)` | one field of an arrow, converted to its unit | inverse |
| `Connect(source => destination, arrow = Transfer())` | adds an arrow after the others | inverse (`RemoveArrow` of the last) |
| `RemoveArrow(source, destination, index)` | removes one arrow | inverse if it is the last, else snapshot |
| `Disconnect(source => destination)` | removes all the arrows between two nodes | snapshot |
| `AddNode(label, initial = Contents(); vessel)` | adds a lot or a stage | inverse (`RemoveNode`) |
| `RemoveNode(label)` | removes a node and its arrows | snapshot |
| `RenameNode(old, new)` | renames a node in place (the selection follows) | inverse |
| `SetVessel(label, vessel)` | puts a node in a vessel, or none | inverse |
| `Equip(vessel, equipment)` | attaches a `Vessel`, or removes it (`nothing`) | inverse |
| `SetView(label, key, value)` | a key of the nodeview (`nothing` deletes it); layout only | inverse |
| `MoveNode(label, [x, y])` | the `"position"` of a node; layout only | inverse |
| `Solve(targets, vary)` | `solve!` with the models of the session; returns the `Solution` | snapshot |

An inverse is a command; a snapshot is a copy of the whole quiver, used where an inverse
would have to restore arrows in their order among others, or many values at once. After a
snapshot is restored, `quiver(s)` is a new object: interfaces always get it from the
session.

The rules of the quiver (no cycles, a transformation alone, one drain) are checked by
BrewQuiver before it changes anything; the commands check the rest: the nodes and arrows
exist, amounts and times are not negative, fractions are between 0 and 1, two different
ingredients do not share a name (the files refer to them by name), and the keys of the
nodeview follow the convention below. An edit after which the quiver no longer brews is
refused and reverted.

New commands subtype `EditCommand` and implement `validate`, `affected`, `describe`,
`revert_record`, `BrewQuiverUICore.perform!` and, for layout-only edits, `brew_effect`.

Coming next: undo and redo with transactions, view data, and layout.

## The nodeview convention

`nodeview(q, label)` of BrewQuiver is a `Dict{String, Any}` of free data for interfaces,
saved in the files of quivers. All the frontends use these keys:

| key          | value                                  | meaning                                                 |
|--------------|----------------------------------------|---------------------------------------------------------|
| `"position"` | `[x, y]`, numbers                      | position in abstract layout units (one unit per layer and per slot, `x` growing downstream, `y` downwards); frontends scale it |
| `"collapsed"`| `Bool`                                 | the node is shown collapsed (its details hidden)        |
| `"color"`    | `"#rrggbb"`                            | a color chosen by the user, overriding the color of the beer (from its SRM) |
| `"note"`     | `String`                               | a note of the user about the node                       |

A frontend keeps its own data under its prefix: `"term."` for BrewQuiverTerm,
`"app."` for BrewQuiverApp (e.g. `"app.size" => [w, h]`). Keys without a prefix are
reserved for this convention; propose new ones here.

## License

MIT.
