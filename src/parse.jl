# Parsing what a user types into a value: the inverse of `format`, for the text boxes and
# prompts of the frontends.

# the symbols shown by `format` that Unitful does not read, and their units
const _UNIT_WORDS = Dict("%" => "percent", "min" => "minute", "mins" => "minute", "h" => "hr",
                         "hrs" => "hr", "days" => "d", "day" => "d", "l" => "L", "ml" => "mL")

const _NUMBER = r"^\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*(.*?)\s*$"

"""
    parse_value(text) -> value

What a user typed, as a value for an edit command: a quantity (`"4.8 kg"`, `"1.050 sg"`,
`"95%"`, `"70 min"`, `"4 L/h"`, `"80 °C"`, `"2.4 vols"`, any unit of Unitful or
UnitfulBrewing), a plain number (`"2"`, `"0.95"`), `nothing` (`""`, `"-"`, `"–"`,
`"nothing"`, `"none"`: leave it to the vessel or the default), a timing
(`"10 min remaining"`, `"at 70 min"`), or `true`/`false`. It reads what [`format`](@ref)
writes. Throws an `ArgumentError` with a readable message otherwise.

The value is checked and converted by the command it goes to (e.g. a percentage becomes a
fraction in [`SetArrowField`](@ref)).
"""
function parse_value(text::AbstractString)
    t = strip(text)
    lowercase(t) in ("", "-", "–", "nothing", "none") && return nothing
    lowercase(t) == "true" && return true
    lowercase(t) == "false" && return false
    m = match(r"^(.*?)\s+remaining$"i, t)
    m === nothing || return Remaining(_time(parse_value(m[1]), text))
    m = match(r"^at\s+(.*)$"i, t)
    m === nothing || return At(_time(parse_value(m[1]), text))
    m = match(_NUMBER, t)
    m === nothing && throw(ArgumentError("$(repr(String(text))) is not a number with a unit, e.g. 4.8 kg"))
    x = parse(Float64, m[1])
    isempty(m[2]) && return x
    return x * _unit(m[2], text)
end

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
