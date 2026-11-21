# Edit commands: the changes of a quiver an interface makes, each a plain value that
# validates itself, knows the nodes it affects, describes itself, and records what it needs
# to be reverted exactly.

"""
    EditCommand

Supertype of the edits of a quiver in a [`Session`](@ref), applied with [`apply!`](@ref).
Each command implements:

- [`validate`](@ref)`(cmd, q)`: throws a [`CommandError`](@ref) if `cmd` cannot be applied
  to `q`, changing nothing;
- [`affected`](@ref)`(cmd, q)`: the nodes to rebrew from after it (computed before it);
- [`describe`](@ref)`(cmd)`: a short description, e.g. "Set :pale to 4.8 kg";
- [`revert_record`](@ref)`(cmd, q)`: what reverts it exactly (computed before it): an
  [`Inverse`](@ref) command or a [`Snapshot`](@ref) of the quiver;
- [`brew_effect`](@ref)`(cmd)`: [`Rebrews`](@ref) or [`LayoutOnly`](@ref);
- `perform!(q, cmd)` (internal): the change itself.
"""
abstract type EditCommand end

"""
    CommandError(description, message)

A command was refused: `description` is that of the command, `message` why. The session is
left as it was.
"""
struct CommandError <: Exception
    description::String
    message::String
end
Base.showerror(io::IO, e::CommandError) = print(io, e.description, ": ", e.message)

_refuse(cmd::EditCommand, msg::AbstractString) = throw(CommandError(describe(cmd), msg))

# The effect of a command on the brew: Rebrews or LayoutOnly
abstract type BrewEffect end

"""
    Rebrews()

The [`brew_effect`](@ref) of the commands that change the brew (the default): it is updated
after them.
"""
struct Rebrews <: BrewEffect end

"""
    LayoutOnly()

The [`brew_effect`](@ref) of the commands that only change the layout (the positions of the
nodes, their view): the brew is kept, and nothing is marked changed.
"""
struct LayoutOnly <: BrewEffect end

"""
    brew_effect(cmd::EditCommand)

[`Rebrews`](@ref)`()` (the default) or [`LayoutOnly`](@ref)`()`.
"""
brew_effect(::EditCommand) = Rebrews()

"""
    AllNodes()

What [`affected`](@ref) returns for a command that may change any node: the quiver is
brewed again entirely.
"""
struct AllNodes end

"""
    affected(cmd::EditCommand, q::Quiver)

The labels of the nodes from which the brew is updated after `cmd` (with `rebrew!`), as
they are named after it, or [`AllNodes`](@ref)`()`. Computed on `q` before `cmd`.
"""
function affected end

"""
    describe(cmd::EditCommand)

A short description of `cmd`, for menus ("Undo Set :pale to 4.8 kg") and history lists.
"""
function describe end

"""
    validate(cmd::EditCommand, q::Quiver)

Throws a [`CommandError`](@ref) if `cmd` cannot be applied to `q`. The rules of the
quiver itself (no cycles, a transformation alone, one drain) are checked by BrewQuiver as
the command is performed, before anything changes.
"""
validate(::EditCommand, ::Quiver) = nothing

"""
    RevertRecord

What reverts a command exactly ([`revert_record`](@ref)): an [`Inverse`](@ref) command or
a [`Snapshot`](@ref) of the quiver.
"""
abstract type RevertRecord end

"""
    Inverse(cmd)

Reverts a command by applying the command `cmd`, e.g. setting back the old amount of a lot.
"""
struct Inverse{C <: EditCommand} <: RevertRecord
    command::C
end

"""
    Snapshot(q)

Reverts a command by restoring a copy of the whole quiver `q` as it was before. Used for
the edits whose inverse is error-prone: removing a node with its arrows, removing an arrow
among others, solving.
"""
struct Snapshot <: RevertRecord
    quiver::Quiver
    Snapshot(q::Quiver) = new(deepcopy(q))
end

"""
    revert_record(cmd::EditCommand, q::Quiver)

What reverts `cmd` applied to `q`: an [`Inverse`](@ref) command or a [`Snapshot`](@ref) of
`q`. Computed on `q` before `cmd`.
"""
function revert_record end

# the change itself, on the quiver of the session (`Solve` needs the models)
perform!(s, cmd::EditCommand) = perform!(s.quiver, cmd)

# ---------------------------------------------------------------------------------------
# formatting, for the descriptions

function _fmt(x::Unitful.Quantity)
    v = round(ustrip(x); sigdigits = 4)
    return string(isinteger(v) ? Int(v) : v, " ", unit(x))
end
_fmt(x::Real) = (v = round(x; sigdigits = 4); string(isinteger(v) ? Int(v) : v))
_fmt(x::Bool) = string(x)
_fmt(::Nothing) = "nothing"
_fmt(x::Symbol) = ":$x"
_fmt(x) = string(x)

_fmt_contents(c::Contents) = _fmt_contents(c.liquor, c.solids)
_fmt_contents(l, solids) =
    if isempty(solids) && iszero(l)
        "nothing"
    elseif isempty(solids)
        _fmt(uconvert(u"L", volume(l)))
    elseif iszero(l) && length(solids) == 1 && only(solids) isa Portion
        p = only(solids)
        p.amount isa Real ? "$(_fmt(p.amount)) × $(p.ingredient.name)" :
                            "$(_fmt(uconvert(_mass_unit(p.amount), p.amount))) $(p.ingredient.name)"
    else
        "new contents"
    end
_mass_unit(m) = m < 1u"kg" ? u"g" : u"kg"

_edge(s, d, i) = i == 1 ? ":$s => :$d" : ":$s => :$d #$i"
_arrow_name(a) = string(nameof(typeof(a)))
_field_name(f::Symbol) = replace(String(f), "_" => " ")

# ---------------------------------------------------------------------------------------
# checks

_check_node(cmd, q, label) = haskey(q, label) || _refuse(cmd, "there is no node labelled :$label")
_check_free(cmd, q, label) =
    haskey(q, label) && _refuse(cmd, "there is already a node labelled :$label")
_check_label(cmd, label) = isempty(String(label)) && _refuse(cmd, "a label cannot be empty")
function _check_arrow(cmd, q, s, d, i)
    _check_node(cmd, q, s)
    _check_node(cmd, q, d)
    n = d in successors(q, s) ? length(q[s => d]) : 0
    n == 0 && _refuse(cmd, "there is no arrow from :$s to :$d")
    1 ≤ i ≤ n || _refuse(cmd, "there are $n arrows from :$s to :$d, not $i")
end

# the files of quivers refer to ingredients by name: two different ones cannot share a name
function _check_names(cmd, q, label, c::Contents)
    for p in c.solids
        p isa Portion || continue
        for n in nodes(q)
            n == label && continue
            for o in q[n].initial.solids
                o isa Portion && o.ingredient.name == p.ingredient.name && o.ingredient != p.ingredient &&
                    _refuse(cmd, "the lot :$n has another ingredient named $(repr(p.ingredient.name))")
            end
        end
    end
end

_contents(c::Contents) = c
_contents(x) = try
    Contents(x)
catch e
    e isa MethodError || rethrow()
    throw(ArgumentError("the contents of a node are `Contents`, a liquor or `ingredient => amount`, not $x"))
end

# ---------------------------------------------------------------------------------------
# lots

"""
    SetInitial(label, initial)

Sets the initial contents of the node `label`: `Contents`, a liquor (`water(16u"L")`) or
`ingredient => amount`. Reverted by its [`Inverse`](@ref).
"""
struct SetInitial <: EditCommand
    label::Symbol
    initial::Contents
end
SetInitial(label::Symbol, x) = SetInitial(label, _contents(x))

describe(c::SetInitial) = "Set :$(c.label) to $(_fmt_contents(c.initial))"
function validate(c::SetInitial, q::Quiver)
    _check_node(c, q, c.label)
    _check_names(c, q, c.label, c.initial)
end
affected(c::SetInitial, q::Quiver) = [c.label]
revert_record(c::SetInitial, q::Quiver) = Inverse(SetInitial(c.label, q[c.label].initial))
perform!(q::Quiver, c::SetInitial) = (q[c.label] = c.initial; nothing)

"""
    SetAmount(label, amount)

Sets the amount of the lot `label`: the mass or count of its ingredient (a lot of one
ingredient), or the volume or mass of its liquor (water, a salt, an acid), scaled with
everything in it (its minerals, ...). Reverted by its [`Inverse`](@ref).
"""
struct SetAmount <: EditCommand
    label::Symbol
    amount::Any            # (any value typed: what is not an amount is refused)
end

describe(c::SetAmount) = "Set :$(c.label) to $(_fmt(c.amount))"
function validate(c::SetAmount, q::Quiver)
    _check_node(c, q, c.label)
    _with_amount(c, q[c.label].initial)
    return nothing
end
affected(c::SetAmount, q::Quiver) = [c.label]
revert_record(c::SetAmount, q::Quiver) = Inverse(SetInitial(c.label, q[c.label].initial))
perform!(q::Quiver, c::SetAmount) = (q[c.label] = _with_amount(c, q[c.label].initial); nothing)

function _with_amount(c::SetAmount, x::Contents)
    c.amount isa Union{Unitful.Quantity, Real} && !(c.amount isa Bool) ||
        _refuse(c, "an amount is a mass, a volume or a count, e.g. 4.5 kg, 16 L, 2")
    _negative(c.amount) && _refuse(c, "an amount cannot be negative")
    if iszero(x.liquor) && length(x.solids) == 1 && only(x.solids) isa Portion
        p = only(x.solids)
        return _lot(Portion(p.ingredient, _portion_amount(c, c.amount); timing = p.timing))
    elseif isempty(x.solids) && !iszero(x.liquor)
        old = _liquor_amount(c, x, c.amount)
        iszero(old) && _refuse(c, "there is nothing to scale in :$(c.label): set its contents instead")
        return float(uconvert(NoUnits, c.amount / old)) * x
    end
    _refuse(c, ":$(c.label) is not a lot of one ingredient or of a liquor: set its contents instead")
end
_negative(x) = x < zero(x)
_lot(p::Portion) = Contents(zero(Liquor), AbstractSolid[p])
_portion_amount(::SetAmount, m::Unitful.Mass) = m
_portion_amount(::SetAmount, n::Real) = n
_portion_amount(c::SetAmount, x) = _refuse(c, "the amount of an ingredient is a mass or a count, not $(_fmt(x))")
_liquor_amount(::SetAmount, x, ::Unitful.Volume) = uconvert(u"L", volume(x))
_liquor_amount(::SetAmount, x, ::Unitful.Mass) = uconvert(u"kg", total_mass(x))
_liquor_amount(c::SetAmount, x, a) = _refuse(c, "the amount of a liquor is a volume or a mass, not $(_fmt(a))")

"""
    SetIngredient(label, ingredient)

Replaces the ingredient of the lot `label` (a lot of one ingredient) by `ingredient`, of the
same kind (a fermentable by a fermentable, ...), keeping its amount. Reverted by its
[`Inverse`](@ref).
"""
struct SetIngredient{I <: AbstractIngredient} <: EditCommand
    label::Symbol
    ingredient::I
end

describe(c::SetIngredient) = "Set the ingredient of :$(c.label) to $(c.ingredient.name)"
function validate(c::SetIngredient, q::Quiver)
    _check_node(c, q, c.label)
    x = q[c.label].initial
    (iszero(x.liquor) && length(x.solids) == 1 && only(x.solids) isa Portion) ||
        _refuse(c, ":$(c.label) is not a lot of one ingredient")
    old = only(x.solids).ingredient
    typeof(old) == typeof(c.ingredient) ||
        _refuse(c, "a lot of $(lowercase(string(nameof(typeof(old)))))s takes a $(lowercase(string(nameof(typeof(old))))), " *
                   "not a $(lowercase(string(nameof(typeof(c.ingredient)))))")
    _check_names(c, q, c.label, _with_ingredient(c, x))
end
affected(c::SetIngredient, q::Quiver) = [c.label]
revert_record(c::SetIngredient, q::Quiver) = Inverse(SetInitial(c.label, q[c.label].initial))
perform!(q::Quiver, c::SetIngredient) = (q[c.label] = _with_ingredient(c, q[c.label].initial); nothing)
_with_ingredient(c::SetIngredient, x::Contents) =
    (p = only(x.solids); _lot(Portion(c.ingredient, p.amount; timing = p.timing)))

# the liquor of a lot of liquor only (water, a salt or an acid dissolved), or a refusal
function _liquor_lot(c, q, label)
    x = q[label].initial
    (isempty(x.solids) && !iszero(x.liquor)) || _refuse(c, ":$label is not a lot of water or of a liquor")
    return x.liquor
end

"""
    SetTemperature(label, temperature)

Sets the temperature of the lot of liquor `label` (e.g. the strike water). Reverted by its
[`Inverse`](@ref).
"""
struct SetTemperature <: EditCommand
    label::Symbol
    temperature::Any       # (any value typed: what is not a temperature is refused)
end

describe(c::SetTemperature) = "Set the temperature of :$(c.label) to $(_fmt(c.temperature))"
function validate(c::SetTemperature, q::Quiver)
    _check_node(c, q, c.label)
    c.temperature isa Unitful.Temperature ||
        _refuse(c, "a temperature is in °C or °F, e.g. 70 °C, 70 C, 158 F")
    _liquor_lot(c, q, c.label)
    return nothing
end
affected(c::SetTemperature, q::Quiver) = [c.label]
revert_record(c::SetTemperature, q::Quiver) = Inverse(SetInitial(c.label, q[c.label].initial))
perform!(q::Quiver, c::SetTemperature) =
    (q[c.label] = with_temperature(q[c.label].initial, c.temperature); nothing)

"""
    SetWaterProfile(label, profile)

Sets the `WaterProfile` of the lot of water `label`, keeping its water and temperature: its
minerals are those of the profile for its volume. Reverted by its [`Inverse`](@ref).
"""
struct SetWaterProfile <: EditCommand
    label::Symbol
    profile::WaterProfile
end

describe(c::SetWaterProfile) = "Set the water profile of :$(c.label)"
function validate(c::SetWaterProfile, q::Quiver)
    _check_node(c, q, c.label)
    l = _liquor_lot(c, q, c.label)
    (iszero(l.extract) && iszero(l.alcohol) && !iszero(l.water)) ||
        _refuse(c, ":$(c.label) is not a lot of water")
    return nothing
end
affected(c::SetWaterProfile, q::Quiver) = [c.label]
revert_record(c::SetWaterProfile, q::Quiver) = Inverse(SetInitial(c.label, q[c.label].initial))
function perform!(q::Quiver, c::SetWaterProfile)
    x = q[c.label].initial
    l = x.liquor
    q[c.label] = Liquor(; water = l.water, temperature = l.temperature,
                        minerals = Minerals(c.profile, uconvert(u"L", volume(x))))
    return nothing
end

# ---------------------------------------------------------------------------------------
# arrows

"""
    SetArrow(source, destination, index, arrow)

Replaces the `index`-th arrow from `source` to `destination` by `arrow`. Reverted by its
[`Inverse`](@ref).
"""
struct SetArrow{A <: AbstractArrow} <: EditCommand
    source::Symbol
    destination::Symbol
    index::Int
    arrow::A
end
SetArrow(e::Pair{Symbol, Symbol}, index::Integer, a::AbstractArrow) = SetArrow(e.first, e.second, index, a)

describe(c::SetArrow) = "Set $(_edge(c.source, c.destination, c.index)) to a $(_arrow_name(c.arrow))"
validate(c::SetArrow, q::Quiver) = _check_arrow(c, q, c.source, c.destination, c.index)
affected(c::SetArrow, q::Quiver) = [c.source]
revert_record(c::SetArrow, q::Quiver) =
    Inverse(SetArrow(c.source, c.destination, c.index, q[c.source => c.destination, c.index]))
perform!(q::Quiver, c::SetArrow) = (q[c.source => c.destination, c.index] = c.arrow; nothing)

"""
    SetArrowField(source, destination, index, field, value)

Sets the `field` of the `index`-th arrow from `source` to `destination` to `value`, e.g.
`SetArrowField(:kettle, :wort, 1, :time, 70u"minute")`. A quantity is converted to the unit
of the field (a dimensionless one, like a percentage, to a fraction); quantities of
amounts, times and rates cannot be negative, and fractions are between 0 and 1. Reverted by
its [`Inverse`](@ref).
"""
struct SetArrowField <: EditCommand
    source::Symbol
    destination::Symbol
    index::Int
    field::Symbol
    value::Any
end
SetArrowField(e::Pair{Symbol, Symbol}, index::Integer, field::Symbol, value) =
    SetArrowField(e.first, e.second, index, field, value)

describe(c::SetArrowField) =
    "Set the $(_field_name(c.field)) of $(_edge(c.source, c.destination, c.index)) to $(_fmt(c.value))"
function validate(c::SetArrowField, q::Quiver)
    _check_arrow(c, q, c.source, c.destination, c.index)
    _with_field(c, q[c.source => c.destination, c.index])
    return nothing
end
affected(c::SetArrowField, q::Quiver) = [c.source]
revert_record(c::SetArrowField, q::Quiver) =
    Inverse(SetArrow(c.source, c.destination, c.index, q[c.source => c.destination, c.index]))
perform!(q::Quiver, c::SetArrowField) =
    (q[c.source => c.destination, c.index] = _with_field(c, q[c.source => c.destination, c.index]); nothing)

# the arrow `a` with the field of `c` set
_with_field(c::SetArrowField, a::AbstractArrow) = _rebuild(c, a, c.field, c.value)

# `x` with its `field` set to `value`, rebuilt with the constructor of all its fields
function _rebuild(c, x, field::Symbol, value)
    T = typeof(x)
    field in fieldnames(T) ||
        _refuse(c, "a $(nameof(T)) has no $field; its fields are " * join(fieldnames(T), ", "))
    v = _fit_field(c, field, fieldtype(T, field), value)
    vals = [f == field ? v : getfield(x, f) for f in fieldnames(T)]
    return Base.typename(T).wrapper(vals...)
end

# `v` as a value of the field type `T`
function _fit_field(c, field, T, v)
    v === nothing && Nothing <: T && return nothing
    if v isa Unitful.Quantity
        for U in Base.uniontypes(T)
            if U <: Unitful.Quantity && isconcretetype(U) && dimension(U) == dimension(v)
                x = convert(U, uconvert(unit(U), v))
                _nonnegative(dimension(x)) && _negative(x) && _refuse(c, "it cannot be negative")
                return x
            end
        end
        dimension(v) == NoDims && Float64 <: T && return _fraction(c, float(uconvert(NoUnits, v)))
    elseif v isa Real && !(v isa Bool) && Float64 <: T
        return _fraction(c, float(v))
    elseif v isa T
        return v
    end
    _refuse(c, "the $(_field_name(field)) takes $(_expected(T)), not $(_fmt(v))")
end
_fraction(c, x) = 0 ≤ x ≤ 1 ? x : _refuse(c, "a fraction is between 0 and 1 (0 to 100%)")
# all but temperatures cannot be negative
_nonnegative(d) = d != dimension(u"K")
_expected(T) = join(unique([U === Nothing ? "nothing" : U === Float64 ? "a fraction" :
                            U <: Unitful.Quantity ? "a quantity in $(unit(U))" : string(U)
                            for U in Base.uniontypes(T)]), " or ")

"""
    Connect(source, destination, arrow = Transfer())

Adds `arrow` from `source` to `destination`, after the arrows already there. Arrows that
would create a cycle, or break the rules of the arrows leaving a node, are refused.
Reverted by its [`Inverse`](@ref), a [`RemoveArrow`](@ref) of the last arrow.
"""
struct Connect{A <: AbstractArrow} <: EditCommand
    source::Symbol
    destination::Symbol
    arrow::A
end
Connect(source::Symbol, destination::Symbol) = Connect(source, destination, Transfer())
Connect(e::Pair{Symbol, Symbol}, a::AbstractArrow = Transfer()) = Connect(e.first, e.second, a)

describe(c::Connect) = "Connect :$(c.source) => :$(c.destination)" *
                       (c.arrow == Transfer() ? "" : " with a $(_arrow_name(c.arrow))")
function validate(c::Connect, q::Quiver)
    _check_node(c, q, c.source)
    _check_node(c, q, c.destination)
end
affected(c::Connect, q::Quiver) = [c.source]
revert_record(c::Connect, q::Quiver) =
    Inverse(RemoveArrow(c.source, c.destination, _count(q, c.source, c.destination) + 1))
perform!(q::Quiver, c::Connect) = (connect!(q, c.source => c.destination, c.arrow); nothing)
_count(q, s, d) = d in successors(q, s) ? length(q[s => d]) : 0

"""
    RemoveArrow(source, destination, index)

Removes the `index`-th arrow from `source` to `destination`, keeping the others in order.
Reverted by a [`Connect`](@ref) when it is the last one, else by a [`Snapshot`](@ref).
"""
struct RemoveArrow <: EditCommand
    source::Symbol
    destination::Symbol
    index::Int
end
RemoveArrow(e::Pair{Symbol, Symbol}, index::Integer) = RemoveArrow(e.first, e.second, index)

describe(c::RemoveArrow) = "Remove the arrow $(_edge(c.source, c.destination, c.index))"
validate(c::RemoveArrow, q::Quiver) = _check_arrow(c, q, c.source, c.destination, c.index)
affected(c::RemoveArrow, q::Quiver) = [c.source, c.destination]
revert_record(c::RemoveArrow, q::Quiver) =
    c.index == _count(q, c.source, c.destination) ?
        Inverse(Connect(c.source, c.destination, q[c.source => c.destination, c.index])) : Snapshot(q)
perform!(q::Quiver, c::RemoveArrow) = (disconnect!(q, c.source => c.destination, c.index); nothing)

"""
    Disconnect(source, destination)

Removes all the arrows from `source` to `destination`. Reverted by a [`Snapshot`](@ref).
"""
struct Disconnect <: EditCommand
    source::Symbol
    destination::Symbol
end
Disconnect(e::Pair{Symbol, Symbol}) = Disconnect(e.first, e.second)

describe(c::Disconnect) = "Disconnect :$(c.source) => :$(c.destination)"
function validate(c::Disconnect, q::Quiver)
    _check_node(c, q, c.source)
    _check_node(c, q, c.destination)
    _count(q, c.source, c.destination) > 0 ||
        _refuse(c, "there is no arrow from :$(c.source) to :$(c.destination)")
end
affected(c::Disconnect, q::Quiver) = [c.source, c.destination]
revert_record(::Disconnect, q::Quiver) = Snapshot(q)
perform!(q::Quiver, c::Disconnect) = (disconnect!(q, c.source => c.destination); nothing)

# ---------------------------------------------------------------------------------------
# nodes

"""
    AddNode(label, initial = Contents(); vessel = nothing)

Adds the node `label` with `initial` contents (a lot), or empty (a stage, filled by
arrows), in `vessel`. Reverted by its [`Inverse`](@ref), a [`RemoveNode`](@ref).
"""
struct AddNode <: EditCommand
    label::Symbol
    initial::Contents
    vessel::Union{Nothing, Symbol}
end
AddNode(label::Symbol, initial = Contents(); vessel::Union{Nothing, Symbol} = nothing) =
    AddNode(label, _contents(initial), vessel)

describe(c::AddNode) = "Add :$(c.label)" * (c.vessel === nothing ? "" : " to the $(c.vessel)")
function validate(c::AddNode, q::Quiver)
    _check_label(c, c.label)
    _check_free(c, q, c.label)
    _check_names(c, q, c.label, c.initial)
end
affected(c::AddNode, q::Quiver) = [c.label]
revert_record(c::AddNode, q::Quiver) = Inverse(RemoveNode(c.label))
perform!(q::Quiver, c::AddNode) = (add!(q, c.label, c.initial; vessel = c.vessel); nothing)

"""
    RemoveNode(label)

Removes the node `label` with its arrows. Reverted by a [`Snapshot`](@ref): an inverse
would have to restore its arrows, in their order among the others, and its place in the
order of the nodes.
"""
struct RemoveNode <: EditCommand
    label::Symbol
end

describe(c::RemoveNode) = "Remove :$(c.label)"
validate(c::RemoveNode, q::Quiver) = _check_node(c, q, c.label)
affected(c::RemoveNode, q::Quiver) = union(predecessors(q, c.label), successors(q, c.label))
revert_record(::RemoveNode, q::Quiver) = Snapshot(q)
perform!(q::Quiver, c::RemoveNode) = (remove!(q, c.label); nothing)

"""
    RenameNode(old, new)

Renames the node `old` to `new`, keeping everything else (see `rename!`). Reverted by its
[`Inverse`](@ref). The selection follows the node.
"""
struct RenameNode <: EditCommand
    old::Symbol
    new::Symbol
end

describe(c::RenameNode) = "Rename :$(c.old) to :$(c.new)"
function validate(c::RenameNode, q::Quiver)
    _check_node(c, q, c.old)
    _check_label(c, c.new)
    c.old == c.new || _check_free(c, q, c.new)
end
affected(c::RenameNode, q::Quiver) = [c.new]
revert_record(c::RenameNode, q::Quiver) = Inverse(RenameNode(c.new, c.old))
perform!(q::Quiver, c::RenameNode) = (rename!(q, c.old, c.new); nothing)

"""
    SetVessel(label, vessel)

Puts the node `label` in `vessel` (a `Symbol`), or in none (`nothing`). Its arrows take
what they do not give themselves from the equipment of its new vessel. Reverted by its
[`Inverse`](@ref).
"""
struct SetVessel <: EditCommand
    label::Symbol
    vessel::Union{Nothing, Symbol}
end

describe(c::SetVessel) =
    c.vessel === nothing ? "Take :$(c.label) out of its vessel" : "Put :$(c.label) in the $(c.vessel)"
validate(c::SetVessel, q::Quiver) = _check_node(c, q, c.label)
affected(c::SetVessel, q::Quiver) = [c.label]
revert_record(c::SetVessel, q::Quiver) = Inverse(SetVessel(c.label, vessel(q, c.label)))
perform!(q::Quiver, c::SetVessel) = (vessel!(q, c.label, c.vessel); nothing)

# ---------------------------------------------------------------------------------------
# equipment

"""
    Equip(vessel, equipment)

Attaches the `equipment` (a `Vessel`) to `vessel` (see `equip!`), or removes it
(`nothing`). Reverted by its [`Inverse`](@ref).
"""
struct Equip <: EditCommand
    vessel::Symbol
    equipment::Union{Nothing, Vessel}
end

describe(c::Equip) = c.equipment === nothing ? "Remove the equipment of the $(c.vessel)" :
                                               "Equip the $(c.vessel)"
validate(c::Equip, q::Quiver) =
    isempty(String(c.vessel)) && _refuse(c, "the name of a vessel cannot be empty")
affected(c::Equip, q::Quiver) = [n for n in nodes(q) if vessel(q, n) === c.vessel]
revert_record(c::Equip, q::Quiver) = Inverse(Equip(c.vessel, equipment(q, c.vessel)))
perform!(q::Quiver, c::Equip) =
    (c.equipment === nothing ? unequip!(q, c.vessel) : equip!(q, c.vessel, c.equipment); nothing)

"""
    SetEquipmentField(vessel, field, value)

Sets the `field` of the equipment of `vessel` (a field of `Vessel`, e.g. `:evaporation`) to
`value`, converted as by [`SetArrowField`](@ref); `nothing` leaves it to the arrows. A
vessel without equipment gets one. Reverted by its [`Inverse`](@ref), an [`Equip`](@ref).
"""
struct SetEquipmentField <: EditCommand
    vessel::Symbol
    field::Symbol
    value::Any
end

describe(c::SetEquipmentField) = "Set the $(_field_name(c.field)) of the $(c.vessel) to $(_fmt(c.value))"
function validate(c::SetEquipmentField, q::Quiver)
    isempty(String(c.vessel)) && _refuse(c, "the name of a vessel cannot be empty")
    _with_field(c, something(equipment(q, c.vessel), Vessel()))
    return nothing
end
affected(c::SetEquipmentField, q::Quiver) = affected(Equip(c.vessel, nothing), q)
revert_record(c::SetEquipmentField, q::Quiver) = Inverse(Equip(c.vessel, equipment(q, c.vessel)))
perform!(q::Quiver, c::SetEquipmentField) =
    (equip!(q, c.vessel, _with_field(c, something(equipment(q, c.vessel), Vessel()))); nothing)
_with_field(c::SetEquipmentField, v::Vessel) = _rebuild(c, v, c.field, c.value)

# ---------------------------------------------------------------------------------------
# layout and view (see the nodeview convention in the README)

"""
    SetView(label, key, value)

Sets the `key` of the [`nodeview`] of the node `label` to `value`, or deletes it (`nothing`).
Keys without a prefix follow the convention of the README (`"position"`, `"collapsed"`,
`"color"`, `"note"`) and their values are checked; a frontend's own keys have its prefix
(`"term."`, `"app."`). It only changes the layout: the brew is kept. Reverted by its
[`Inverse`](@ref).
"""
struct SetView <: EditCommand
    label::Symbol
    key::String
    value::Any
end

describe(c::SetView) = c.value === nothing ? "Clear the $(c.key) of :$(c.label)" :
                                             "Set the $(c.key) of :$(c.label)"
brew_effect(::SetView) = LayoutOnly()
function validate(c::SetView, q::Quiver)
    _check_node(c, q, c.label)
    c.value === nothing && return nothing
    occursin('.', c.key) && return nothing
    _check_view(c, Val(Symbol(c.key)), c.value)
end
_check_view(c, ::Val{:position}, v) =
    (v isa AbstractVector && length(v) == 2 && all(x -> x isa Real && isfinite(x), v)) ||
        _refuse(c, "a position is [x, y]")
_check_view(c, ::Val{:collapsed}, v) = v isa Bool || _refuse(c, "collapsed is true or false")
_check_view(c, ::Val{:color}, v) =
    (v isa AbstractString && occursin(r"^#[0-9a-fA-F]{6}$", v)) || _refuse(c, "a color is \"#rrggbb\"")
_check_view(c, ::Val{:note}, v) = v isa AbstractString || _refuse(c, "a note is a string")
_check_view(c, ::Val, v) =
    _refuse(c, "$(repr(c.key)) is not a key of the nodeview convention; " *
               "a frontend's own keys have its prefix, e.g. \"term.$(c.key)\"")
affected(::SetView, ::Quiver) = Symbol[]
revert_record(c::SetView, q::Quiver) =
    Inverse(SetView(c.label, c.key, deepcopy(get(nodeview(q, c.label), c.key, nothing))))
function perform!(q::Quiver, c::SetView)
    v = nodeview(q, c.label)
    c.value === nothing ? delete!(v, c.key) : (v[c.key] = deepcopy(c.value))
    return nothing
end

"""
    MoveNode(label, position)

Moves the node `label` to `position`, `[x, y]` in abstract layout units: the `"position"` of
its nodeview. It only changes the layout. Reverted by its [`Inverse`](@ref).
"""
struct MoveNode <: EditCommand
    label::Symbol
    position::Vector{Float64}
end
MoveNode(label::Symbol, p) = MoveNode(label, Float64[p...])

describe(c::MoveNode) = "Move :$(c.label)"
brew_effect(::MoveNode) = LayoutOnly()
function validate(c::MoveNode, q::Quiver)
    _check_node(c, q, c.label)
    (length(c.position) == 2 && all(isfinite, c.position)) || _refuse(c, "a position is [x, y]")
end
affected(::MoveNode, ::Quiver) = Symbol[]
revert_record(c::MoveNode, q::Quiver) = revert_record(SetView(c.label, "position", c.position), q)
perform!(q::Quiver, c::MoveNode) = perform!(q, SetView(c.label, "position", c.position))

# ---------------------------------------------------------------------------------------
# solving

"""
    Solve(targets, vary; rtol = 1e-8, maxiter = 50)

Changes the parameters `vary` of the quiver to meet the `targets` (see `solve!`), with the
models of the session. [`apply!`](@ref) returns the `Solution`; the quiver is left with it
also when the solver does not converge. Reverted by a [`Snapshot`](@ref).
"""
struct Solve <: EditCommand
    targets::Vector{Target}
    vary::Vector{AbstractParameter}
    rtol::Float64
    maxiter::Int
end
Solve(targets, vary; rtol::Real = 1e-8, maxiter::Integer = 50) =
    Solve(Target[Target(t) for t in (targets isa AbstractVector ? targets : [targets])],
          AbstractParameter[p for p in (vary isa AbstractParameter ? [vary] : vary)], rtol, maxiter)

describe(c::Solve) = length(c.targets) == 1 ?
    "Solve for the $(nameof(only(c.targets).f)) of :$(only(c.targets).node)" :
    "Solve for $(length(c.targets)) targets"
function validate(c::Solve, q::Quiver)
    for t in c.targets
        _check_node(c, q, t.node)
    end
    for p in c.vary
        _check_parameter(c, q, p)
    end
end
_check_parameter(c, q, p::Amount) = foreach(l -> _check_node(c, q, l), p.labels)
_check_parameter(c, q, p::Setting) = _check_arrow(c, q, p.edge.first, p.edge.second, p.index)
affected(::Solve, ::Quiver) = AllNodes()
revert_record(::Solve, q::Quiver) = Snapshot(q)
perform!(s, c::Solve) = solve!(s.quiver, c.targets...; vary = c.vary, models = s.models,
                               rtol = c.rtol, maxiter = c.maxiter)
