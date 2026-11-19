# An editing session: a quiver, its file, its latest brew, and the selection.

"""
    Session(q::Quiver; path = nothing, models = (;))

An editing session of the quiver `q`, saved at `path` (or not yet saved), brewed with the
`models` of BrewingFormulas (see `brew`). It holds:

- the quiver ([`quiver`](@ref)) and its file ([`filepath`](@ref));
- its latest brew ([`result`](@ref)) and the state of the brew ([`status`](@ref)):
  [`Brewed`](@ref), or [`BrewFailed`](@ref) when the quiver was loaded in a state that does
  not brew;
- the nodes whose results changed in the last step ([`changed`](@ref)), for interfaces to
  highlight, and the [`warnings`](@ref) of the brew;
- the selection ([`selection`](@ref)): nodes and arrows.

After an edit, the brew is updated with `rebrew!` from the earliest affected nodes, falling
back to `brew`.

See also [`open_session`](@ref), [`import_recipe`](@ref), [`save!`](@ref).
"""
mutable struct Session
    quiver::Quiver
    path::Union{Nothing, String}
    models::NamedTuple
    result::Union{Nothing, BrewResult}
    status::AbstractBrewStatus
    changed::Set{Symbol}
    warnings::Vector{BrewWarning}
    # warnings that are not about the brew (e.g. of the import of a recipe), kept across brews
    notes::Vector{BrewWarning}
    selection::Vector{ItemRef}
end

function Session(q::Quiver; path::Union{Nothing, AbstractString} = nothing,
                 models::NamedTuple = (;), notes = BrewWarning[])
    s = Session(q, path === nothing ? nothing : String(path), models, nothing,
                BrewFailed(ErrorException("not brewed yet")), Set{Symbol}(), BrewWarning[],
                collect(BrewWarning, notes), ItemRef[])
    brew!(s)
    empty!(s.changed)
    return s
end

"""
    quiver(s::Session)

The quiver edited in `s`. Change it only through the edit commands, so that the brew and the
history stay consistent.
"""
quiver(s::Session) = s.quiver

"""
    filepath(s::Session)

The path of the file of the session, or `nothing` if it was never saved.
"""
filepath(s::Session) = s.path

"""
    models(s::Session)

The models of BrewingFormulas the session brews with (overriding `DEFAULT_MODELS`).
"""
models(s::Session) = s.models

"""
    result(s::Session)

The latest brew of the quiver (a `BrewResult`), or `nothing` if it never brewed.
"""
result(s::Session) = s.result

"""
    status(s::Session)

The state of the brew: [`Brewed`](@ref) or [`BrewFailed`](@ref).
"""
status(s::Session) = s.status
isbrewed(s::Session) = isbrewed(s.status)

"""
    changed(s::Session)

The labels of the nodes whose results (contents or leftover) changed in the last step: an
edit, an undo or a redo. Interfaces highlight them.
"""
changed(s::Session) = s.changed

"""
    warnings(s::Session)
    warnings(s::Session, label)

The warnings of the session ([`BrewWarning`](@ref)s): those of its latest brew (vessels
overfilled, ...) and those of loading it (e.g. the import of a recipe); or those about the
node `label`.
"""
warnings(s::Session) = vcat(s.notes, s.warnings)
warnings(s::Session, label::Symbol) = [w for w in warnings(s) if w.node === label]

# ---------------------------------------------------------------------------------------
# brewing

# a copy of a brew result that `rebrew!` can update without changing the original
_copy(r::BrewResult) = BrewResult(copy(r.nodes), copy(r.arrows), copy(r.order), copy(r.vessels),
                                  r.models)

# the brew of `q` after a change of the nodes `from`, given the previous brew `prev`; it
# throws if `q` does not brew
function _brew(q::Quiver, models::NamedTuple, prev, from)
    from = [n for n in from if haskey(q, n)]
    if prev !== nothing && !isempty(from)
        try
            r = _copy(prev)
            for n in from
                rebrew!(r, q, n)
            end
            return r
        catch
            # (fall back to a whole brew, which throws if the quiver does not brew)
        end
    end
    return brew(q; models)
end

# the nodes whose results differ between two brews
function _changed(old, new::BrewResult)
    old === nothing && return Set(new.order)
    out = Set{Symbol}()
    for n in new.order
        a = get(old.nodes, n, nothing)
        b = new.nodes[n]
        (a === nothing || !(a.contents ≈ b.contents) || !(a.leftover ≈ b.leftover)) && push!(out, n)
    end
    return out
end

function _brew_warnings(res::BrewResult, q::Quiver)
    out = BrewWarning[]
    for o in overfilled(res, q)
        push!(out, BrewWarning(o.node, "$(round(u"L", o.volume; digits = 2)) exceed the capacity " *
                                       "of $(round(u"L", o.capacity; digits = 2)) of the $(o.vessel)"))
    end
    return out
end

# install a new brew in the session
function _install!(s::Session, res::BrewResult)
    s.changed = _changed(s.result, res)
    s.result = res
    s.status = Brewed()
    s.warnings = _brew_warnings(res, s.quiver)
    return s
end

# try to bring the brew up to date after a change of the nodes `from`; returns the
# exception if the quiver does not brew, leaving the brew of the session as it was
function _rebrew!(s::Session, from)
    prev = isbrewed(s) ? s.result : nothing
    res = try
        first(collecting(() -> _brew(s.quiver, s.models, prev, from)))
    catch e
        e isa InterruptException && rethrow()
        return e
    end
    _install!(s, res)
    return nothing
end

"""
    brew!(s::Session)

Brews the quiver of `s` again, entirely (e.g. after a change of its models). Returns the
state of the brew.
"""
function brew!(s::Session)
    e = _rebrew!(s, Symbol[])
    if e !== nothing
        s.status = BrewFailed(e)
        s.result = nothing
        empty!(s.changed)
        empty!(s.warnings)
    end
    return s.status
end

# ---------------------------------------------------------------------------------------
# files

"""
    open_session(path; models = (;))

A session of the quiver saved at `path` (see `writejson` of BrewQuiver).
"""
open_session(path::AbstractString; models::NamedTuple = (;)) =
    Session(readjson(Quiver, path); path, models)

"""
    recipe_names(path)

The names of the recipes of the BeerJSON document at `path`.
"""
recipe_names(path::AbstractString) =
    [r.name for r in something(readjson(BeerJSONParser, path).beerjson.recipes, [])]

"""
    import_recipe(path, which = 1; models = (;), kwargs...)

A new, unsaved session of the quiver of a recipe of the BeerJSON document at `path`: the
recipe `which`, by index or by name (see [`recipe_names`](@ref)). The keyword arguments go
to `Quiver(recipe; ...)` of BrewQuiver (e.g. `calibration`, `library`). What the import
warns about is kept in the [`warnings`](@ref) of the session.
"""
function import_recipe(path::AbstractString, which::Union{Integer, AbstractString} = 1;
                       models::NamedTuple = (;), kwargs...)
    rs = something(readjson(BeerJSONParser, path).beerjson.recipes, [])
    r = _pick(rs, which, path)
    q, messages = collecting(() -> Quiver(r; kwargs...))
    return Session(q; models, notes = [BrewWarning(nothing, m) for m in messages])
end

function _pick(rs, i::Integer, path)
    1 ≤ i ≤ length(rs) || throw(ArgumentError("$path has $(length(rs)) recipes, not $i"))
    return rs[i]
end
function _pick(rs, name::AbstractString, path)
    i = findfirst(r -> r.name == name, rs)
    i === nothing && throw(ArgumentError("$path has no recipe named $(repr(name))"))
    return rs[i]
end

"""
    save!(s::Session, path = filepath(s))

Saves the quiver of `s` at `path` (with the values computed by its brew, for other readers
of the file), which becomes the path of the session.
"""
function save!(s::Session, path::Union{Nothing, AbstractString} = s.path)
    path === nothing && throw(ArgumentError("the session has no file yet: give a path"))
    writejson(path, s.quiver; results = isbrewed(s) ? s.result : nothing)
    s.path = String(path)
    return s
end

# ---------------------------------------------------------------------------------------
# selection

"""
    selection(s::Session)

The selected items ([`ItemRef`](@ref)s) of `s`, in the order they were selected: the last
is the primary one, e.g. the one an inspector shows.
"""
selection(s::Session) = s.selection

"""
    select!(s::Session, refs::ItemRef...)

Selects `refs`, replacing the selection. Refs to items not in the quiver are refused.
"""
function select!(s::Session, refs::ItemRef...)
    _check_refs(s, refs)
    s.selection = unique!(ItemRef[refs...])
    return s
end

"""
    select!(s::Session, Add(), refs::ItemRef...)

Adds `refs` to the selection (e.g. a click with shift), as the last selected.
"""
struct Add end
function select!(s::Session, ::Add, refs::ItemRef...)
    _check_refs(s, refs)
    s.selection = unique!(ItemRef[filter(r -> !(r in refs), s.selection); refs...])
    return s
end

"""
    deselect!(s::Session, refs::ItemRef...)

Removes `refs` from the selection.
"""
deselect!(s::Session, refs::ItemRef...) = (filter!(r -> !(r in refs), s.selection); s)

"""
    clear_selection!(s::Session)

Selects nothing.
"""
clear_selection!(s::Session) = (empty!(s.selection); s)

function _check_refs(s, refs)
    for r in refs
        isvalid_ref(s.quiver, r) || throw(ArgumentError("$r is not in the quiver"))
    end
end

# drop the refs to items no longer in the quiver (after an edit)
_prune_selection!(s::Session) = (filter!(r -> isvalid_ref(s.quiver, r), s.selection); s)
