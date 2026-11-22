# Templates: quivers to start from, of the usual shapes of brews, with the ingredients of the
# starter library (to be changed for one's own).

_ing(name) = STARTER_LIBRARY[name]

# the hot side of a batch: a mash with a sparge, its runnings drained into `first` and
# `second` (stages already added)
function _mash_and_sparge!(q, grist, strike, sparge; first = :kettle, second = first)
    for (label, name, amount) in grist
        add!(q, label, _ing(name) => amount)
    end
    add!(q, :strike_water, water(strike; temperature = 75u"°C"))
    add!(q, :sparge_water, water(sparge; temperature = 80u"°C"))
    add!(q, :mash, :rested, :grain_bed; vessel = :mashtun)
    connect!(q, [:strike_water; [g[1] for g in grist]] => :mash)
    connect!(q, :mash => :rested, MashRest(temperature = 67u"°C", time = 60u"minute"))
    connect!(q, :rested => first, Drain(absorption = 1.0u"L/kg"))
    connect!(q, :rested => :grain_bed)
    connect!(q, :sparge_water => :grain_bed)
    connect!(q, :grain_bed => second, Drain(absorption = 1.0u"L/kg"))
    return q
end

# a boil with two hop additions, chilled
function _boil!(q, kettle, wort, chilled, hops, (bittering, aroma))
    connect!(q, hops => kettle, Transfer(bittering; remaining = 60u"minute"))
    connect!(q, hops => kettle, Transfer(aroma; remaining = 10u"minute"))
    connect!(q, kettle => wort, Boil(time = 60u"minute", evaporation = 4u"L/hr"))
    connect!(q, wort => chilled, Chill(temperature = 19u"°C"))
    return q
end

function _single_batch()
    q = Quiver()
    add!(q, :kettle, :wort, :chilled; vessel = :kettle)
    _mash_and_sparge!(q, [(:pale, "Pale ale malt", 4.5u"kg"), (:crystal, "Crystal 60", 0.3u"kg")],
                      16u"L", 14u"L")
    add!(q, :cascade, _ing("Cascade") => 50u"g")
    add!(q, :yeast, _ing("US-05") => 1)
    add!(q, :priming_sugar, _ing("Corn sugar") => 130u"g")
    add!(q, :fermentor, :beer; vessel = :fermentor)
    add!(q, :bottling, :bottles; vessel = :bottles)
    _boil!(q, :kettle, :wort, :chilled, :cascade, (25u"g", 25u"g"))
    connect!(q, :chilled => :fermentor, Drain(retain = 1u"L"))
    connect!(q, :yeast => :fermentor)
    connect!(q, :fermentor => :beer, Ferment(temperature = 19u"°C", time = 14u"d"))
    connect!(q, :priming_sugar => :bottling)
    connect!(q, :beer => :bottling, Drain(retain = 1u"L"))
    connect!(q, :bottling => :bottles, Prime(sugar = CornSugar()))
    return q
end

function _parti_gyle()
    q = Quiver()
    for i in 1:2
        add!(q, Symbol(:kettle, i), Symbol(:wort, i), Symbol(:chilled, i); vessel = Symbol(:kettle, i))
    end
    _mash_and_sparge!(q, [(:pale, "Maris Otter", 6.5u"kg"), (:crystal, "Crystal 60", 0.3u"kg")],
                      24u"L", 20u"L"; first = :kettle1, second = :kettle2)
    add!(q, :goldings, _ing("East Kent Goldings") => 100u"g")
    for i in 1:2
        add!(q, Symbol(:yeast, i), _ing("S-04") => 1)
        add!(q, Symbol(:fermentor, i), Symbol(:beer, i); vessel = Symbol(:fermentor, i))
    end
    _boil!(q, :kettle1, :wort1, :chilled1, :goldings, (40u"g", 20u"g"))
    _boil!(q, :kettle2, :wort2, :chilled2, :goldings, (25u"g", 15u"g"))
    for i in 1:2
        connect!(q, Symbol(:chilled, i) => Symbol(:fermentor, i), Drain(retain = 1u"L"))
        connect!(q, Symbol(:yeast, i) => Symbol(:fermentor, i))
        connect!(q, Symbol(:fermentor, i) => Symbol(:beer, i), Ferment(temperature = 19u"°C", time = 14u"d"))
    end
    return q
end

function _split_batch()
    q = Quiver()
    add!(q, :kettle, :wort, :chilled; vessel = :kettle)
    _mash_and_sparge!(q, [(:pale, "Pilsner malt", 4.5u"kg"), (:wheat, "Wheat malt", 0.5u"kg")],
                      16u"L", 14u"L")
    add!(q, :hops, _ing("Saaz") => 60u"g")
    _boil!(q, :kettle, :wort, :chilled, :hops, (40u"g", 20u"g"))
    for (i, yeast) in enumerate(("US-05", "T-58"))
        add!(q, Symbol(:yeast, i), _ing(yeast) => 1)
        add!(q, Symbol(:fermentor, i), Symbol(:beer, i); vessel = Symbol(:fermentor, i))
        connect!(q, :chilled => Symbol(:fermentor, i), i == 1 ? Transfer(50u"percent") : Drain(retain = 1u"L"))
        connect!(q, Symbol(:yeast, i) => Symbol(:fermentor, i))
        connect!(q, Symbol(:fermentor, i) => Symbol(:beer, i), Ferment(temperature = 19u"°C", time = 14u"d"))
    end
    return q
end

function _brew_in_a_bag()
    q = Quiver()
    add!(q, :pale, _ing("Pale ale malt") => 4.5u"kg")
    add!(q, :water, water(30u"L"; temperature = 72u"°C"))
    add!(q, :cascade, _ing("Cascade") => 50u"g")
    add!(q, :yeast, _ing("US-05") => 1)
    add!(q, :mash, :rested, :kettle, :wort, :chilled; vessel = :kettle)
    add!(q, :bag; vessel = :bag)
    add!(q, :fermentor, :beer; vessel = :fermentor)
    connect!(q, [:water, :pale] => :mash)
    connect!(q, :mash => :rested, MashRest(temperature = 66u"°C", time = 60u"minute"))
    connect!(q, :rested => :kettle, Drain(absorption = 1.0u"L/kg"))   # the bag lifted
    connect!(q, :rested => :bag)
    _boil!(q, :kettle, :wort, :chilled, :cascade, (25u"g", 25u"g"))
    connect!(q, :chilled => :fermentor, Drain(retain = 1u"L"))
    connect!(q, :yeast => :fermentor)
    connect!(q, :fermentor => :beer, Ferment(temperature = 19u"°C", time = 14u"d"))
    return q
end

"""
    TEMPLATES

The templates a quiver can be started from, as `name => description` (see
[`template`](@ref)): a single batch, a parti-gyle, a split batch, brew in a bag.
"""
const TEMPLATES = [
    "single batch" => "mash, sparge, boil, ferment and bottle one beer",
    "parti-gyle" => "the first and second runnings of a mash boiled and fermented apart: two beers",
    "split batch" => "one wort fermented in two fermentors, with two yeasts",
    "brew in a bag" => "mash in the kettle, the bag lifted, no sparge"]

const _TEMPLATE_BUILDERS = Dict("single batch" => _single_batch, "parti-gyle" => _parti_gyle,
                                "split batch" => _split_batch, "brew in a bag" => _brew_in_a_bag)

"""
    template(name) -> Quiver

A new quiver of the template `name` (see [`TEMPLATES`](@ref)), with the ingredients of the
[`STARTER_LIBRARY`](@ref) and typical amounts, to be changed.
"""
function template(name::AbstractString)
    f = get(_TEMPLATE_BUILDERS, name, nothing)
    f === nothing && throw(ArgumentError("$(repr(name)) is not a template: " * join((repr(first(t)) for t in TEMPLATES), ", ")))
    return f()
end
