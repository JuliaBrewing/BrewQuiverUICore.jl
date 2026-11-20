# New commands

A new command is a subtype of [`EditCommand`](@ref) implementing the protocol of the
commands. As an example, a command that scales every lot of a quiver by a factor (to brew a
bigger batch), reverted by a snapshot:

```@example extend
using BrewQuiverUICore, BrewQuiver, Unitful, UnitfulBrewing
include(joinpath(pkgdir(BrewQuiverUICore), "docs", "quivers.jl"))
import BrewQuiverUICore: describe, validate, affected, revert_record, perform!, mergekey

struct ScaleBatch <: EditCommand
    factor::Float64
end

describe(c::ScaleBatch) = "Scale the batch by $(c.factor)"
validate(c::ScaleBatch, q::Quiver) =
    c.factor > 0 || throw(CommandError(describe(c), "the factor must be positive"))
affected(::ScaleBatch, ::Quiver) = AllNodes()
revert_record(::ScaleBatch, q::Quiver) = Snapshot(q)
function perform!(q::Quiver, c::ScaleBatch)
    for n in nodes(q)
        isempty(predecessors(q, n)) && !iszero(q[n].initial) && (q[n] = c.factor * q[n].initial)
    end
    return nothing
end

s = Session(single_batch())
apply!(s, ScaleBatch(2))
format(node_summary(s, :bottles).volume), undo_description(s)
```

- `validate(cmd, q)` throws a [`CommandError`](@ref); the rules of the quiver are checked by
  BrewQuiver as it changes it, before changing anything.
- `affected(cmd, q)`: the nodes to rebrew from, as named after the command, or
  [`AllNodes`](@ref)`()`; computed before the command.
- `revert_record(cmd, q)`: an [`Inverse`](@ref) command, or a [`Snapshot`](@ref) of the quiver
  when an inverse would be error-prone; computed before the command.
- `perform!(q, cmd)`: the change (or `perform!(s::Session, cmd)` when it needs the session,
  e.g. its models, as [`Solve`](@ref) does).
- `brew_effect(cmd)`: [`LayoutOnly`](@ref)`()` for commands that do not change the brew.
- `mergekey(cmd)`: for commands typed into, a key naming what they set, all of it.

Test a new command as the package does: applying it and its record gives the same file
(`writejson`) and the same brew as before, and undo and redo in random sequences keep these
invariants.
