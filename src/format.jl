# Formatting of quantities for display: each unit with its number of decimals.

"""
    display_digits(unit)

The number of decimals a quantity in `unit` is shown with (see [`format`](@ref)), or
`nothing` for three significant digits. Methods for new units extend it.
"""
display_digits(::Unitful.Units) = nothing
for (u, d) in ((u"sg", 3), (u"°P", 1), (u"L", 1), (u"mL", 0), (u"kg", 2), (u"g", 0), (u"mg", 0),
               (u"percent", 1), (u"IBU", 0), (u"SRM", 1), (u"EBC", 0), (u"vols", 2), (u"°C", 1),
               (u"°F", 0), (u"minute", 0), (u"hr", 1), (u"d", 1), (u"mg/L", 0), (u"L/kg", 2),
               (u"L/hr", 1), (u"hr^-1", 2), (u"L/minute", 1), (u"g/mL", 3))
    @eval display_digits(::typeof($u)) = $d
end

"""
    display_unit(x::Unitful.Quantity)

The unit `x` is shown in by [`format`](@ref): masses below 1 kg in g, below 1 g in mg,
volumes below 1 L in mL, and other quantities in their own unit.
"""
display_unit(x::Unitful.Quantity) = unit(x)
display_unit(x::Unitful.Mass) = (m = abs(x); m ≥ 1u"kg" ? u"kg" : m ≥ 1u"g" || iszero(m) ? u"g" : u"mg")
display_unit(x::Unitful.Volume) = abs(x) ≥ 1u"L" || iszero(x) ? u"L" : u"mL"

# the symbol of a unit, as shown: "mg/L" for mg L^-1
function unit_symbol(u::Unitful.Units)
    num, den = String[], String[]
    for t in split(string(u), ' ')
        m = match(r"^(.*?)(\^-?\d+)?$", t)
        name = get(_SYMBOLS, m[1], m[1])
        e = m[2] === nothing ? "" : m[2]
        startswith(e, "^-") ? push!(den, e == "^-1" ? name : name * "^" * e[3:end]) : push!(num, name * e)
    end
    isempty(den) && return join(num, "·")
    return (isempty(num) ? "1" : join(num, "·")) * "/" * join(den, "/")
end
unit_symbol(::typeof(u"percent")) = "%"
const _SYMBOLS = Dict("minute" => "min", "hr" => "h")

"""
    format(x; unit = display_unit(x), digits = display_digits(unit))

`x` as a string for display, e.g. `"1.052 sg"`, `"23.1 L"`, `"300 g"`, `"5.2 %"`,
`"35 IBU"`. Plain numbers are shown with two decimals (a pH), `missing` and `nothing` as
`"–"`.
"""
function format(x::Unitful.Quantity; unit = display_unit(x), digits = display_digits(unit))
    v = ustrip(unit, x)
    return _number(v, digits) * (unit == u"percent" ? "" : " ") * unit_symbol(unit)
end
format(x::Real; digits = 2) = _number(x, digits)
format(x::Integer; digits = 0) = string(x)
format(::Missing; kwargs...) = "–"
format(::Nothing; kwargs...) = "–"
format(x::AbstractString; kwargs...) = String(x)
format(x::Symbol; kwargs...) = ":" * String(x)
format(t::Remaining; kwargs...) = format(t.time) * " remaining"
format(t::At; kwargs...) = "at " * format(t.time)

function _number(v::Real, digits)
    digits === nothing && return _sig(v)
    return Printf.format(Printf.Format("%.$(digits)f"), v)
end
function _sig(v)
    r = round(v; sigdigits = 3)
    return isinteger(r) && abs(r) < 1e15 ? string(Int(r)) : string(r)
end
