# Layout: a layered drawing of the quiver, by topological rank, with the nodes of each vessel
# kept together, written into the "position" of the nodeview of each node.

"""
    layout(q::Quiver; sources = :before, sweeps = 8) -> Dict{Symbol, Vector{Float64}}

A layered layout of `q`: the position `[x, y]` of each node, in abstract layout units.

- `x` is the layer (the column), so that every arrow goes from left to right. The stages
  are aligned by vessel: the vessels are ranked by the longest chain of vessels before them
  (the mash tun, then the kettles, then the fermentors, ...), the vessels of a rank share
  the same columns, and the stages of a vessel take one column each, in order; so the two
  kettles of a parti-gyle are in the same column, and so are their worts. (A stage in no
  vessel is a vessel of its own. When the vessels are used in a cycle, the layer is the
  length of the longest path from a source.) The lots (the sources) are put in the first
  column with `sources = :first`, or with `sources = :before` in the column just before
  their first destination, next to where they are used (the hops by the kettle).
- `y` is the slot in the layer, `0, 1, 2, ...` from the top. The nodes of a layer are
  ordered by the barycenter of their neighbours in the layers before and after (sweeping
  `sweeps` times), to reduce the crossings of the arrows; the nodes of the same vessel in a
  layer are kept together, and the vessels keep their order.

See [`layout!`](@ref) to write it into the nodeviews, and [`positions`](@ref).
"""
function layout(q::Quiver; sources::Symbol = :before, sweeps::Integer = 8)
    sources in (:before, :first) || throw(ArgumentError("sources is :before or :first, not $(repr(sources))"))
    order = nodes(q)
    isempty(order) && return Dict{Symbol, Vector{Float64}}()
    layer = something(_vessel_layers(q, order), _layers(q, order))
    _place_sources!(layer, q, order, sources)
    # the stages first: ordered in their layers, the lots then put next to their destination
    stages = [n for n in order if !_islot(q, n)]
    isempty(stages) && (stages = order)
    instage = Set(stages)
    nlayers = maximum(values(layer)) + 1
    layers = [Symbol[] for _ in 1:nlayers]
    for n in stages
        push!(layers[layer[n] + 1], n)
    end
    # the rank of the vessel of each node, by first appearance
    vrank = Dict{Union{Nothing, Symbol}, Int}()
    for n in order
        v = vessel(q, n)
        v === nothing || haskey(vrank, v) || (vrank[v] = length(vrank))
    end
    group = Dict(n => _group(q, n, vrank) for n in order)
    # initial order: by group, then topological order
    topo = Dict(n => i for (i, n) in enumerate(order))
    for l in layers
        sort!(l; by = n -> (group[n], topo[n]))
    end
    slot = Dict(n => i - 1 for l in layers for (i, n) in enumerate(l))
    for k in 1:sweeps
        down = isodd(k)
        for i in (down ? (2:nlayers) : (nlayers - 1:-1:1))
            neighbours(n) = down ? [p for p in predecessors(q, n) if p in instage && layer[p] < layer[n]] :
                                   [d for d in successors(q, n) if d in instage && layer[d] > layer[n]]
            _reorder!(layers[i], neighbours, slot, group)
            for (j, n) in enumerate(layers[i])
                slot[n] = j - 1
            end
        end
    end
    # each lot in the free slot of its layer nearest to its destinations (those of the
    # earliest destinations first)
    taken = Set((layer[n], slot[n]) for n in stages)
    lots = [n for n in order if !(n in instage)]
    target(n) = (ds = successors(q, n); isempty(ds) ? 0.0 : sum(slot[d] for d in ds) / length(ds))
    sort!(lots; by = n -> (minimum((layer[d] for d in successors(q, n)); init = 0), target(n), topo[n]))
    for n in lots
        t = round(Int, target(n))
        y = first(y for y in Iterators.flatten((t + k, t - k) for k in 0:typemax(Int) - 1)
                  if y ≥ 0 && !((layer[n], y) in taken))
        slot[n] = y
        push!(taken, (layer[n], y))
    end
    return Dict(n => Float64[layer[n], slot[n]] for n in order)
end

# a lot: a node in no vessel without arrows into it
_islot(q, n) = vessel(q, n) === nothing && isempty(predecessors(q, n))

# the layer of each node: the longest path from a source (the lots placed afterwards)
function _layers(q::Quiver, order)
    layer = Dict{Symbol, Int}()
    for n in order
        ps = predecessors(q, n)
        layer[n] = isempty(ps) ? 0 : maximum(layer[p] for p in ps) + 1
    end
    return layer
end

# the layer of each stage, aligned by vessel (see `layout`), or `nothing` when the vessels
# are used in a cycle; the stages start at layer 1, after a column for the lots
function _vessel_layers(q::Quiver, order)
    unit(n) = something(vessel(q, n), Symbol("#", n))      # (a stage in no vessel: its own)
    stages = [n for n in order if !_islot(q, n)]
    # the rank of each vessel: the longest chain of vessels before it
    rank = Dict{Symbol, Int}(unit(n) => 0 for n in stages)
    for _ in 1:length(rank)                                  # (relaxed; a cycle never settles)
        changed = false
        for n in stages, p in predecessors(q, n)
            _islot(q, p) && continue
            (u, v) = (unit(p), unit(n))
            u == v || rank[u] + 1 ≤ rank[v] || (rank[v] = rank[u] + 1; changed = true)
        end
        changed || @goto settled
    end
    return nothing
    @label settled
    # the column of each stage in its vessel, and the width of each rank
    col = Dict{Symbol, Int}()
    for n in stages
        inner = [col[p] for p in predecessors(q, n) if !_islot(q, p) && unit(p) == unit(n)]
        col[n] = isempty(inner) ? 0 : maximum(inner) + 1
    end
    nranks = maximum(values(rank)) + 1
    width = zeros(Int, nranks)
    for n in stages
        width[rank[unit(n)] + 1] = max(width[rank[unit(n)] + 1], col[n] + 1)
    end
    start = cumsum([1; width])                             # (column 0: the lots)
    layer = Dict{Symbol, Int}(n => start[rank[unit(n)] + 1] + col[n] for n in stages)
    # (an arrow within a vessel but against its order cannot happen; check the drawing
    # still goes left to right)
    for n in stages, p in predecessors(q, n)
        _islot(q, p) || layer[p] < layer[n] || return nothing
    end
    # a dead end alone in its vessel (a bag of spent grain, a blend): right after where it
    # comes from, rather than after all the vessels of its rank
    members = Dict{Symbol, Int}()
    for n in stages
        members[unit(n)] = get(members, unit(n), 0) + 1
    end
    for n in stages
        isempty(successors(q, n)) && members[unit(n)] == 1 || continue
        ps = [p for p in predecessors(q, n) if !_islot(q, p)]
        isempty(ps) || (layer[n] = maximum(layer[p] for p in ps) + 1)
    end
    for n in order
        _islot(q, n) && (layer[n] = 0)
    end
    return layer
end

# the lots in the first column (`:first`), or just before their first destination
# (`:before`); then the layers start at 0
function _place_sources!(layer, q, order, sources)
    for n in Iterators.reverse(order)                      # (chains of lots follow)
        _islot(q, n) || continue
        ss = successors(q, n)
        isempty(ss) && continue
        layer[n] = sources === :first ? 0 : max(0, minimum(layer[d] for d in ss) - 1)
    end
    m = minimum(values(layer))
    for n in keys(layer)
        layer[n] -= m
    end
    return layer
end

# the group of a node: its vessel, or for a lot the vessel of its first destination, placed
# before the stages of that vessel
function _group(q, n, vrank)
    v = vessel(q, n)
    v === nothing || return (vrank[v], 1)
    for d in successors(q, n)
        w = vessel(q, d)
        w === nothing || return (vrank[w], 0)
    end
    return (length(vrank), 0)
end

# order a layer by barycenters, keeping the groups together (ordered by their mean
# barycenter) and the groups of a vessel in order
function _reorder!(l::Vector{Symbol}, neighbours, slot, group)
    bary = Dict{Symbol, Float64}()
    for n in l
        ns = neighbours(n)
        bary[n] = isempty(ns) ? Float64(slot[n]) : sum(slot[p] for p in ns) / length(ns)
    end
    groups = unique(group[n] for n in l)
    mean(g) = (xs = [bary[n] for n in l if group[n] == g]; sum(xs) / length(xs))
    # (groups of the same vessel keep their order: a lot before its stages)
    gorder = sort(groups; by = g -> (mean(first(h for h in groups if h[1] == g[1])), g))
    rank = Dict(g => i for (i, g) in enumerate(gorder))
    sort!(l; by = n -> (rank[group[n]], bary[n], slot[n]))
    return l
end

"""
    crossings(q::Quiver, positions) -> Int

The number of pairs of arrows that cross in a layered drawing with the given positions
(arrows as straight segments; arrows between the same pair of layers are compared), to
assess a layout.
"""
function crossings(q::Quiver, pos)
    es = unique((s, d) for (s, d, _) in arrows(q))
    c = 0
    for i in eachindex(es), j in i+1:length(es)
        (a, b), (u, v) = es[i], es[j]
        (pos[a][1] == pos[u][1] && pos[b][1] == pos[v][1]) || continue
        (a == u || b == v) && continue
        c += (pos[a][2] - pos[u][2]) * (pos[b][2] - pos[v][2]) < 0
    end
    return c
end

"""
    positions(s::Session) -> Dict{Symbol, Vector{Float64}}

The position of each node of `s`, `[x, y]`: its nodeview `"position"` if it has one, else
where [`layout`](@ref) would put it. Frontends draw from this, so that a quiver without
positions (e.g. an imported recipe) is drawn laid out.
"""
function positions(s::Session)
    q = s.quiver
    auto = nothing
    out = Dict{Symbol, Vector{Float64}}()
    for n in nodes(q)
        p = get(nodeview(q, n), "position", nothing)
        if p === nothing
            auto === nothing && (auto = layout(q))
            out[n] = auto[n]
        else
            out[n] = Float64[p...]
        end
    end
    return out
end

"""
    layout!(s::Session; description = "Arrange the nodes", kwargs...)

Writes the [`layout`](@ref) of the quiver of `s` into the `"position"` of the nodeviews, as
one undoable step of [`MoveNode`](@ref)s (layout only: no brew). The keyword arguments go to
`layout`. Returns the positions.
"""
function layout!(s::Session; description::AbstractString = "Arrange the nodes", kwargs...)
    pos = layout(s.quiver; kwargs...)
    transaction(s, description) do
        for n in nodes(s.quiver)
            get(nodeview(s.quiver, n), "position", nothing) == pos[n] && continue
            apply!(s, MoveNode(n, pos[n]))
        end
    end
    return pos
end
