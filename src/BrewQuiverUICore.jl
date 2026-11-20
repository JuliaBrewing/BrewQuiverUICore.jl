"""
    BrewQuiverUICore

The frontend-neutral core of the BrewQuiver user interfaces: an editing [`Session`](@ref) of
a quiver of BrewQuiver, with its file, its brew, the selection and (in later versions) the
edit commands, their history with undo and redo, view data and layout. Plain Julia data and
functions, shared by the terminal (BrewQuiverTerm) and graphical (BrewQuiverApp) frontends.
"""
module BrewQuiverUICore

using Unitful
using UnitfulBrewing
using BrewingFormulas
using BrewQuiver
import Printf
import BeerJSON
using BeerJSON: BeerJSONParser, readjson, writejson
using Logging: Logging, AbstractLogger, LogLevel, Warn, with_logger

include("brewstate.jl")
include("selection.jl")
include("commands.jl")
include("history_types.jl")
include("session.jl")
include("apply.jl")
include("history.jl")
include("format.jl")
include("parse.jl")
include("views.jl")
include("layout.jl")
include("catalog.jl")

# brew state
export AbstractBrewStatus, Brewed, BrewFailed, isbrewed, BrewWarning

# selection
export ItemRef, NodeRef, ArrowRef, isvalid_ref

# sessions
export Session, open_session, import_recipe, recipe_names, save!, brew!
export quiver, result, status, changed, warnings, filepath, models
export selection, select!, Add, deselect!, clear_selection!

# commands
export EditCommand, CommandError, apply!
export validate, affected, describe, revert_record, brew_effect
export Rebrews, LayoutOnly, AllNodes, RevertRecord, Inverse, Snapshot
export SetInitial, SetAmount, SetIngredient, SetTemperature, SetWaterProfile, SetArrow,
    SetArrowField, Connect, RemoveArrow,
    Disconnect, AddNode, RemoveNode, RenameNode, SetVessel, Equip, SetEquipmentField, SetView,
    MoveNode, Solve

# history
export History, undo!, redo!, canundo, canredo, undo_description, redo_description, history,
    isdirty, mergekey, begin_transaction!, commit!, abort!, transaction, intransaction

# view data
export format, display_digits, display_unit, parse_value
export NodeSummary, node_summary, node_summaries, RESULT_COLUMNS, node_color, vessel_groups,
    results_table, ArrowSummary, arrow_summary, arrow_summaries, FieldSpec, fields,
    solid_rows, liquor_rows, mineral_rows, node_detail, timeline_rows, vessel_bookings,
    solution_rows

# layout
export layout, layout!, positions, crossings

# ingredients
export WATER_AGENTS, library, set_library!, catalog, find_ingredient

end # module
