# Concepts

## The session

A [`Session`](@ref) is what an interface edits: a quiver of BrewQuiver, the path of its
file, the models it is brewed with, and

- its latest brew ([`result`](@ref)), kept up to date after every edit by `rebrew!` from
  the nodes the edit affected, falling back to a whole `brew`;
- the state of the brew ([`status`](@ref)): [`Brewed`](@ref), or [`BrewFailed`](@ref) for a
  quiver loaded in a state that does not brew;
- the nodes whose results changed in the last step ([`changed`](@ref)): those whose
  contents or leftover differ from the previous brew, for interfaces to highlight;
- the [`warnings`](@ref) of the brew (vessels overfilled; what BrewQuiver logs, e.g. when
  importing a recipe, collected rather than printed);
- the [`selection`](@ref): nodes ([`NodeRef`](@ref)) and arrows ([`ArrowRef`](@ref)), the
  last being the primary one;
- the [`History`](@ref) of the edits;
- a [`library`](@ref) of ingredients to add.

Sessions are made with [`Session`](@ref), [`open_session`](@ref) (a file of a quiver) or
[`import_recipe`](@ref) (a BeerJSON recipe), and saved with [`save!`](@ref).

## Commands

Interfaces change the quiver only through **commands**, [`EditCommand`](@ref)s applied with
[`apply!`](@ref). A command is a plain value: `SetAmount(:pale, 4.8u"kg")`,
`Connect(:hops => :kettle, Transfer(20u"g"; remaining = 10u"minute"))`. Each one

- **validates** itself, and BrewQuiver checks the rules of the quiver (no cycles, a
  transformation alone, one drain) before changing anything: a refused command throws a
  [`CommandError`](@ref) and leaves the session as it was;
- knows the nodes it **affects**, from which the brew is updated;
- **describes** itself ("Set :pale to 4.8 kg"), for menus and history lists;
- records what **reverts** it exactly, before it is applied: an [`Inverse`](@ref) command
  (set back the old amount) or a [`Snapshot`](@ref) of the whole quiver, for the edits whose
  inverse would be error-prone (removing a node with its arrows in their order).

An edit after which a quiver that brewed no longer brews (a drain with not enough liquid, a
fermentation without yeast) is refused too, and reverted: the quiver of a session always
brews, unless it was loaded broken, in which case it can be edited until it brews.

Layout-only commands ([`MoveNode`](@ref), [`SetView`](@ref)) keep the brew.

## History

The [`History`](@ref) of a session has an undo and a redo stack of steps. A step is a
command, several grouped in a **transaction** (a node dragged across many frames, a form,
a paste), or several **merged** (the same field typed into, within a short window). Undo
reverts a step with its records and restores the brew and the selection; redo applies its
commands again. A **saved marker** tells whether the session has unsaved changes, also
after undoing back to the saved state. The history lives in memory only: it is not written
to the files.

## View data

Frontends render plain data, with Unitful quantities: [`NodeSummary`](@ref) (the results of
a node, its display color, its warnings, whether it changed or is selected),
[`ArrowSummary`](@ref), [`node_detail`](@ref), [`results_table`](@ref),
[`timeline_rows`](@ref), [`vessel_bookings`](@ref), [`solution_rows`](@ref), and the
[`fields`](@ref) of arrows and equipment for forms. [`format`](@ref) shows a quantity with
the decimals of its unit, and [`parse_value`](@ref) reads back what users type.

## Layout and the nodeview convention

`nodeview(q, label)` of BrewQuiver is a dictionary of free data for interfaces, kept in the
files of quivers. All frontends use these keys:

| key          | value              | meaning                                                                                     |
|--------------|--------------------|---------------------------------------------------------------------------------------------|
| `"position"` | `[x, y]`, numbers  | position in abstract layout units: one per layer (`x`, downstream) and per slot (`y`, downwards) |
| `"collapsed"`| `Bool`             | the node is shown collapsed                                                                 |
| `"color"`    | `"#rrggbb"`        | a color chosen by the user, overriding that of the beer                                     |
| `"note"`     | `String`           | a note of the user about the node                                                           |

A frontend keeps its own data under its prefix: `"term."` for BrewQuiverTerm, `"app."` for
BrewQuiverApp. [`SetView`](@ref) checks the keys without a prefix against this convention.
[`layout`](@ref) computes positions in these units, and [`positions`](@ref) gives the
stored ones or the computed ones for the nodes without.
