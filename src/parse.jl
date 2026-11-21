# Parsing what a user types into a value: the inverse of `format`, for the text boxes and
# prompts of the frontends.

# the symbols shown by `format` that Unitful does not read, and the aliases of units that
# need a symbol hard to type (°C, °F, °P, °L) or that brewers write otherwise; a letter that
# Unitful reads as another unit (C coulomb, F farad, P poise) means here the unit of brewing
const _UNIT_WORDS = Dict(
    "%" => "percent", "min" => "minute", "mins" => "minute", "h" => "hr", "hrs" => "hr",
    "days" => "d", "day" => "d", "l" => "L", "ml" => "mL",
    # temperatures
    "C" => "°C", "c" => "°C", "degC" => "°C", "ºC" => "°C", "°c" => "°C",
    "F" => "°F", "f" => "°F", "degF" => "°F", "ºF" => "°F", "°f" => "°F",
    # gravities and colors
    "P" => "°P", "plato" => "°P", "Plato" => "°P", "degP" => "°P", "ºP" => "°P",
    "brix" => "Brix", "SG" => "sg", "srm" => "SRM", "ebc" => "EBC",
    "lovibond" => "°L", "Lovibond" => "°L", "degL" => "°L", "ºL" => "°L",
    # others
    "ibu" => "IBU", "vol" => "vols", "lbs" => "lb", "ppm" => "mg/L")

const _NUMBER = r"^\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*(.*?)\s*$"

"""
    parse_value(text; unit = nothing) -> value
    parse_value(text, current) -> value

What a user typed, as a value for an edit command: a quantity (`"4.8 kg"`, `"1.050 sg"`,
`"95%"`, `"70 min"`, `"4 L/h"`, `"80 °C"`, `"2.4 vols"`, any unit of Unitful or
UnitfulBrewing, and aliases for the units with symbols hard to type or that brewers write
otherwise: `C` and `F` for °C and °F (`"70 C"`, `"158F"`), `P` or `plato` for °P,
`lovibond` for °L, `srm`, `ebc`, `brix`, `ibu`, `SG`, `vol`, `lbs`, `ppm`), a plain number (`"2"`, `"0.95"`), `nothing` (`""`, `"-"`, `"–"`,
`"nothing"`, `"none"`: leave it to the vessel or the default), a timing
(`"10 min remaining"`, `"at 70 min"`), or `true`/`false`. It reads what [`format`](@ref)
writes. Throws an `ArgumentError` with a readable message otherwise.

A number typed without a unit is in `unit`, if given: with `unit = u"L"`, `"25"` is 25 L,
and `"2500 mL"` is 2500 mL. With the `current` value of what is edited, it is in the unit
that value is shown in (see [`display_unit`](@ref)): `"25"` replacing 27 L is 25 L,
`"250"` replacing 300 g is 250 g, and `"5 remaining"` replacing `10 min remaining` is 5
minutes remaining. No unit is guessed from the size of the number.

The value is checked and converted by the command it goes to (e.g. a percentage becomes a
fraction in [`SetArrowField`](@ref)).
"""
parse_value(text::AbstractString, current) = parse_value(text; unit = input_unit(current))

function parse_value(text::AbstractString; unit::Union{Nothing, Unitful.Units} = nothing)
    t = strip(text)
    lowercase(t) in ("", "-", "–", "nothing", "none") && return nothing
    lowercase(t) == "true" && return true
    lowercase(t) == "false" && return false
    m = match(r"^(.*?)\s+remaining$"i, t)
    m === nothing || return Remaining(_time(parse_value(m[1]; unit), text))
    m = match(r"^at\s+(.*)$"i, t)
    m === nothing || return At(_time(parse_value(m[1]; unit), text))
    m = match(_NUMBER, t)
    m === nothing && throw(ArgumentError("$(repr(String(text))) is not a number with a unit, e.g. 4.8 kg"))
    x = parse(Float64, m[1])
    isempty(m[2]) && return unit === nothing ? x : x * unit
    return x * _unit(m[2], text)
end

"""
    input_unit(current)

The unit a number typed without one is read in, when it replaces `current` (see
[`parse_value`](@ref)): the unit `current` is shown in, for a quantity or a timing;
`nothing` for anything else.
"""
input_unit(x::Unitful.Quantity) = display_unit(x)
input_unit(t::Union{Remaining, At}) = input_unit(t.time)
input_unit(x) = nothing

function _unit(u::AbstractString, text)
    s = join((get(_UNIT_WORDS, w, w) for w in split(u, r"(?=[/*·^ ])|(?<=[/*·^ ])")), "")
    s = replace(s, "·" => "*", r"\s+" => "*")
    x = try
        uparse(s; unit_context = [Unitful, UnitfulBrewing])
    catch
        nothing
    end
    # ("1/h" is read as a quantity of 1)
    x isa Unitful.Quantity && isone(ustrip(x)) && (x = unit(x))
    x isa Unitful.Units || throw(ArgumentError("$(repr(String(u))) in $(repr(String(text))) is not a unit"))
    return x
end

_time(t::Unitful.Time, text) = t
_time(t, text) = throw(ArgumentError("a timing is a time, e.g. 10 min remaining or at 70 min, not $(repr(String(text)))"))
