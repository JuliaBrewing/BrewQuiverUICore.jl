# The history of a session: the steps applied, with an undo and a redo stack, transactions
# grouping several edits into one step, merging of consecutive small edits of the same
# field, a bounded length, and the marker of the saved state. It lives in memory only.

# the id of the current state
_state(h::History) = isempty(h.undo) ? h.floor : last(h.undo).id

"""
    mergekey(cmd::EditCommand)

The key of what `cmd` sets, for merging consecutive edits into one step of the history (e.g.
typing in a number box), or `nothing` (the default) for commands that are never merged.
Two consecutive commands with the same key are merged when the second comes within the
`merge_window` of the [`History`](@ref) of the first, and no save, undo or redo came
between them: the step keeps what reverts the first, and the description of the last.
Commands with a key must set the whole of what it names, so that the last one alone redoes
the step.
"""
mergekey(::EditCommand) = nothing
mergekey(c::Union{SetInitial, SetAmount, SetIngredient}) = (:initial, c.label)
mergekey(c::SetArrow) = (:arrow, c.source, c.destination, c.index)
mergekey(c::SetArrowField) = (:arrow, c.source, c.destination, c.index, c.field)
mergekey(c::SetView) = (:view, c.label, c.key)
mergekey(c::MoveNode) = (:view, c.label, "position")
mergekey(c::Equip) = (:equipment, c.vessel)
mergekey(c::SetVessel) = (:vessel, c.label)

# record an edit in the history of `s`
function _record!(s::Session, step::Applied, before::Vector{ItemRef})
    h = s.history
    if h.transaction !== nothing
        push!(h.transaction.steps, step)
        return s
    end
    key, now = mergekey(step.command), h.clock()
    top = isempty(h.undo) ? nothing : last(h.undo)
    if key !== nothing && top !== nothing && !h.barrier && top.mergekey == key &&
       now - top.time ≤ h.merge_window
        first_step = only(top.steps)
        top.steps = [Applied(step.command, first_step.record, _union(first_step.affected, step.affected))]
        top.description = describe(step.command)
        top.selection_after = copy(s.selection)
        top.time = now
        top.id = _new_id!(h)          # (a new state)
    else
        _push!(h, HistoryEntry(_new_id!(h), describe(step.command), [step], before,
                               copy(s.selection), key, now))
    end
    h.barrier = false
    return s
end

_new_id!(h::History) = (h.next_id += 1; h.next_id - 1)
_union(a::AllNodes, b) = a
_union(a::AllNodes, ::AllNodes) = a
_union(a, b::AllNodes) = b
_union(a::Vector{Symbol}, b::Vector{Symbol}) = union(a, b)

function _push!(h::History, e::HistoryEntry)
    push!(h.undo, e)
    empty!(h.redo)
    while length(h.undo) > h.limit
        h.floor = popfirst!(h.undo).id
    end
    return h
end

# ---------------------------------------------------------------------------------------
# undo and redo

"""
    canundo(s::Session), canredo(s::Session)

Whether there is a step to undo, or to redo.
"""
canundo(s::Session) = !isempty(s.history.undo) && s.history.transaction === nothing
canredo(s::Session) = !isempty(s.history.redo) && s.history.transaction === nothing
@doc (@doc canundo) canredo

"""
    undo_description(s::Session), redo_description(s::Session)

The description of the step [`undo!`](@ref) or [`redo!`](@ref) would undo or redo (for
menus: "Undo Set :pale to 4.8 kg"), or `nothing`.
"""
undo_description(s::Session) = isempty(s.history.undo) ? nothing : last(s.history.undo).description
redo_description(s::Session) = isempty(s.history.redo) ? nothing : last(s.history.redo).description
@doc (@doc undo_description) redo_description

"""
    undo!(s::Session)

Undoes the last step: reverts its commands, in reverse order, updates the brew from the
nodes they affected, and restores the selection before it. Returns its description, or
`nothing` if there is nothing to undo. Not allowed while a transaction is open.
"""
function undo!(s::Session)
    h = s.history
    _no_transaction(s, "Undo")
    isempty(h.undo) && return nothing
    e = pop!(h.undo)
    _revert_steps!(s, e.steps)
    s.selection = copy(e.selection_before)
    _prune_selection!(s)
    push!(h.redo, e)
    h.barrier = true
    return e.description
end

"""
    redo!(s::Session)

Redoes the last step undone: applies its commands again, updates the brew, and restores the
selection after it. Returns its description, or `nothing` if there is nothing to redo. Not
allowed while a transaction is open.
"""
function redo!(s::Session)
    h = s.history
    _no_transaction(s, "Redo")
    isempty(h.redo) && return nothing
    e = pop!(h.redo)
    done = Applied[]
    try
        for step in e.steps
            push!(done, first(_do!(s, step.command)))
        end
    catch
        # (cannot happen for a history kept by the session; leave it as it was)
        _revert_steps!(s, done)
        push!(h.redo, e)
        rethrow()
    end
    _update_brew_lenient!(s, done)
    e.steps = done
    s.selection = copy(e.selection_after)
    _prune_selection!(s)
    push!(h.undo, e)
    h.barrier = true
    return e.description
end

_no_transaction(s, what) = s.history.transaction === nothing ||
    throw(CommandError(what, "a transaction is open: commit or abort it first"))

# revert applied steps, in reverse order, and update the brew
function _revert_steps!(s::Session, steps::Vector{Applied})
    aff = Symbol[]
    for step in Iterators.reverse(steps)
        aff = _union(aff, _union(step.affected, _record_affected(step.record, s.quiver)))
        _revert!(s, step.record)
    end
    _all_layout(steps) ? empty!(s.changed) : _restore_brew!(s, aff)
    return s
end
_record_affected(r::Inverse, q) = affected(r.command, q)
_record_affected(::Snapshot, q) = AllNodes()
_all_layout(steps) = all(st -> brew_effect(st.command) isa LayoutOnly, steps)

function _update_brew_lenient!(s::Session, steps::Vector{Applied})
    _all_layout(steps) && return (empty!(s.changed); s)
    aff = foldl((a, st) -> _union(a, st.affected), steps; init = Symbol[])
    return _restore_brew!(s, aff)
end

# update the brew, recording a failure (the state was reached before, so it is accepted)
function _restore_brew!(s::Session, aff)
    e = _rebrew!(s, aff)
    e === nothing || (s.status = BrewFailed(e); s.result = nothing; empty!(s.changed); empty!(s.warnings))
    return s
end

# ---------------------------------------------------------------------------------------
# transactions

"""
    begin_transaction!(s::Session, description)

Opens a transaction: the edits applied until [`commit!`](@ref) are one step of the
history, with `description` (e.g. "Move 3 nodes", "Paste"). The edits are applied, and
the brew updated, as they come (e.g. a node dragged across many frames). Transactions
opened inside another one fold into it: only the outermost one makes a step.

See also [`abort!`](@ref), [`transaction`](@ref).
"""
function begin_transaction!(s::Session, description::AbstractString)
    h = s.history
    if h.transaction === nothing
        h.transaction = Transaction(String(description), 1, Applied[], copy(s.selection))
    else
        h.transaction.depth += 1
    end
    return s
end

"""
    commit!(s::Session)

Closes the transaction opened by [`begin_transaction!`](@ref): when it is the outermost
one, its edits become one step of the history (none if there were no edits).
"""
function commit!(s::Session)
    h = s.history
    t = h.transaction
    t === nothing && throw(CommandError("Commit", "there is no transaction open"))
    t.depth -= 1
    t.depth > 0 && return s
    h.transaction = nothing
    isempty(t.steps) && return s
    _push!(h, HistoryEntry(_new_id!(h), t.description, t.steps, t.selection_before,
                           copy(s.selection), nothing, h.clock()))
    h.barrier = true
    return s
end

"""
    abort!(s::Session)

Aborts the open transaction, and those it is in: reverts all its edits, restoring the
quiver, the brew and the selection as they were when it was opened. Nothing goes into the
history.
"""
function abort!(s::Session)
    h = s.history
    t = h.transaction
    t === nothing && throw(CommandError("Abort", "there is no transaction open"))
    h.transaction = nothing
    _revert_steps!(s, t.steps)
    s.selection = t.selection_before
    _prune_selection!(s)
    return s
end

"""
    transaction(f, s::Session, description)

Calls `f()` in a transaction ([`begin_transaction!`](@ref)): its edits are one step of the
history, committed when `f` returns, or aborted if it throws (the exception is rethrown).

```julia
transaction(s, "Move 2 nodes") do
    apply!(s, MoveNode(:mash, [0, 1]))
    apply!(s, MoveNode(:rested, [1, 1]))
end
```
"""
function transaction(f, s::Session, description::AbstractString)
    begin_transaction!(s, description)
    value = try
        f()
    catch
        s.history.transaction === nothing || abort!(s)
        rethrow()
    end
    commit!(s)
    return value
end

"""
    intransaction(s::Session)

Whether a transaction is open.
"""
intransaction(s::Session) = s.history.transaction !== nothing

# ---------------------------------------------------------------------------------------
# saved state, and the list of steps

"""
    isdirty(s::Session)

Whether the session has changes not saved: its state is not the one last saved (or loaded)
with its file. Undoing back to the saved state makes it clean again; a session never saved
(e.g. an imported recipe) is dirty.
"""
isdirty(s::Session) = s.history.saved === nothing || s.history.saved != _state(s.history)

_mark_saved!(h::History) = (h.saved = _state(h); h.barrier = true; h)

"""
    history(s::Session)

The steps of the history of `s`, oldest first, as NamedTuples `(description, done, saved)`:
`done` for the steps that can be undone (the others can be redone), `saved` for the step
whose state was saved. For history lists.
"""
function history(s::Session)
    h = s.history
    done = [(description = e.description, done = true, saved = e.id == h.saved) for e in h.undo]
    undone = [(description = e.description, done = false, saved = e.id == h.saved)
              for e in Iterators.reverse(h.redo)]
    return vcat(done, undone)
end
