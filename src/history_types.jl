# The types of the history of a session (see history.jl).

# a command applied to a session, with what reverts it and the nodes it affected
struct Applied
    command::EditCommand
    record::RevertRecord
    affected::Union{AllNodes, Vector{Symbol}}
end

"""
    HistoryEntry

A step of the history: the commands applied (one, several for a transaction or merged
edits), what reverts them, the selection before and after, and a `description` for menus.
"""
mutable struct HistoryEntry
    id::Int
    description::String
    steps::Vector{Applied}
    selection_before::Vector{ItemRef}
    selection_after::Vector{ItemRef}
    mergekey::Union{Nothing, String}   # (the repr of the mergekey of its commands)
    time::Float64
end

mutable struct Transaction
    description::String
    depth::Int
    steps::Vector{Applied}
    selection_before::Vector{ItemRef}
end

"""
    History(; limit = 100, merge_window = 1.5, clock = time)

The history of a [`Session`](@ref), in memory only: at most `limit` steps can be undone.
Consecutive edits of the same field (the same [`mergekey`](@ref)) are merged into one step
when they come within `merge_window` seconds of each other, by the `clock` (a function
giving seconds; replaceable in tests).
"""
mutable struct History{C}
    undo::Vector{HistoryEntry}
    redo::Vector{HistoryEntry}
    limit::Int
    merge_window::Float64
    clock::C
    next_id::Int
    # the id of the state when the undo stack is empty: 0, or the last entry dropped
    floor::Int
    # the id of the state saved, or `nothing` if never saved
    saved::Union{Nothing, Int}
    # no merging into the top entry (after a save, an undo or a redo)
    barrier::Bool
    transaction::Union{Nothing, Transaction}
end

function History(; limit::Integer = 100, merge_window::Real = 1.5, clock = time)
    limit ≥ 1 || throw(ArgumentError("the history needs room for one step at least"))
    return History{typeof(clock)}(HistoryEntry[], HistoryEntry[], limit, merge_window, clock, 1, 0, nothing,
                   true, nothing)
end

