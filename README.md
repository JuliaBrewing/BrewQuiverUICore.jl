# BrewQuiverUICore

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaBrewing.github.io/BrewQuiverUICore.jl/dev/) [![CI](https://github.com/JuliaBrewing/BrewQuiverUICore.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JuliaBrewing/BrewQuiverUICore.jl/actions/workflows/ci.yml)

The frontend-neutral core of the user interfaces of
[BrewQuiver.jl](https://github.com/JuliaBrewing/BrewQuiver.jl): plain Julia data and
functions, with no terminal or graphics dependencies, shared by the terminal interface
(BrewQuiverTerm.jl) and the graphical one (BrewQuiverApp.jl).

The [documentation](https://JuliaBrewing.github.io/BrewQuiverUICore.jl/dev/) has the
concepts, guides for editing, view data and writing a frontend, and the API reference.

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
| `SetTemperature(label, temperature)` | the temperature of a lot of liquor (water) | inverse |
| `SetWaterProfile(label, profile)` | the `WaterProfile` of a lot of water, keeping its water and temperature | inverse |
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

## Undo and redo

Each session has a `History`, in memory only (it is not written to the files), with an undo
and a redo stack of steps. A step is a command, a transaction of several, or merged edits.

```julia
undo_description(s)          # "Set :pale to 4.8 kg", for a menu "Undo Set :pale to 4.8 kg"
undo!(s); redo!(s)           # return the description, or nothing
canundo(s), canredo(s)
history(s)                   # [(description, done, saved), ...], oldest first
isdirty(s)                   # changes not saved?
```

- **Undo** reverts the commands of the step in reverse order, with their records (inverse
  commands or snapshots), updates the brew from the nodes they affected, and restores the
  selection before the step. **Redo** applies the commands again and restores the selection
  after it. A new edit clears the redo stack.
- **Layout-only** steps (`MoveNode`, `SetView`) are undone and redone without brewing.
- **Transactions** group several edits into one step: `begin_transaction!(s, description)`,
  `commit!(s)`, `abort!(s)`, or `transaction(s, description) do ... end`, which aborts when
  its block throws. The edits are applied, and brewed, as they come (a node dragged across
  many frames); `abort!` reverts them all, restoring the quiver, the brew and the selection
  of the beginning. Transactions opened inside another fold into the outermost; an empty one
  leaves no step. Undo and redo are refused while a transaction is open.
- **Merging**: an edit merges into the step on top of the undo stack when both have the
  same `mergekey(cmd)` (the same aspect of the same item: the amount, ingredient,
  temperature or water profile of a lot, a field of an arrow, a key of a nodeview, the
  position of a node, a field of the equipment of a vessel), it comes within `merge_window` seconds (1.5 by default) of the previous one,
  and no save, undo or redo came between them. Typing 4.6, 4.7, 4.8 in an amount box makes
  one step, "Set :pale to 4.8 kg", undone back to the amount before the first.
- **Bounded**: `History(; limit = 100)` keeps the last `limit` steps.
- **Saved marker**: saving (or opening a file) marks the current state; `isdirty(s)` is
  false only in that state, so undoing back to it makes the session clean again. When the
  saved state can no longer be reached (its step dropped from the redo stack by a new edit,
  or from the bottom of a bounded history), the session stays dirty until saved. A session
  never saved (a new quiver, an imported recipe) is dirty.

```julia
s = open_session("bitter.quiver.json"; history = History(; limit = 200, merge_window = 1.0))
transaction(s, "Move 2 nodes") do
    apply!(s, MoveNode(:mash, [0, 1]))
    apply!(s, MoveNode(:rested, [1, 1]))
end
```

## Ingredients

```julia
set_library!(s, "my_ingredients.json")       # or a Library; or open_session(path; library)
catalog(s)                                   # name => ingredient: the quiver's, the library's, salts and acids
i = find_ingredient(s, "munich")             # by name, ignoring case, or the only one containing it
apply!(s, AddNode(:munich, i => 0.5u"kg"))
apply!(s, AddNode(:gypsum, find_ingredient(s, "gypsum") => 4u"g"))
```

The catalog holds the ingredients of the lots of the quiver, those of the `Library` of the
session (BrewQuiver's, from BeerJSON documents; not saved with the quiver), and the salts
and acids of `WATER_AGENTS`; a name stands for one ingredient, the quiver's first, since the
files of quivers refer to ingredients by name.

## Models, inventory and export

```julia
apply!(s, set_model(s, :bitterness, Rager()))   # undoable; MODEL_CHOICES lists the models
inventory_rows(s)                               # what the brew needs, with the library's stock
consume_stock!(s); save_library(s, "my_ingredients.json")
export_recipes(s, "recipes.json")               # BeerJSON, a recipe per product
```

## Preferred units

```julia
set_units!(s, load_units())        # ~/.config/brewquiver/units.toml, shared by the frontends
UnitPreferences(fermentable = u"lb", hop = u"oz", volume = u"gal", temperature = u"°F")
format(s, x; role = :hop)          # shown in the preferred unit of the role
parse_value(s, "10", current; role = :fermentable)   # a bare number in the unit shown
```

Each role (malts, hops, cultures, salts, other masses, volumes, temperatures, gravities,
colors, absorptions, rates) has its unit, from `UNIT_CHOICES`; masses and volumes may be
`:auto` (kg or g, L or mL by size). A number typed without a unit is in the unit shown, or
for an empty field in the preferred unit of its role; no unit is guessed from its size.

## View data

Plain data for the frontends to render, with Unitful quantities (formatted by the frontend
with `format`), `missing` where a value does not apply:

```julia
format(1.0523u"sg")              # "1.052 sg"; also "23.1 L", "300 g", "5.2%", "35 IBU", "4.0 L/h"
node_summaries(s)                # NodeSummary per node: kind, results, color, warnings, changed, selected
node_summary(s, :wort).gravity   # 1.048 sg
vessel_groups(s)                 # [nothing => lots, :mashtun => [...], :kettle => [...], ...]
results_table(s)                 # (header, rows) of the results of all the nodes
node_detail(s, :kettle)          # summary, initial, contents, leftover, incoming and outgoing arrows
solid_rows(c), liquor_rows(c), mineral_rows(c)   # the parts of contents, as rows
arrow_summaries(s)               # ArrowSummary per arrow: kind, parameters, duration, moved, released
fields(Boil())                   # FieldSpecs for forms: label, value, units, fraction, optional
timeline_rows(s; start = 8u"hr") # when each node is filled, ready and emptied
vessel_bookings(s)               # when each vessel is busy, the makespan and the overlaps
solution_rows(apply!(s, Solve(...)))
```

- `format` shows each unit with its decimals (`display_digits(unit)`, three significant
  digits by default), masses below 1 kg in g and volumes below 1 L in mL
  (`display_unit`); compound units as "mg/L".
- `node_color(s, label)` is the nodeview `"color"` of the user, else the color of the beer
  from its SRM (`srm_hex` of BrewingFormulas), else that of the malt of a lot, else
  `nothing` (water, hops), for the frontend's default.
- The mash pH is given for the nodes with grain still to mash, with its warnings (e.g. a
  dark grain without its distilled water pH) among those of the node.
- `parse_value(text)` reads what a user types, the inverse of `format`: `"4.8 kg"`,
  `"95%"`, `"70 min"`, `"4 L/h"`, `"1.050 sg"`, any unit of Unitful or UnitfulBrewing (with
  aliases for symbols hard to type: `70 C`, `158 F`, `12 P`), a
  plain number, a timing (`"10 min remaining"`, `"at 70 min"`), or nothing (`""`, `"–"`),
  for the text boxes of the frontends; the commands check and convert the value.
- `SetEquipmentField(vessel, field, value)` edits one field of the equipment of a vessel,
  for forms built with `fields(equipment(q, vessel))`.

## Layout

```julia
layout(q)          # Dict(label => [x, y]): a layered layout of a quiver
layout!(s)         # writes it into the nodeviews, as one undoable step "Arrange the nodes"
positions(s)       # the stored positions, and the layout for the nodes without one
crossings(q, pos)  # the arrows that cross, to assess a layout
```

`x` is the layer of a node, the length of the longest path from a source, so that every
arrow goes from left to right; a lot sits in the layer just before its first destination
(the hops by the kettle). `y` is the slot in the layer, from the top: the nodes of a layer
are ordered by the barycenters of their neighbours in the layers before and after,
sweeping back and forth, with the nodes of the same vessel kept together and the vessels in
their order. A single batch comes out along one row, with no crossings. Frontends draw from
`positions(s)`, so that a quiver without positions (an imported recipe) is drawn laid out,
and scale the abstract units to their own.

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
