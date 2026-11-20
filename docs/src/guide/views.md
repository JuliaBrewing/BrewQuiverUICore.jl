# View data and layout

```@setup views
using BrewQuiverUICore, BrewQuiver, Unitful, UnitfulBrewing
include(joinpath(pkgdir(BrewQuiverUICore), "docs", "quivers.jl"))
s = Session(single_batch())
```

Frontends render plain data with Unitful quantities, `missing` where a value does not
apply, and format them at the last moment.

## Formatting and parsing

[`format`](@ref) shows a quantity with the decimals of its unit ([`display_digits`](@ref)),
in a display unit ([`display_unit`](@ref): grams below a kilogram, millilitres below a
litre):

```@example views
format.([1.0523u"sg", 23.14u"L", 0.3u"kg", 5.23u"percent", 34.6u"IBU", 4u"L/hr", 60u"minute"])
```

[`parse_value`](@ref) reads what users type, and what `format` writes:

```@example views
parse_value.(["4.8 kg", "95%", "70 min", "4 L/h", "10 min remaining", "–"])
```

A number typed without a unit is in the unit of the value it replaces, as shown
([`input_unit`](@ref)): no unit is guessed from its size.

```@example views
parse_value("25", 27.0u"L"), parse_value("2500 mL", 27.0u"L"), parse_value("250", 0.3u"kg")
```

## Nodes and arrows

```@example views
x = node_summary(s, :wort)
(x.kind, format(x.volume), format(x.gravity), format(x.ibu), x.color)
```

```@example views
[(a.source, a.destination, a.index, a.kind, format(a.moved_mass)) for a in arrow_summaries(s)][1:4]
```

[`node_color`](@ref) is the user's color, or the color of the beer from its SRM, or that of
the malt of a lot. [`vessel_groups`](@ref) groups the nodes by vessel, the lots first:

```@example views
vessel_groups(s)
```

[`node_detail`](@ref) has everything an inspector shows: the summary, the initial contents,
the contents and leftover in the brew (with [`solid_rows`](@ref), [`liquor_rows`](@ref) and
[`mineral_rows`](@ref)), and the arrows in and out.

```@example views
[(r.name, format(r.amount), format(r.timing)) for r in solid_rows(node_detail(s, :kettle).contents)]
```

[`fields`](@ref) describes the fields of an arrow or of equipment, for forms, with the units
they accept:

```@example views
[(f.label, format(f.value), string.(f.units), f.optional ? "optional" : "") for f in fields(Boil())]
```

## Tables, timeline and solutions

```@example views
t = results_table(s)
t.header
```

```@example views
k = only(r for r in timeline_rows(s; start = 8u"hr") if r.label == :kettle)
(k.label, k.vessel, uconvert(u"hr", k.arrive), uconvert(u"hr", k.leave))
```

```@example views
b = vessel_bookings(s)
([v for (v, _) in b.vessels], format(uconvert(u"d", b.makespan)), b.overlaps)
```

[`solution_rows`](@ref) shows the solution of a [`Solve`](@ref):

```@example views
sol = apply!(s, Solve(:fermentor => gravity => 1.050u"sg", Amount(:pale, :crystal)))
[(t.node, t.quantity, format(t.goal), format(t.reached)) for t in solution_rows(sol).targets]
```

## Layout

[`layout`](@ref) places each node in the layer of its longest path from a source (a lot
just before its first destination), and orders the layers by barycenters, keeping the nodes
of each vessel together:

```@example views
p = layout(quiver(s))
[n => p[n] for n in (:pale, :mash, :kettle, :wort, :fermentor)]
```

[`layout!`](@ref) writes the positions into the nodeviews as one undoable step, and
[`positions`](@ref) gives the stored positions, or the layout for the nodes without one.
[`crossings`](@ref) counts the arrows that cross:

```@example views
crossings(quiver(s), p)
```
