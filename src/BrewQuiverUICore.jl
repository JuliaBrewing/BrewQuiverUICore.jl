"""
    BrewQuiverUICore

The frontend-neutral core of the BrewQuiver user interfaces: an editing [`Session`](@ref) of
a quiver of BrewQuiver, with its file, its brew, the selection and (in later versions) the
edit commands, their history with undo and redo, view data and layout. Plain Julia data and
functions, shared by the terminal (BrewQuiverTerm) and graphical (BrewQuiverApp) frontends.
"""
module BrewQuiverUICore

using Unitful
using BrewQuiver
import BeerJSON
using BeerJSON: BeerJSONParser, readjson, writejson
using Logging: Logging, AbstractLogger, LogLevel, Warn, with_logger

include("brewstate.jl")
include("selection.jl")
include("commands.jl")
include("session.jl")
include("apply.jl")

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
export SetInitial, SetAmount, SetIngredient, SetArrow, SetArrowField, Connect, RemoveArrow,
    Disconnect, AddNode, RemoveNode, RenameNode, SetVessel, Equip, SetView, MoveNode, Solve

end # module
