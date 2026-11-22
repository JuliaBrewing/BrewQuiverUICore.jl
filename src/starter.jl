# A starter library of common ingredients, with typical values, so that a quiver can be built
# before a library of one's own is loaded: always in the catalog of a session, below the
# library of the session (which wins on equal names).

_malt(name, yield, color; kw...) = Fermentable(name; yield = yield * u"percent", color = color * u"°L", kw...)
_sugar(name, yield, color; kw...) =
    Fermentable(name; kind = :sugar, yield = yield * u"percent", color = color * u"SRM", moisture = 0, kw...)

"""
    STARTER_LIBRARY

A `Library` of common malts, adjuncts, sugars, extracts, hops and yeasts, with typical values
(the yield, color and alpha acids of a given lot vary: check those of yours). It is part of
the [`catalog`](@ref) of every session, below the [`library`](@ref) of the session, and is
never written with it.
"""
const STARTER_LIBRARY = let lib = Library()
    for i in AbstractIngredient[
            # base malts
            _malt("Pale ale malt", 80, 3), _malt("Maris Otter", 81, 3), _malt("Pilsner malt", 81, 1.6),
            _malt("Two-row pale malt", 79, 1.8), _malt("Vienna malt", 78, 3.5), _malt("Munich malt", 77, 9),
            _malt("Dark Munich malt", 75, 20), _malt("Wheat malt", 82, 2), _malt("Rye malt", 76, 3.5),
            _malt("Smoked malt", 79, 5), _malt("Acidulated malt", 58, 2),
            # adjuncts
            _malt("Flaked oats", 70, 1), _malt("Flaked barley", 70, 1.7), _malt("Flaked maize", 82, 0.5),
            _malt("Torrified wheat", 79, 1.5),
            # specialty malts
            _malt("Dextrin malt", 72, 1.5), _malt("Crystal 15", 75, 15), _malt("Crystal 40", 74, 40),
            _malt("Crystal 60", 74, 60), _malt("Crystal 120", 72, 120), _malt("Special B", 65, 145),
            _malt("Biscuit malt", 75, 25), _malt("Victory malt", 75, 28), _malt("Aromatic malt", 78, 20),
            _malt("Melanoidin malt", 77, 27), _malt("Pale chocolate malt", 65, 200),
            _malt("Chocolate malt", 60, 350), _malt("Roasted barley", 55, 300), _malt("Black malt", 55, 500),
            _malt("Carafa Special II", 65, 430),
            # sugars and extracts
            _sugar("Table sugar", 100, 0), _sugar("Corn sugar", 100, 0), _sugar("Invert sugar", 100, 1),
            _sugar("Dark candi syrup", 75, 80), _sugar("Honey", 75, 1),
            Fermentable("Light dry malt extract"; kind = :dry_extract, yield = 95u"percent",
                        color = 4u"SRM", moisture = 3u"percent"),
            Fermentable("Light liquid malt extract"; kind = :extract, yield = 80u"percent",
                        color = 4u"SRM", moisture = 18u"percent"),
            # hops (alpha acids)
            Hop("Amarillo"; alpha = 9u"percent"), Hop("Cascade"; alpha = 6u"percent"),
            Hop("Centennial"; alpha = 10u"percent"), Hop("Challenger"; alpha = 7.5u"percent"),
            Hop("Chinook"; alpha = 13u"percent"), Hop("Citra"; alpha = 12.5u"percent"),
            Hop("Columbus"; alpha = 15u"percent"), Hop("East Kent Goldings"; alpha = 5u"percent"),
            Hop("Fuggle"; alpha = 4.5u"percent"), Hop("Galaxy"; alpha = 14u"percent"),
            Hop("Hallertau Mittelfrüh"; alpha = 4u"percent"), Hop("Magnum"; alpha = 13u"percent"),
            Hop("Mosaic"; alpha = 12.5u"percent"), Hop("Motueka"; alpha = 7u"percent"),
            Hop("Nelson Sauvin"; alpha = 12u"percent"), Hop("Northern Brewer"; alpha = 8.5u"percent"),
            Hop("Perle"; alpha = 8u"percent"), Hop("Saaz"; alpha = 3.5u"percent"),
            Hop("Simcoe"; alpha = 13u"percent"), Hop("Sorachi Ace"; alpha = 12u"percent"),
            Hop("Spalt"; alpha = 4.5u"percent"), Hop("Styrian Golding"; alpha = 5u"percent"),
            Hop("Target"; alpha = 10.5u"percent"), Hop("Tettnang"; alpha = 4.5u"percent"),
            Hop("Warrior"; alpha = 16u"percent"), Hop("Willamette"; alpha = 5u"percent"),
            # yeasts (apparent attenuation)
            Culture("US-05"; attenuation = 80u"percent", form = :dry),
            Culture("S-04"; attenuation = 74u"percent", form = :dry),
            Culture("Nottingham"; attenuation = 80u"percent", form = :dry),
            Culture("Windsor"; attenuation = 70u"percent", form = :dry),
            Culture("T-58"; attenuation = 75u"percent", form = :dry),
            Culture("WB-06"; attenuation = 78u"percent", form = :dry),
            Culture("BE-256"; attenuation = 84u"percent", form = :dry),
            Culture("W-34/70"; attenuation = 83u"percent", kind = :lager, form = :dry),
            Culture("S-23"; attenuation = 80u"percent", kind = :lager, form = :dry),
            Culture("WLP001 California Ale"; attenuation = 76u"percent"),
            Culture("WLP002 English Ale"; attenuation = 68u"percent"),
            Culture("Wyeast 1056 American Ale"; attenuation = 75u"percent"),
            Culture("Wyeast 1968 London ESB"; attenuation = 69u"percent"),
            Culture("Wyeast 3068 Weihenstephan Weizen"; attenuation = 75u"percent"),
            Culture("Wyeast 3711 French Saison"; attenuation = 82u"percent"),
            Culture("Wyeast 2124 Bohemian Lager"; attenuation = 75u"percent", kind = :lager)]
        push!(lib, i)
    end
    lib
end

# ---------------------------------------------------------------------------------------
# searching the catalog

"""
    search_ingredients(s::Session, text = ""; role = nothing) -> Vector{String}

The names of the ingredients of the [`catalog`](@ref) of `s` matching `text`, best first:
each word of `text` must start a word of the name, or else be found in it (ignoring case);
the names starting with `text` come first, then those with a word starting with it, then
the others, each in alphabetical order. With a `role` (`:fermentable`, `:hop`, `:culture`,
`:agent`, see [`unit_role`](@ref)), only the ingredients of that role. For completing what
is typed, and for lists of ingredients to choose from.
"""
function search_ingredients(s::Session, text::AbstractString = ""; role = nothing)
    c = catalog(s)
    words = split(lowercase(text))
    rank(name) = begin
        n = lowercase(name)
        all(w -> occursin(w, n), words) || return nothing
        startswith(n, lowercase(strip(text))) && return 1
        nw = split(n, r"[\s\-/()]+")
        all(w -> any(startswith(x, w) for x in nw), words) && return 2
        return 3
    end
    found = Tuple{Int, String}[]
    for (name, i) in c
        role === nothing || unit_role(i) === role || continue
        r = rank(name)
        r === nothing || push!(found, (r, name))
    end
    return [name for (_, name) in sort!(found; by = x -> (x[1], _natural(x[2])))]
end

# a key sorting names in natural order: "Crystal 15" before "Crystal 120"
_natural(name) = replace(lowercase(name), r"\d+" => m -> lpad(m, 6, '0'))
