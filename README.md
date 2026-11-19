# BrewQuiverUICore

[![CI](https://github.com/JuliaBrewing/BrewQuiverUICore.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JuliaBrewing/BrewQuiverUICore.jl/actions/workflows/ci.yml)

The frontend-neutral core of the user interfaces of
[BrewQuiver.jl](https://github.com/JuliaBrewing/BrewQuiver.jl): plain Julia data and
functions, with no terminal or graphics dependencies, shared by the terminal interface
(BrewQuiverTerm.jl) and the graphical one (BrewQuiverApp.jl).

This package is **under development** and not registered. It takes BrewQuiver and its
siblings from GitHub through the `[sources]` of `Project.toml` (Julia 1.11 or later).

Brewing itself is not here: what is useful without an interface belongs in BrewQuiver, and
formulas in BrewingFormulas.jl.

## Sessions

A `Session` holds a quiver being edited, the path of its file, its latest brew, the state of
the brew, the nodes whose results changed in the last step, the warnings of the brew and the
selection.

```julia
using BrewQuiverUICore

s = open_session("bitter.quiver.json")       # or Session(q), or import_recipe("recipe.json")
result(s)[:bottles]                           # the latest BrewResult
status(s)                                     # Brewed() or BrewFailed(exception)
changed(s)                                    # nodes whose results changed in the last step
warnings(s, :kettle)                          # e.g. the vessel is overfilled
select!(s, NodeRef(:kettle))                  # or ArrowRef(:hops => :kettle, 2)
select!(s, Add(), NodeRef(:wort))             # add to the selection
save!(s)                                      # or save!(s, path)
```

- After an edit, the brew is updated with `rebrew!` from the earliest affected nodes,
  falling back to a whole `brew`, on a copy of the previous result: an edit after which the
  quiver no longer brews is refused, and the session keeps its previous quiver and brew. A
  quiver loaded in a state that does not brew opens with `BrewFailed`, and can be edited
  until it brews.
- `changed(s)` lists the nodes whose contents or leftover differ (`≈`) from the previous
  brew, not all the nodes that were recomputed.
- The warnings logged by BrewQuiver (e.g. by the import of a recipe) are collected into
  `warnings(s)`, as `BrewWarning(node, message)`, instead of going to the terminal.
- Arrows are referred to by `ArrowRef(source, destination, index)`: there may be several
  arrows between the same two nodes, kept in order.

Coming next: edit commands, undo and redo with transactions, view data, and layout.

## The nodeview convention

`nodeview(q, label)` of BrewQuiver is a `Dict{String, Any}` of free data for interfaces,
saved in the files of quivers. All the frontends use these keys:

| key          | value                                  | meaning                                                 |
|--------------|----------------------------------------|---------------------------------------------------------|
| `"position"` | `[x, y]`, numbers                      | position in abstract layout units (one unit per layer and per slot, `x` growing downstream, `y` downwards); frontends scale it |
| `"collapsed"`| `Bool`                                 | the node is shown collapsed (its details hidden)        |
| `"color"`    | `"#rrggbb"`                            | a color chosen by the user, overriding the color of the beer (from its SRM) |
| `"note"`     | `String`                               | a note of the user about the node                       |

A frontend keeps its own data under its prefix: `"term."` for BrewQuiverTerm,
`"app."` for BrewQuiverApp (e.g. `"app.size" => [w, h]`). Keys without a prefix are
reserved for this convention; propose new ones here.

## License

MIT.
