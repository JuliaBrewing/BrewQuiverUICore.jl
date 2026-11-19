# Applying commands to a session: validate, record what reverts them, perform, and update
# the brew, refusing (and reverting) the edits after which the quiver no longer brews.

"""
    apply!(s::Session, cmd::EditCommand)

Applies the edit `cmd` to the session `s`:

1. validates it ([`validate`](@ref)); BrewQuiver checks the rules of the quiver as it is
   performed, before changing anything;
2. records what reverts it ([`revert_record`](@ref));
3. performs it, and updates the brew with `rebrew!` from the nodes it [`affected`](@ref)
   (falling back to `brew`), unless it only changes the layout ([`LayoutOnly`](@ref));
4. updates the selection (following a renamed node, dropping removed items).

A refused command throws a [`CommandError`](@ref) and leaves the session as it was. That
includes an edit after which a quiver that brewed no longer does (e.g. a drain with not
enough liquid): the edit is reverted. A quiver that did not brew (loaded so) can be edited
until it does.

Returns what the command gives: the `Solution` of a [`Solve`](@ref), else `nothing`.
"""
apply!(s::Session, cmd::EditCommand) = last(_apply!(s, cmd))

function _apply!(s::Session, cmd::EditCommand)
    before = copy(s.selection)
    step, value = _do!(s, cmd)
    try
        _update_brew!(s, brew_effect(cmd), step.affected, step.record, cmd)
    catch
        s.selection = before
        rethrow()
    end
    _record!(s, step, before)
    return step, value
end

# validate, record and perform a command, and update the selection (not the brew)
function _do!(s::Session, cmd::EditCommand)
    validate(cmd, s.quiver)
    rec = revert_record(cmd, s.quiver)
    aff = affected(cmd, s.quiver)
    value = try
        perform!(s, cmd)
    catch e
        # (BrewQuiver checks before changing anything; a snapshot is restored anyway)
        rec isa Snapshot && _revert!(s, rec)
        e isa CommandError && rethrow()
        e isa Union{ArgumentError, DomainError} || rethrow()
        throw(CommandError(describe(cmd), _message(e)))
    end
    _update_selection!(s, cmd)
    _prune_selection!(s)
    return Applied(cmd, rec, aff), value
end

function _update_brew!(s::Session, ::Rebrews, aff, rec, cmd)
    brewed = isbrewed(s)
    e = _rebrew!(s, aff)
    e === nothing && return s
    if brewed
        _revert!(s, rec)
        throw(CommandError(describe(cmd), "the quiver would no longer brew: " * _message(e)))
    end
    s.status = BrewFailed(e)
    return s
end
_update_brew!(s::Session, ::LayoutOnly, aff, rec, cmd) = (empty!(s.changed); s)

# undo the change of the quiver recorded by `rec` (not the brew)
_revert!(s::Session, rec::Inverse) = (perform!(s, rec.command); s)
_revert!(s::Session, rec::Snapshot) = (s.quiver = deepcopy(rec.quiver); s)

# the selection follows renamed nodes, and the arrows after a removed one
_update_selection!(s::Session, ::EditCommand) = s
function _update_selection!(s::Session, c::RenameNode)
    f(l) = l == c.old ? c.new : l
    s.selection = unique!(ItemRef[_rename_ref(r, f) for r in s.selection])
    return s
end
_rename_ref(r::NodeRef, f) = NodeRef(f(r.label))
_rename_ref(r::ArrowRef, f) = ArrowRef(f(r.source), f(r.destination), r.index)
function _update_selection!(s::Session, c::RemoveArrow)
    same(r) = r isa ArrowRef && r.source == c.source && r.destination == c.destination
    s.selection = ItemRef[same(r) && r.index > c.index ? ArrowRef(r.source, r.destination, r.index - 1) : r
                          for r in s.selection
                          if !(same(r) && r.index == c.index)]
    return s
end
