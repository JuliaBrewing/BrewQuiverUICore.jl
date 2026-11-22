# View data: summaries of nodes and arrows, details, results tables, timelines and solutions,
# as plain data with Unitful quantities, for the frontends to render (see `format`).

"""
    NodeSummary

What a frontend shows of a node, from [`node_summary`](@ref):

- `label`, `vessel` (or `nothing`), `kind`: `:lot` (initial contents, e.g. a malt, the
  water), `:stage` (filled by arrows) or `:product` (a stage with no arrows leaving it);
- `contents`: a short description of the initial contents of a lot ("4.5 kg Pale ale
  malt"), else `""`;
- the results of the brew, `missing` where they do not apply (no liquid, not brewed):
  `volume`, `gravity`, `original_gravity`, `abv`, `ibu`, `srm`, `temperature`,
  `carbonation`, and `mash_ph` (a number, for nodes with grain to mash);
- `color`: `"#rrggbb"`, the user's color (nodeview `"color"`) or that of the beer from its
  SRM, or `nothing`;
- `warnings` (strings), whether it `changed` in the last step, whether it is `selected`.
"""
struct NodeSummary
    label::Symbol
    vessel::Union{Nothing, Symbol}
    kind::Symbol
    contents::String
    volume::Union{Missing, Unitful.Quantity}
    gravity::Union{Missing, Unitful.Quantity}
    original_gravity::Union{Missing, Unitful.Quantity}
    abv::Union{Missing, Unitful.Quantity}
    ibu::Union{Missing, Unitful.Quantity}
    srm::Union{Missing, Unitful.Quantity}
    temperature::Union{Missing, Unitful.Quantity}
    carbonation::Union{Missing, Unitful.Quantity}
    mash_ph::Union{Missing, Float64}
    color::Union{Nothing, String}
    warnings::Vector{String}
    changed::Bool
    selected::Bool
end

"""
    RESULT_COLUMNS

The results of a node shown in tables, in order, as `field => header` (fields of
[`NodeSummary`](@ref)).
"""
const RESULT_COLUMNS = [:volume => "Volume", :gravity => "Gravity", :original_gravity => "OG",
                        :abv => "ABV", :ibu => "IBU", :srm => "Color",
                        :temperature => "Temp.", :mash_ph => "Mash pH"]

_kind(q::Quiver, label) = !iszero(q[label].initial) && isempty(predecessors(q, label)) ? :lot :
                          isempty(successors(q, label)) ? :product : :stage

"""
    node_summary(s::Session, label) -> NodeSummary
    node_summaries(s::Session) -> Vector{NodeSummary}

The [`NodeSummary`](@ref) of the node `label`, or of all the nodes in topological order.
"""
function node_summary(s::Session, label::Symbol)
    q = s.quiver
    haskey(q, label) || throw(ArgumentError("there is no node labelled :$label"))
    kind = _kind(q, label)
    initial = q[label].initial
    values, phwarnings = _results(s, label)
    return NodeSummary(label, vessel(q, label), kind,
                       kind === :lot ? contents_text(s, initial) : "", values...,
                       node_color(s, label), vcat([w.message for w in warnings(s, label)], phwarnings),
                       label in s.changed, NodeRef(label) in s.selection)
end
"""
    node_summaries(s::Session) -> Vector{NodeSummary}

The [`NodeSummary`](@ref) of every node of `s`, in topological order.
"""
node_summaries(s::Session) = [node_summary(s, n) for n in nodes(s.quiver)]

const _NO_RESULTS = (missing, missing, missing, missing, missing, missing, missing, missing, missing)

function _results(s::Session, label::Symbol)
    isbrewed(s) || return _NO_RESULTS, String[]
    c = s.result[label]
    ph, phwarnings = _mash_ph(c)
    iszero(mass(c.liquor)) && return (_NO_RESULTS[1:end-1]..., ph), phwarnings
    m = s.result.models
    eq = m.gravity
    return (uconvert(u"L", volume(c; eq)), gravity(c; eq), original_gravity(c; eq),
            uconvert(u"percent", abv(m.abv, c; eq)), ibu(c; eq), srm(m.color, c; eq),
            liquor(c).temperature, carbonation(c; eq), ph), phwarnings
end

# the mash pH of contents with grain to mash, and its warnings
function _mash_ph(c::Contents)
    any(p -> p isa Portion{Fermentable} && p.ingredient.kind === :grain, c.solids) ||
        return missing, String[]
    iszero(mass(c.liquor)) && return missing, String[]
    ph, messages = try
        collecting(() -> mash_ph(c))
    catch e
        e isa ArgumentError || rethrow()
        return missing, [_message(e)]
    end
    return float(ph), messages
end

"""
    node_color(s::Session, label)

The display color of the node `label`, `"#rrggbb"`: the user's (nodeview `"color"`), else
that of its beer from its SRM (`srm_hex` of BrewingFormulas) when it has extract or
alcohol, else that of the fermentable of a lot of one; `nothing` otherwise (water, hops,
...), for the frontend's default.
"""
function node_color(s::Session, label::Symbol)
    c = get(nodeview(s.quiver, label), "color", nothing)
    c === nothing || return c
    if isbrewed(s)
        x = s.result[label]
        l = x.liquor
        (iszero(l.extract) && iszero(l.alcohol)) ||
            return srm_hex(srm(s.result.models.color, x; eq = s.result.models.gravity))
    end
    i = s.quiver[label].initial
    if iszero(i.liquor) && length(i.solids) == 1 && only(i.solids) isa Portion{Fermentable}
        return srm_hex(only(i.solids).ingredient.color)
    end
    return nothing
end

"""
    vessel_groups(s::Session) -> Vector{Pair}

The nodes grouped by vessel, `vessel => labels`, in the topological order of their first
node; the nodes in no vessel (the lots) are grouped under `nothing`.
"""
function vessel_groups(s::Session)
    out = Pair{Union{Nothing, Symbol}, Vector{Symbol}}[]
    at = Dict{Union{Nothing, Symbol}, Int}()
    for n in nodes(s.quiver)
        v = vessel(s.quiver, n)
        haskey(at, v) || (push!(out, v => Symbol[]); at[v] = length(out))
        push!(out[at[v]].second, n)
    end
    return out
end

"""
    results_table(s::Session; columns = RESULT_COLUMNS)

The results of the nodes as a table: `(header, rows)`, with the header strings
(`"Node"`, `"Vessel"` and those of `columns`) and a row for each node, in topological
order, of its label, vessel and results (quantities, `missing` where they do not apply).
"""
function results_table(s::Session; columns = RESULT_COLUMNS)
    header = ["Node"; "Vessel"; [h for (_, h) in columns]]
    rows = [Any[x.label; x.vessel; [getfield(x, f) for (f, _) in columns]] for x in node_summaries(s)]
    return (header = header, rows = rows)
end

# ---------------------------------------------------------------------------------------
# arrows

"""
    ArrowSummary

What a frontend shows of an arrow, from [`arrow_summary`](@ref): `source`, `destination`,
`index`, `kind` (`"Transfer"`, `"Boil"`, ...), `parameters` (the fields given, as a
NamedTuple, e.g. `(time = 60.0 minute, stand = 0.0 minute, ...)`), its `duration`, and from the brew (`missing` if not brewed) the `moved`
volume and mass and the `released` water and CO₂; whether it is `selected`.
"""
struct ArrowSummary{P <: NamedTuple}
    source::Symbol
    destination::Symbol
    index::Int
    kind::String
    parameters::P
    duration::Unitful.Quantity
    moved_volume::Union{Missing, Unitful.Quantity}
    moved_mass::Union{Missing, Unitful.Quantity}
    released_water::Union{Missing, Unitful.Quantity}
    released_co2::Union{Missing, Unitful.Quantity}
    selected::Bool
end

"""
    arrow_summary(s::Session, source, destination, index = 1) -> ArrowSummary
    arrow_summary(s::Session, ref::ArrowRef)
    arrow_summaries(s::Session) -> Vector{ArrowSummary}

The [`ArrowSummary`](@ref) of an arrow, or of all, by source in topological order.
"""
function arrow_summary(s::Session, src::Symbol, dst::Symbol, i::Integer = 1)
    r = ArrowRef(src, dst, i)
    isvalid_ref(s.quiver, r) || throw(ArgumentError("$r is not in the quiver"))
    a = s.quiver[src => dst, i]
    given = Tuple(f for f in fieldnames(typeof(a)) if getfield(a, f) !== nothing)
    params = NamedTuple{given}(Tuple(getfield(a, f) for f in given))
    moved = released = missing
    if isbrewed(s)
        ar = s.result[src => dst][i]
        moved, released = ar.moved, ar.released
    end
    return ArrowSummary(src, dst, i, _arrow_name(a), params, duration(a),
                        moved === missing ? missing : uconvert(u"L", volume(moved; eq = s.result.models.gravity)),
                        moved === missing ? missing : total_mass(moved),
                        released === missing ? missing : released.water,
                        released === missing ? missing : released.co2,
                        r in s.selection)
end
arrow_summary(s::Session, r::ArrowRef) = arrow_summary(s, r.source, r.destination, r.index)
"""
    arrow_summaries(s::Session) -> Vector{ArrowSummary}

The [`ArrowSummary`](@ref) of every arrow of `s`, by source in topological order, then
destination and index.
"""
arrow_summaries(s::Session) =
    [arrow_summary(s, n, d, i) for n in nodes(s.quiver) for d in successors(s.quiver, n)
                               for i in eachindex(s.quiver[n => d])]

"""
    FieldSpec

An editable field of an arrow or of a vessel, for forms (see [`fields`](@ref)): its `name`,
a `label` ("stand temperature"), its `value`, the `units` it accepts (example units, one
per dimension; empty if it is not a quantity), whether it is a `fraction` (a plain number
from 0 to 1, or a percentage), and whether it is `optional` (`nothing` allowed: then the
vessel or a default gives it).
"""
struct FieldSpec{V}
    name::Symbol
    label::String
    value::V
    units::Vector{Unitful.Units}
    fraction::Bool
    optional::Bool
end

"""
    fields(arrow_or_vessel) -> Vector{FieldSpec}

The editable fields of an arrow (set with [`SetArrowField`](@ref)) or of the equipment of a
vessel (set with [`SetEquipmentField`](@ref)).
"""
function fields(x::Union{AbstractArrow, Vessel})
    T = typeof(x)
    return [let FT = fieldtype(T, f), us = Base.uniontypes(FT)
                FieldSpec(f, _field_name(f), getfield(x, f),
                          Unitful.Units[unit(U) for U in us if U <: Unitful.Quantity && isconcretetype(U)],
                          Float64 in us, Nothing in us)
            end for f in fieldnames(T)]
end

# ---------------------------------------------------------------------------------------
# details of contents

"""
    solid_rows(contents)

The solids of `contents`, as NamedTuples `(kind, name, amount, timing)`: `kind` is
`"Portion"` (an ingredient as added; `name` is the ingredient), `"Residue"` (spent grain),
`"HopMatter"` or `"YeastCake"`; `amount` is a mass or a count; `timing` is `nothing` or a
`Remaining`/`At`.
"""
solid_rows(c::Contents) = [_solid_row(x) for x in c.solids]
_solid_row(p::Portion) = (kind = "Portion", name = p.ingredient.name, amount = p.amount, timing = p.timing)
_solid_row(r::Residue) = (kind = "Residue", name = "spent grain", amount = r.mass, timing = nothing)
_solid_row(h::HopMatter) = (kind = "HopMatter", name = "hop matter", amount = h.mass, timing = nothing)
_solid_row(y::YeastCake) = (kind = "YeastCake", name = "yeast", amount = y.mass, timing = nothing)
_solid_row(x::AbstractSolid) = (kind = string(nameof(typeof(x))), name = "", amount = missing, timing = nothing)

"""
    liquor_rows(contents)

The conserved quantities of the liquor of `contents`, as NamedTuples `(name, value)`: water,
extract, alcohol, iso-alpha acids, CO₂ and temperature.
"""
function liquor_rows(c::Contents)
    l = c.liquor
    return [(name = "water", value = l.water), (name = "extract", value = l.extract),
            (name = "alcohol", value = l.alcohol), (name = "iso-alpha acids", value = l.isoalpha),
            (name = "CO₂", value = l.co2), (name = "temperature", value = l.temperature)]
end

"""
    mineral_rows(contents)

The water profile of `contents` (see `profile`), as NamedTuples `(ion, concentration)`, or
an empty vector if it has no liquid.
"""
function mineral_rows(c::Contents)
    iszero(c.liquor.water) && return @NamedTuple{ion::String, concentration::Unitful.Quantity}[]
    p = profile(c)
    return [(ion = "calcium", concentration = p.calcium), (ion = "magnesium", concentration = p.magnesium),
            (ion = "sodium", concentration = p.sodium), (ion = "chloride", concentration = p.chloride),
            (ion = "sulfate", concentration = p.sulfate), (ion = "bicarbonate", concentration = p.bicarbonate)]
end

"""
    node_detail(s::Session, label)

Everything a frontend shows when inspecting a node, as a NamedTuple: its `summary`
([`NodeSummary`](@ref)), its `initial` contents, its `contents` and `leftover` in the brew
(`nothing` if not brewed), and its `incoming` and `outgoing` arrows
([`ArrowSummary`](@ref)s). Contents are shown with [`solid_rows`](@ref),
[`liquor_rows`](@ref) and [`mineral_rows`](@ref).
"""
function node_detail(s::Session, label::Symbol)
    q = s.quiver
    sm = node_summary(s, label)
    brewed = isbrewed(s)
    return (summary = sm, initial = q[label].initial,
            contents = brewed ? s.result[label] : nothing,
            leftover = brewed ? leftover(s.result, label) : nothing,
            incoming = [arrow_summary(s, p, label, i) for p in predecessors(q, label)
                                                     for i in eachindex(q[p => label])],
            outgoing = [arrow_summary(s, label, d, i) for d in successors(q, label)
                                                     for i in eachindex(q[label => d])])
end

# ---------------------------------------------------------------------------------------
# timeline and solutions

"""
    timeline_rows(s::Session; start = 0u"minute")

The timeline of the brew (see `timeline`), as NamedTuples `(label, vessel, arrive, ready,
leave)` in topological order (`leave` is `nothing` for the products), or an empty vector if
the quiver does not brew. See also [`vessel_bookings`](@ref).
"""
function timeline_rows(s::Session; start = 0u"minute")
    t = _timeline(s, start)
    t === nothing && return NamedTuple[]
    return [(label = n, vessel = t.vessels[n], arrive = t[n].arrive, ready = t[n].ready,
             leave = t[n].leave) for n in t.order]
end

"""
    vessel_bookings(s::Session; start = 0u"minute")

When each vessel is busy, for a time × vessel chart: `vessel => [(label, from, to), ...]`
in the order of [`vessel_groups`](@ref), each node of the vessel from when it starts being
filled to when it is emptied (or the end of the timeline, for a product), with the
`makespan` and the `overlaps` (see BrewQuiver), as a NamedTuple `(vessels, makespan,
overlaps)`; `nothing` if the quiver does not brew.
"""
function vessel_bookings(s::Session; start = 0u"minute")
    t = _timeline(s, start)
    t === nothing && return nothing
    span = makespan(t)
    finish = start + span
    vs = [v => [(label = n, from = t[n].arrive, to = something(t[n].leave, finish)) for n in ns]
          for (v, ns) in vessel_groups(s) if v !== nothing]
    return (vessels = vs, makespan = span, overlaps = overlaps(t))
end

_timeline(s::Session, start) = isbrewed(s) ? timeline(s.result, s.quiver; start) : nothing

"""
    solution_rows(sol::Solution)

A `Solution` of [`Solve`](@ref) as plain data: `(converged, iterations, parameters,
targets)`, with `parameters` as NamedTuples `(name, value)` (e.g. `"amount of :pale"` and
its contents) and `targets` as `(node, quantity, goal, reached)`.
"""
function solution_rows(sol::Solution)
    return (converged = sol.converged, iterations = sol.iterations,
            parameters = [(name = _parameter_name(p), value = v) for (p, v) in sol.parameters],
            targets = [(node = t.node, quantity = string(nameof(t.f)), goal = t.goal, reached = r)
                       for (t, r) in sol.targets])
end
_parameter_name(p::Amount) = "amount of " * join((":$l" for l in p.labels), ", ")
_parameter_name(p::Setting) = "$(_field_name(p.field)) of $(_edge(p.edge.first, p.edge.second, p.index))"
_parameter_name(p::AbstractParameter) = string(p)
