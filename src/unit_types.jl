# The preferred units (see units.jl), defined before the session that holds them.

const _U = Union{Symbol, Unitful.Units}   # (a unit, or :auto)

"""
    UNIT_CHOICES

The units each kind of quantity (a *role*) can be shown and typed in, the first being the
default; `:auto` shows a mass or a volume in the unit that suits its size (kg or g, L or mL,
see [`display_unit`](@ref)):

| role | quantities | choices |
|---|---|---|
| `fermentable` | amounts of malts, sugars | auto, kg, g, lb, oz |
| `hop` | amounts of hops | g, mg, kg, oz, lb |
| `culture` | masses of yeast (counts stay counts) | g, mg, kg, oz |
| `agent` | salts and acids | g, mg, oz |
| `mass` | other masses (the liquor, the solids left) | auto, kg, g, lb, oz |
| `volume` | water, wort, beer | auto, L, mL, hL, gal, qt, bbl |
| `temperature` | | °C, °F |
| `gravity` | | sg, °P, Brix |
| `color` | | SRM, EBC, °L |
| `absorption` | grain and hop absorption | L/kg, qt/lb |
| `rate` | evaporation, drain rate | L/hr, gal/hr |
"""
const UNIT_CHOICES = (
    fermentable = _U[:auto, u"kg", u"g", u"lb", u"oz"],
    hop = _U[u"g", u"mg", u"kg", u"oz", u"lb"],
    culture = _U[u"g", u"mg", u"kg", u"oz"],
    agent = _U[u"g", u"mg", u"oz"],
    mass = _U[:auto, u"kg", u"g", u"lb", u"oz"],
    volume = _U[:auto, u"L", u"mL", u"hL", u"gal", u"qt", u"bbl"],
    temperature = _U[u"°C", u"°F"],
    gravity = _U[u"sg", u"°P", u"Brix"],
    color = _U[u"SRM", u"EBC", u"°L"],
    absorption = _U[u"L/kg", u"qt/lb"],
    rate = _U[u"L/hr", u"gal/hr"])

"""
    UnitPreferences(; role = unit, ...)

The unit each role is shown and typed in (see [`UNIT_CHOICES`](@ref)), the defaults for
those not given: e.g. `UnitPreferences(fermentable = u"lb", hop = u"oz", volume = u"gal",
temperature = u"°F")`. A [`Session`](@ref) has its preferences ([`units`](@ref)), read by
frontends from a configuration file ([`load_units`](@ref)).
"""
struct UnitPreferences
    units::Dict{Symbol, Union{Symbol, Unitful.Units}}
    function UnitPreferences(d::AbstractDict)
        units = Dict{Symbol, Union{Symbol, Unitful.Units}}(r => first(cs) for (r, cs) in pairs(UNIT_CHOICES))
        for (r, u) in d
            r = Symbol(r)
            haskey(UNIT_CHOICES, r) ||
                throw(ArgumentError("$(repr(r)) is not a role of units: " * join(keys(UNIT_CHOICES), ", ")))
            u in UNIT_CHOICES[r] ||
                throw(ArgumentError("$u is not a unit for $r: " * join(_unit_name.(UNIT_CHOICES[r]), ", ")))
            units[r] = u
        end
        return new(units)
    end
end
UnitPreferences(; kwargs...) = UnitPreferences(Dict{Symbol, Union{Symbol, Unitful.Units}}(kwargs))

Base.getindex(p::UnitPreferences, role::Symbol) = p.units[role]
Base.:(==)(a::UnitPreferences, b::UnitPreferences) = a.units == b.units

