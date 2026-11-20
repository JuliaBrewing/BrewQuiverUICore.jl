# BrewQuiverUICore.jl

The frontend-neutral core of the user interfaces of
[BrewQuiver.jl](https://github.com/JuliaBrewing/BrewQuiver.jl), the engine that models
brewing as a quiver: a directed acyclic multigraph whose nodes are the contents of vessels
at the stages of the brewing, and whose arrows are the processes between them.

BrewQuiverUICore holds what every interface needs and nothing that draws: plain Julia data
and functions, with no terminal or graphics dependencies, shared by the terminal interface
[BrewQuiverTerm.jl](https://github.com/JuliaBrewing/BrewQuiverTerm.jl) and the graphical
one, BrewQuiverApp.jl.

- an editing **session**: a quiver, its file, its latest brew, the selection, and the nodes
  that changed in the last step;
- **edit commands** that validate themselves, refuse what would break the quiver or its
  brew, and record what reverts them exactly;
- an **undo and redo history**, with transactions, merging of consecutive small edits, a
  bounded length and a saved marker;
- **view data**: summaries of nodes and arrows with their results in units, formatting and
  parsing of quantities, display colors, tables, the timeline;
- a **layered layout** of the quiver, and the convention of the data that interfaces keep
  in the files of quivers;
- an **ingredient catalog**, for adding lots.

## Installation

The package is under development and not registered. It takes BrewQuiver and its siblings
from GitHub through the `[sources]` of its `Project.toml` (Julia 1.11 or later):

```julia
using Pkg
Pkg.add(url = "https://github.com/JuliaBrewing/BrewQuiverUICore.jl")
```

## A first look

```@example tour
using BrewQuiverUICore, BrewQuiver, Unitful, UnitfulBrewing
include(joinpath(pkgdir(BrewQuiverUICore), "docs", "quivers.jl"))   # single_batch()

s = Session(single_batch())
node_summary(s, :wort).gravity
```

An edit is a command applied to the session; the brew follows, from the nodes it affects,
and the nodes whose results changed are known (those downstream of the malt, not the hops):

```@example tour
apply!(s, SetAmount(:pale, 4.8u"kg"))
format(node_summary(s, :wort).gravity), length(changed(s)), :cascade in changed(s)
```

and it can be undone:

```@example tour
undo_description(s)
```

```@example tour
undo!(s)
format(node_summary(s, :wort).gravity)
```

An edit after which the quiver would no longer brew is refused, and changes nothing:

```@example tour
try
    apply!(s, SetAmount(:strike_water, 1u"L"))
catch e
    sprint(showerror, e)
end
```

Read on with the [Concepts](@ref), then the guides.
