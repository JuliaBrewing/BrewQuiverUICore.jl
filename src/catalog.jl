# The ingredients a session can add: those of its quiver, of its library, and the salts and
# acids of brewing water.

"""
    WATER_AGENTS

The salts and acids that can be added to water by name (see [`catalog`](@ref)): the salts
of BrewingFormulas (gypsum, calcium chloride, Epsom salt, ...) and lactic acid (88%) and
phosphoric acid (10%), as `Salt` and `Acid` ingredients of BrewQuiver.
"""
const WATER_AGENTS = AbstractIngredient[
    Salt(Gypsum()), Salt(CalciumChloride()), Salt(EpsomSalt()), Salt(MagnesiumChloride()),
    Salt(TableSalt()), Salt(BakingSoda()), Salt(Chalk()), Salt(SlakedLime()),
    Acid(LacticAcid()), Acid(PhosphoricAcid())]

"""
    library(s::Session)

The `Library` of ingredients of the session (empty unless given), whose ingredients can be
added to the quiver (see [`catalog`](@ref)). Set it with [`set_library!`](@ref).
"""
library(s::Session) = s.library

"""
    set_library!(s::Session, lib::Library)
    set_library!(s::Session, paths::AbstractString...)

Gives the session the library `lib`, or the library of the BeerJSON documents at `paths`
(their fermentables, hops and cultures; see `Library` of BrewQuiver). It is not part of the
quiver, nor of its history.
"""
set_library!(s::Session, lib::Library) = (s.library = lib; s)
set_library!(s::Session, paths::AbstractString...) = set_library!(s, Library(paths...))

"""
    catalog(s::Session) -> Dict{String, AbstractIngredient}

The ingredients that can be added to the quiver of `s`, by name: the salts and acids of
[`WATER_AGENTS`](@ref), those of the [`STARTER_LIBRARY`](@ref), of the [`library`](@ref) of
the session, and of the lots of its quiver, each taking precedence over the ones before (the
files of quivers refer to ingredients by name, so a name stands for one ingredient).
"""
function catalog(s::Session)
    out = Dict{String, AbstractIngredient}(i.name => i for i in WATER_AGENTS)
    for n in keys(STARTER_LIBRARY)
        out[n] = STARTER_LIBRARY[n]
    end
    for n in keys(s.library)
        out[n] = s.library[n]
    end
    q = s.quiver
    for n in nodes(q), p in q[n].initial.solids
        p isa Portion && (out[p.ingredient.name] = p.ingredient)
    end
    return out
end

"""
    find_ingredient(s::Session, text) -> AbstractIngredient

The ingredient of the [`catalog`](@ref) of `s` named `text` (ignoring case), or else the
only one whose name contains it. Throws an `ArgumentError` naming the candidates when
several match, or saying that none does.
"""
function find_ingredient(s::Session, text::AbstractString)
    c = catalog(s)
    t = lowercase(strip(text))
    isempty(t) && throw(ArgumentError("give the name of an ingredient"))
    for (n, i) in c
        lowercase(n) == t && return i
    end
    found = sort!([n for n in keys(c) if occursin(t, lowercase(n))])
    length(found) == 1 && return c[only(found)]
    isempty(found) && throw(ArgumentError("there is no ingredient named $(repr(String(strip(text))))"))
    throw(ArgumentError("$(repr(String(strip(text)))) could be " *
                        join((repr(n) for n in first(found, 8)), ", ") * (length(found) > 8 ? ", ..." : "")))
end
