# References to the items of a quiver that can be selected: nodes and arrows.

"""
    ItemRef

A reference to an item of a quiver, which can be selected: a [`NodeRef`](@ref) or an
[`ArrowRef`](@ref).
"""
abstract type ItemRef end

"""
    NodeRef(label)

A reference to the node `label` of a quiver.
"""
struct NodeRef <: ItemRef
    label::Symbol
end

"""
    ArrowRef(source, destination, index = 1)

A reference to the `index`-th arrow from `source` to `destination` (there may be several
between the same nodes, e.g. two hop additions from the same lot).
"""
struct ArrowRef <: ItemRef
    source::Symbol
    destination::Symbol
    index::Int
end
ArrowRef(source::Symbol, destination::Symbol) = ArrowRef(source, destination, 1)
ArrowRef(e::Pair{Symbol, Symbol}, index::Integer = 1) = ArrowRef(e.first, e.second, index)

Base.show(io::IO, r::NodeRef) = print(io, "NodeRef(:", r.label, ")")
Base.show(io::IO, r::ArrowRef) =
    print(io, "ArrowRef(:", r.source, " => :", r.destination, ", ", r.index, ")")

"""
    isvalid_ref(q::Quiver, ref::ItemRef)

Whether `ref` refers to an item of `q`.
"""
isvalid_ref(q::Quiver, r::NodeRef) = haskey(q, r.label)
isvalid_ref(q::Quiver, r::ArrowRef) =
    haskey(q, r.source) && haskey(q, r.destination) && r.destination in successors(q, r.source) &&
    1 ≤ r.index ≤ length(q[r.source => r.destination])
