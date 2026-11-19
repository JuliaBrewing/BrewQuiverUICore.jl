# Layout: a layered drawing of the quiver, by topological rank, with the nodes of each vessel
# kept together, written into the "position" of the nodeview of each node.

"""
    layout(q::Quiver; sweeps = 8) -> Dict{Symbol, Vector{Float64}}

A layered layout of `q`: the position `[x, y]` of each node, in abstract layout units.

- `x` is the layer: the length of the longest path from a source to the node, so that
  every arrow goes from left to right. A lot (a source) is put in the layer just before
  its first destination, next to where it is used (the hops by the kettle), rather than
  with all the sources at the start.
- `y` is the slot in the layer, `0, 1, 2, ...` from the top. The nodes of a layer are
  ordered by the barycenter of their neighbours in the layers before and after (sweeping
  `sweeps` times), to reduce the crossings of the arrows; the nodes of the same vessel in a
  layer are kept together, and the vessels keep their order.

See [`layout!`](@ref) to write it into the nodeviews, and [`positions`](@ref).
"""
function layout(q::Quiver; sweeps::Integer = 8)
    order = nodes(q)
    isempty(order) && return Dict{Symbol, Vector{Float64}}()
    layer = _layers(q, order)
    nlayers = maximum(values(layer)) + 1
    layers = [Symbol[] for _ in 1:nlayers]
    for n in order
        push!(layers[layer[n] + 1], n)
    end
    # the rank of the vessel of each node, by first appearance; lots go with their destination
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
            neighbours(n) = down ? [p for p in predecessors(q, n) if layer[p] < layer[n]] :
                                   [d for d in successors(q, n) if layer[d] > layer[n]]
            _reorder!(layers[i], neighbours, slot, group)
            for (j, n) in enumerate(layers[i])
                slot[n] = j - 1
            end
        end
    end
    return Dict(n => Float64[layer[n], slot[n]] for n in order)
end

# the layer of each node: the longest path from a source; a source sits just before its
# first destination
function _layers(q::Quiver, order)
    layer = Dict{Symbol, Int}()
    for n in order
        ps = predecessors(q, n)
        layer[n] = isempty(ps) ? 0 : maximum(layer[p] for p in ps) + 1
    end
    # (sources pulled right, in reverse topological order so that chains of sources follow)
    for n in Iterators.reverse(order)
        isempty(predecessors(q, n)) || continue
        ss = successors(q, n)
        isempty(ss) || (layer[n] = max(0, minimum(layer[d] for d in ss) - 1))
    end
    # (the layers may now start above 0)
    m = minimum(values(layer))
    return Dict(n => l - m for (n, l) in layer)
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
