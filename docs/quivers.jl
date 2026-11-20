# Quivers for the examples of the documentation (as in the tests).

using Unitful, UnitfulBrewing, BrewingFormulas, BrewQuiver

const pale = Fermentable("Pale ale malt"; yield = 80u"percent", color = 3u"°L")
const crystal = Fermentable("Crystal 60"; yield = 74u"percent", color = 60u"°L")
const cascade = Hop("Cascade"; alpha = 6u"percent")
const us05 = Culture("US-05"; attenuation = 78u"percent")
const dextrose = Fermentable("Corn sugar"; kind = :sugar, yield = 100u"percent", moisture = 0)

# the single batch of the README of BrewQuiver
function single_batch()
    q = Quiver()
    add!(q, :pale, pale => 4.5u"kg")
    add!(q, :crystal, crystal => 0.3u"kg")
    add!(q, :cascade, cascade => 50u"g")
    add!(q, :yeast, us05 => 1)
    add!(q, :strike_water, water(16u"L"; temperature = 75u"°C"))
    add!(q, :sparge_water, water(14u"L"; temperature = 80u"°C"))
    add!(q, :priming_sugar, dextrose => 130u"g")
    add!(q, :mash, :rested, :grain_bed; vessel = :mashtun)
    add!(q, :kettle, :wort, :chilled; vessel = :kettle)
    add!(q, :fermentor, :beer; vessel = :fermentor)
    add!(q, :bottling, :bottles; vessel = :bottles)
    connect!(q, [:strike_water, :pale, :crystal] => :mash)
    connect!(q, :mash => :rested, MashRest(temperature = 67u"°C", time = 60u"minute"))
    connect!(q, :rested => :kettle, Drain(absorption = 1.0u"L/kg"))
    connect!(q, :rested => :grain_bed)
    connect!(q, :sparge_water => :grain_bed)
    connect!(q, :grain_bed => :kettle, Drain(absorption = 1.0u"L/kg"))
    connect!(q, :cascade => :kettle, Transfer(25u"g"; remaining = 60u"minute"))
    connect!(q, :cascade => :kettle, Transfer(25u"g"; remaining = 10u"minute"))
    connect!(q, :kettle => :wort, Boil(time = 60u"minute", evaporation = 4u"L/hr"))
    connect!(q, :wort => :chilled, Chill(temperature = 19u"°C"))
    connect!(q, :chilled => :fermentor, Drain(retain = 1u"L"))
    connect!(q, :yeast => :fermentor)
    connect!(q, :fermentor => :beer, Ferment(temperature = 19u"°C", time = 14u"d"))
    connect!(q, :priming_sugar => :bottling)
    connect!(q, :beer => :bottling, Drain(retain = 1u"L"))
    connect!(q, :bottling => :bottles, Prime(sugar = CornSugar()))
    return q
end

# a quiver that does not brew: the transfers take more than there is
function overdrawn()
    q = Quiver()
    add!(q, :w, water(10u"L"))
    add!(q, :a, :b)
    connect!(q, :w => :a, Transfer(6u"L"))
    connect!(q, :w => :b, Transfer(6u"L"))
    return q
end

# the JSON document of a quiver, to compare quivers
document(q::Quiver) = (io = IOBuffer(); writejson(io, q); String(take!(io)))
