# The stock of the library for the brew, and the export of the brew as BeerJSON recipes.

"""
    inventory_rows(s::Session)

What the brew of `s` uses of each ingredient (see `requirements` of BrewQuiver), with the
stock of the [`library`](@ref) of the session, as NamedTuples `(name, needed, stock,
short)`, by name: `stock` is `nothing` when the library does not have the ingredient or
does not know its stock, and `short` says whether the brew needs more than there is (or than
is known). Empty if the quiver does not brew.
"""
function inventory_rows(s::Session)
    isbrewed(s) || return @NamedTuple{name::String, needed::Union{Unitful.Quantity, Real},
                                      stock::Union{Nothing, Unitful.Quantity, Real}, short::Bool}[]
    lib = s.library
    shorts = Set(x.name for x in shortages(lib, s.result, s.quiver))
    return [(name = name, needed = needed, stock = haskey(lib, name) ? stock(lib, name) : nothing,
             short = name in shorts)
            for (name, needed) in sort!(collect(requirements(s.result, s.quiver)); by = first)]
end

"""
    consume_stock!(s::Session) -> Vector{String}

Takes from the stock of the [`library`](@ref) of `s` what its brew uses (see `consume!` of
BrewQuiver), returning the warnings for what was short. It changes the library, not the
quiver: it is not part of the history. Save the library with [`save_library`](@ref).
"""
function consume_stock!(s::Session)
    isbrewed(s) || throw(ArgumentError("the quiver does not brew: nothing to take from the stock"))
    _, messages = collecting(() -> consume!(s.library, s.result, s.quiver))
    return messages
end

"""
    save_library(s::Session, path)

Writes the [`library`](@ref) of `s`, with its stock, as a BeerJSON document at `path`.
"""
save_library(s::Session, path::AbstractString) = (writejson(path, s.library); path)

"""
    export_recipes(s::Session, path)

Writes the brew of `s` as a BeerJSON document at `path`: a recipe per product of the quiver,
with the shares of its lots (see `recipes` of BrewQuiver).
"""
function export_recipes(s::Session, path::AbstractString)
    isbrewed(s) || throw(ArgumentError("the quiver does not brew: there are no recipes to export"))
    collecting(() -> writejson(path, s.result, s.quiver))   # (its warnings are not for the user)
    return path
end
