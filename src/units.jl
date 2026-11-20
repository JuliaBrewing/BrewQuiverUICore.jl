# Preferred units: in which unit each kind of quantity is shown, and read when typed without
# one; per role (the masses of malts, of hops, ...), kept in a configuration file shared by
# the frontends.

"""
    with_unit(p::UnitPreferences, role, unit)

The preferences `p` with `unit` for `role`.
"""
with_unit(p::UnitPreferences, role::Symbol, u) = UnitPreferences(merge(p.units, Dict(role => u)))

_unit_name(u::Unitful.Units) = unit_symbol(u)
_unit_name(::Symbol) = "auto"

# ---------------------------------------------------------------------------------------
# roles

"""
    unit_role(x) -> Union{Symbol, Nothing}
    unit_role(ingredient) -> Symbol

The role of a quantity by its dimension or unit (`:mass`, `:volume`, `:temperature`,
`:gravity`, `:color`, `:absorption`, `:rate`), or `nothing` for those shown in their own
unit (times, bitterness, concentrations, ...); or the role of the amounts of an ingredient
(`:fermentable`, `:hop`, `:culture`, `:agent`).
"""
unit_role(x::Unitful.Quantity) = unit_role(unit(x))
function unit_role(u::Unitful.Units)
    d = dimension(u)
    d == dimension(u"kg") && return :mass
    d == dimension(u"L") && return :volume
    d == dimension(u"K") && return :temperature
    (u == u"sg" || d == dimension(u"°P")) && return :gravity
    d == dimension(u"SRM") && return :color
    d == dimension(u"L/kg") && return :absorption
    d == dimension(u"L/hr") && return :rate
    return nothing
end
unit_role(::Fermentable) = :fermentable
unit_role(::Hop) = :hop
unit_role(::Culture) = :culture
unit_role(::Union{Salt, Acid}) = :agent
unit_role(x) = nothing

# the role of the amount of a lot of contents: that of its ingredient, else of its quantity
function amount_role(c::Contents)
    length(c.solids) == 1 && only(c.solids) isa Portion && return unit_role(only(c.solids).ingredient)
    isempty(c.solids) && iszero(c.liquor.water) && return :agent
    return nothing
end

"""
    preferred_unit(p::UnitPreferences, role, x = nothing)

The unit `x` (a quantity of `role`) is shown in by the preferences `p`: the unit of the
role, or for `:auto` the [`display_unit`](@ref) of `x` (or kg, L when there is no `x`).
`nothing` when there is no role, or when the role's unit does not fit `x` (e.g. a count).
"""
function preferred_unit(p::UnitPreferences, role, x = nothing)
    role === nothing && return x isa Unitful.Quantity ? display_unit(x) : nothing
    u = p[role]
    u === :auto && return x isa Unitful.Quantity ? display_unit(x) : UNIT_CHOICES[role][2]
    x isa Unitful.Quantity && !_fits(x, u) && return display_unit(x)
    return u
end

# whether `x` can be shown in `u` (gravities through an equivalence)
_fits(x, u) = dimension(x) == dimension(u) || (unit_role(x) === :gravity && unit_role(u) === :gravity)

# ---------------------------------------------------------------------------------------
# formatting and parsing with preferences

# `x` in the unit `u`, converting gravities with the equivalence `eq`
function _in_unit(x, u, eq)
    dimension(x) == dimension(u) && return uconvert(u, x)
    return uconvert(u, x, eq)
end

"""
    format(p::UnitPreferences, x; role = unit_role(x), eq = DEFAULT_MODELS.gravity)
    format(s::Session, x; role = unit_role(x))

`x` as a string, in the unit the preferences `p` (or those of the session `s`) give its
`role` (see [`preferred_unit`](@ref)): e.g. a malt in lb, a hop in oz, a volume in gal.
Gravities are converted with the equivalence `eq` (that of the models of the session).
Anything else is shown by [`format`](@ref).
"""
function format(p::UnitPreferences, x::Unitful.Quantity; role = unit_role(x), eq = DEFAULT_MODELS.gravity)
    u = preferred_unit(p, role, x)
    u === nothing && return format(x)
    return format(_in_unit(x, u, eq); unit = u)
end
format(p::UnitPreferences, t::Remaining; kwargs...) = format(p, t.time; kwargs...) * " remaining"
format(p::UnitPreferences, t::At; kwargs...) = "at " * format(p, t.time; kwargs...)
format(p::UnitPreferences, x; kwargs...) = format(x)
format(s::Session, x; role = unit_role(x)) = format(s.units, x; role, eq = models_in_use(s).gravity)

"""
    input_unit(p::UnitPreferences, current; role = unit_role(current))

The unit a number typed without one is read in, when it replaces `current`, with the
preferences `p`: the unit `current` is shown in, or with no current value (`nothing`), the
preferred unit of `role`.
"""
input_unit(p::UnitPreferences, current::Unitful.Quantity; role = unit_role(current)) =
    preferred_unit(p, role, current)
input_unit(p::UnitPreferences, t::Union{Remaining, At}; role = nothing) = input_unit(p, t.time)
input_unit(p::UnitPreferences, ::Nothing; role = nothing) =
    role === nothing ? nothing : preferred_unit(p, role)
input_unit(p::UnitPreferences, x; role = nothing) = nothing

"""
    parse_value(s::Session, text, current; role = unit_role(current))

What a user typed to replace `current` in the session `s`: a number without a unit is in
the unit `current` is shown in with the preferences of `s`, or with no current value in the
preferred unit of `role` (see [`input_unit`](@ref)).
"""
parse_value(s::Session, text::AbstractString, current; role = unit_role(current)) =
    parse_value(text; unit = input_unit(s.units, current; role))

# ---------------------------------------------------------------------------------------
# the preferences of a session, and the configuration file

"""
    units(s::Session)

The [`UnitPreferences`](@ref) of the session. Set them with [`set_units!`](@ref).
"""
units(s::Session) = s.units

"""
    set_units!(s::Session, p::UnitPreferences)

Shows and reads the quantities of `s` in the units of `p`. Not part of the quiver, nor of
its history.
"""
set_units!(s::Session, p::UnitPreferences) = (s.units = p; s)

"""
    units_path()

The configuration file of the preferred units, shared by the frontends:
`brewquiver/units.toml` in `XDG_CONFIG_HOME`, or `~/.config`.
"""
units_path() = joinpath(get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config")), "brewquiver", "units.toml")

"""
    load_units(path = units_path()) -> UnitPreferences

The preferences of the file at `path` (TOML, `role = "unit"`, e.g. `fermentable = "lb"`),
or the defaults if there is no such file.
"""
function load_units(path::AbstractString = units_path())
    isfile(path) || return UnitPreferences()
    d = TOML.parsefile(path)
    units = Dict{Symbol, Any}()
    for (r, name) in get(d, "units", d)
        r = Symbol(r)
        haskey(UNIT_CHOICES, r) || throw(ArgumentError("$path: $(repr(r)) is not a role of units"))
        u = findfirst(u -> _unit_name(u) == name || string(u) == name, UNIT_CHOICES[r])
        u === nothing && throw(ArgumentError("$path: $(repr(name)) is not a unit for $r"))
        units[r] = UNIT_CHOICES[r][u]
    end
    return UnitPreferences(units)
end

"""
    save_units(p::UnitPreferences, path = units_path())

Writes the preferences `p` to the configuration file at `path`.
"""
function save_units(p::UnitPreferences, path::AbstractString = units_path())
    mkpath(dirname(path))
    d = Dict("units" => Dict(String(r) => _unit_name(p[r]) for r in keys(UNIT_CHOICES)))
    open(io -> TOML.print(io, d; sorted = true), path, "w")
    return path
end

"""
    contents_text(s::Session, contents)

A short description of the contents of a lot, in the units of the session:
`"4.5 kg Pale ale malt"` (or `"9.92 lb Pale ale malt"`), `"1 × US-05"`, `"16.0 L"`.
"""
function contents_text(s::Session, c::Contents)
    p = s.units
    if isempty(c.solids) && !iszero(c.liquor)
        iszero(c.liquor.water) && return format(s, total_mass(c); role = :agent)
        return format(s, uconvert(u"L", volume(c)); role = :volume)
    elseif iszero(c.liquor) && length(c.solids) == 1 && only(c.solids) isa Portion
        x = only(c.solids)
        x.amount isa Real && return "$(_fmt(x.amount)) × $(x.ingredient.name)"
        return format(s, x.amount; role = unit_role(x.ingredient)) * " " * x.ingredient.name
    end
    return iszero(c) ? "nothing" : "new contents"
end
