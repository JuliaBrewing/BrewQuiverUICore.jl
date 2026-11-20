# Editing, undo and redo

```@setup edit
using BrewQuiverUICore, BrewQuiver, Unitful, UnitfulBrewing
include(joinpath(pkgdir(BrewQuiverUICore), "docs", "quivers.jl"))
```

## Applying commands

```@example edit
s = Session(single_batch())
apply!(s, SetAmount(:pale, 4.8u"kg"))
apply!(s, SetArrowField(:kettle => :wort, 1, :time, 70u"minute"))
apply!(s, SetArrowField(:cascade, :kettle, 2, :amount, 20u"g"))
[h.description for h in history(s)]
```

The commands, and how each is reverted:

| command | change | reverted by |
|---|---|---|
| [`SetInitial`](@ref)`(label, initial)` | the initial contents of a node | inverse |
| [`SetAmount`](@ref)`(label, amount)` | the mass or count of a lot of one ingredient; the volume or mass of a liquor, scaled | inverse |
| [`SetIngredient`](@ref)`(label, ingredient)` | the ingredient of a lot, of the same kind | inverse |
| [`SetTemperature`](@ref)`(label, temperature)` | the temperature of a lot of liquor | inverse |
| [`SetWaterProfile`](@ref)`(label, profile)` | the water profile of a lot of water | inverse |
| [`SetArrow`](@ref)`(source, destination, index, arrow)` | one arrow | inverse |
| [`SetArrowField`](@ref)`(source, destination, index, field, value)` | one field of an arrow, converted to its unit | inverse |
| [`Connect`](@ref)`(source => destination, arrow)` | adds an arrow after the others | inverse |
| [`RemoveArrow`](@ref)`(source, destination, index)` | removes one arrow | inverse if the last, else snapshot |
| [`Disconnect`](@ref)`(source => destination)` | removes all the arrows between two nodes | snapshot |
| [`AddNode`](@ref)`(label, initial; vessel)` | adds a lot or a stage | inverse |
| [`RemoveNode`](@ref)`(label)` | removes a node and its arrows | snapshot |
| [`RenameNode`](@ref)`(old, new)` | renames a node in place | inverse |
| [`SetVessel`](@ref)`(label, vessel)` | puts a node in a vessel, or none | inverse |
| [`Equip`](@ref)`(vessel, equipment)` | attaches or removes the equipment of a vessel | inverse |
| [`SetEquipmentField`](@ref)`(vessel, field, value)` | one field of the equipment of a vessel | inverse |
| [`SetView`](@ref)`(label, key, value)` | a key of the nodeview; layout only | inverse |
| [`MoveNode`](@ref)`(label, [x, y])` | the position of a node; layout only | inverse |
| [`Solve`](@ref)`(targets, vary)` | `solve!` for targets; returns the solution | snapshot |

A refused command says why, and changes nothing, the selection included:

```@example edit
for cmd in (Connect(:bottles => :pale), SetArrowField(:kettle, :wort, 1, :time, 3u"kg"),
            RenameNode(:kettle, :wort))
    try
        apply!(s, cmd)
    catch e
        println(sprint(showerror, e))
    end
end
```

## Undo and redo

```@example edit
undo_description(s), canredo(s)
```

```@example edit
undo!(s); undo!(s)
redo_description(s)
```

```@example edit
[(h.done ? "done:   " : "undone: ") * h.description for h in history(s)]
```

Undo and redo restore the brew, from the nodes the step affected, and the selection of
before or after the step. A new edit clears the redo stack.

## Transactions

Edits made in a transaction are one step. They are applied, and brewed, as they come, so
that an interface shows them live (a node dragged); aborting reverts them all.

```@example edit
transaction(s, "Brew a stronger beer") do
    apply!(s, SetAmount(:pale, 5u"kg"))
    apply!(s, SetAmount(:crystal, 0.4u"kg"))
end
undo_description(s)
```

[`begin_transaction!`](@ref), [`commit!`](@ref) and [`abort!`](@ref) do the same in steps,
e.g. across the frames of a drag, with Escape to abort. The do-block form aborts when its
block throws, including when an edit in it is refused. Transactions opened inside another
fold into the outermost; undo and redo are refused while one is open.

## Merging

Typing 4.6, 4.7, 4.8 into a number box applies three commands; they make one step, because
consecutive commands with the same [`mergekey`](@ref) (the same aspect of the same item)
merge when they come within the `merge_window` of the [`History`](@ref) (1.5 s by default)
and no save, undo or redo came between them. The step keeps what reverts the first, and
the description and command of the last.

```@example edit
s = Session(single_batch())
for m in (4.6, 4.7, 4.8)
    apply!(s, SetAmount(:pale, m * u"kg"))
end
[h.description for h in history(s)]
```

## The saved marker

```@example edit
file = joinpath(mktempdir(), "bitter.quiver.json")
save!(s, file)
apply!(s, SetAmount(:crystal, 0.4u"kg"))
a = isdirty(s)
undo!(s)
a, isdirty(s)
```

A session is clean only in the state it was last saved or opened in; when that state can
no longer be reached (its step dropped by a new edit, or by the bounded length of the
history), it stays dirty until saved. A session never saved, such as an imported recipe, is
dirty.

## Ingredients

The [`catalog`](@ref) of a session holds the ingredients that can be added: those of its
quiver, those of its [`library`](@ref) (BeerJSON documents of ingredients, see
[`set_library!`](@ref)), and the salts and acids of [`WATER_AGENTS`](@ref).
[`find_ingredient`](@ref) finds one by name, or by a part of it when only one matches.

```@example edit
apply!(s, AddNode(:gypsum, find_ingredient(s, "gyps") => 4u"g"))
apply!(s, Connect(:gypsum => :mash))
format(profile(result(s)[:mash]).sulfate)
```

## Models, inventory and export

The models of BrewingFormulas a session brews with are changed by a command, so that the
change can be undone ([`SetModels`](@ref), [`set_model`](@ref), [`MODEL_CHOICES`](@ref)):

```@example edit
apply!(s, set_model(s, :bitterness, Rager()))
models_in_use(s).bitterness, format(node_summary(s, :wort).ibu)
```

[`inventory_rows`](@ref) compares what the brew needs with the stock of the library,
[`consume_stock!`](@ref) takes it from the stock (not undoable: it changes the library, saved
with [`save_library`](@ref)), and [`export_recipes`](@ref) writes the brew as BeerJSON
recipes.

```@example edit
set_library!(s, Library())     # (an empty library: nothing in stock)
[(r.name, r.needed isa Real ? "$(Int(r.needed)) ×" : format(r.needed), r.short ? "short" : "")
 for r in inventory_rows(s)]
```
