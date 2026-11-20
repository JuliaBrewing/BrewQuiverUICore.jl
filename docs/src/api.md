# API reference

```@meta
CurrentModule = BrewQuiverUICore
```

```@docs
BrewQuiverUICore
```

```@contents
Pages = ["api.md"]
Depth = 2:2
```

## Brew state

```@docs
AbstractBrewStatus
Brewed
BrewFailed
isbrewed
BrewWarning
```

## Selection

```@docs
ItemRef
NodeRef
ArrowRef
isvalid_ref
```

## Sessions

```@docs
Session
open_session
import_recipe
recipe_names
save!
brew!
quiver
result
status
changed
warnings
filepath
models
selection
select!
Add
deselect!
clear_selection!
```

## Commands

```@docs
EditCommand
CommandError
apply!
validate
affected
describe
revert_record
brew_effect
Rebrews
LayoutOnly
AllNodes
RevertRecord
Inverse
Snapshot
SetInitial
SetAmount
SetIngredient
SetTemperature
SetWaterProfile
SetArrow
SetArrowField
Connect
RemoveArrow
Disconnect
AddNode
RemoveNode
RenameNode
SetVessel
Equip
SetEquipmentField
SetView
MoveNode
Solve
```

## History

```@docs
History
undo!
redo!
canundo
canredo
undo_description
redo_description
history
isdirty
mergekey
begin_transaction!
commit!
abort!
transaction
intransaction
```

## View data

```@docs
format
display_digits
display_unit
parse_value
input_unit
NodeSummary
node_summary
node_summaries
RESULT_COLUMNS
node_color
vessel_groups
results_table
ArrowSummary
arrow_summary
arrow_summaries
FieldSpec
fields
solid_rows
liquor_rows
mineral_rows
node_detail
timeline_rows
vessel_bookings
solution_rows
```

## Layout

```@docs
layout
layout!
positions
crossings
```

## Ingredients and inventory

```@docs
WATER_AGENTS
library
set_library!
catalog
find_ingredient
inventory_rows
consume_stock!
save_library
export_recipes
```

## Models

```@docs
SetModels
MODEL_CHOICES
models_in_use
set_model
```
