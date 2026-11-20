# Writing a frontend

A frontend holds a [`Session`](@ref), renders its view data, and turns what users do into
commands. These are the patterns BrewQuiverTerm follows, and that a graphical frontend can
follow too.

## Rendering

- Draw from [`node_summaries`](@ref), [`arrow_summaries`](@ref) and [`positions`](@ref),
  never from the quiver directly: they carry what changed, what is selected, the warnings
  and the colors.
- Get the quiver with `quiver(s)` each time: undoing a structural edit restores a snapshot,
  which replaces it.
- Highlight `changed(s)` after every step; show `status(s)` and the count of `warnings(s)`
  in a status bar, with `undo_description(s)` for the Undo menu.

## Selection

Keep the cursor in the session: `select!(s, NodeRef(:kettle))`, and
`select!(s, Add(), ref)` for a click with shift. Undo and redo restore it, a renamed node
keeps it, and removed items leave it.

## Editing

| interaction | how |
|---|---|
| a number box | parse each change with [`parse_value`](@ref) and apply it (`SetAmount`, `SetArrowField`, `SetEquipmentField`); the edits merge into one step |
| a form of several fields | apply them in a [`transaction`](@ref) |
| dragging a node | [`begin_transaction!`](@ref), a [`MoveNode`](@ref) per frame, [`commit!`](@ref) on release, [`abort!`](@ref) on Escape |
| "arrange" | [`layout!`](@ref) |
| adding a lot | a picker over [`catalog`](@ref), or [`find_ingredient`](@ref) on what is typed, then [`AddNode`](@ref) |
| a refused edit | show the message of the [`CommandError`](@ref): the session is unchanged |
| quitting, opening | ask when [`isdirty`](@ref) |

## Data of the frontend

Keep what only your frontend needs in the nodeviews under your prefix (`"app.size"`,
`"term.folded"`), set with [`SetView`](@ref) so that it is undoable and saved with the
quiver; propose new unprefixed keys for the convention in this package.

## Engine additions

What is useful outside any interface belongs in BrewQuiver: propose it there, and wrap it
here in a command.
