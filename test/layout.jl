# Layout: a layered drawing written into the nodeviews.

# the properties of a layered layout of `q`
function check_layout(q, p)
    @test Set(keys(p)) == Set(nodes(q))
    @test all(p[d][1] > p[s][1] for (s, d, _) in arrows(q))            # left to right
    @test allunique(Tuple.(values(p)))                                    # one node per place
    @test all(isinteger(x) && x ≥ 0 for v in values(p) for x in v)
    # a lot is in the layer just before its first destination, or in the first one
    for n in nodes(q)
        isempty(predecessors(q, n)) && vessel(q, n) === nothing && !isempty(successors(q, n)) || continue
        @test p[n][1] == minimum(p[d][1] for d in successors(q, n)) - 1 || p[n][1] == 0
    end
    # the nodes of a vessel in a layer are together
    for x in unique(v[1] for v in values(p))
        col = sort([n for n in nodes(q) if p[n][1] == x]; by = n -> p[n][2])
        vs = [vessel(q, n) for n in col if vessel(q, n) !== nothing]
        @test all(v -> count(==(v), vs) == 1 || all(==(v), vs[findfirst(==(v), vs):findlast(==(v), vs)]), unique(vs))
    end
end

@testset "Layout" begin
    q = single_batch()
    p = layout(q)
    check_layout(q, p)
    @test crossings(q, p) == 0
    # the stream of the batch along the top row
    @test [p[n] for n in (:mash, :kettle, :wort, :fermentor, :beer, :bottling, :bottles)] ==
          [[1, 0], [4, 0], [5, 0], [7, 0], [8, 0], [9, 0], [10, 0]]
    @test p[:cascade][1] == p[:kettle][1] - 1 && p[:yeast][1] == p[:fermentor][1] - 1
    # the lots in the first column
    f = layout(q; sources = :first)
    @test all(f[n][1] == 0 for n in nodes(q) if isempty(predecessors(q, n)))
    @test all(f[n][1] == p[n][1] for n in nodes(q) if !isempty(predecessors(q, n)))   # (the stages stay)
    @test all(p[d][1] > p[s][1] for (s, d, _) in arrows(q)) && allunique(Tuple.(values(f)))
    @test_throws ArgumentError layout(q; sources = :last)
    # aligned by vessel: the kettles of a parti-gyle in one column, their worts in the next,
    # and the streams on their own rows
    for t in ("parti-gyle", "split batch", "brew in a bag", "single batch")
        tq = template(t)
        for src in (:before, :first)
            check_layout(tq, layout(tq; sources = src))
        end
    end
    t = layout(template("parti-gyle"))
    @test t[:kettle1][1] == t[:kettle2][1] && t[:wort1][1] == t[:wort2][1] &&
          t[:fermentor1][1] == t[:fermentor2][1] && t[:beer1][1] == t[:beer2][1]
    @test t[:kettle1][2] == t[:wort1][2] == t[:beer1][2] && t[:kettle2][2] == t[:wort2][2] == t[:beer2][2]
    b = layout(template("brew in a bag"))
    @test b[:bag][1] == b[:rested][1] + 1                  # a dead end next to where it comes from
    # vessels used in a cycle: by the longest paths
    c = Quiver()
    add!(c, :w, water(10u"L"))
    add!(c, :a; vessel = :v1); add!(c, :b; vessel = :v2); add!(c, :c; vessel = :v1)
    connect!(c, :w => :a); connect!(c, :a => :b); connect!(c, :b => :c)
    pc = layout(c)
    @test pc[:a][1] < pc[:b][1] < pc[:c][1]

    g = partigyle()
    pg = layout(g)
    check_layout(g, pg)
    @test crossings(g, pg) ≤ crossings(g, layout(g; sweeps = 0))
    @test crossings(g, pg) ≤ 3        # (the hops and the grain bed feed both kettles, the beers both blends)
    @test pg[:kettle1][1] == pg[:kettle2][1] && pg[:beer1][1] == pg[:beer2][1]

    @test isempty(layout(Quiver()))
    r = import_recipe(joinpath(DATA, "RRSummerBitter.json"))
    check_layout(quiver(r), layout(quiver(r)))

    # positions: the stored ones, else the layout
    s = batch_session()                                  # :kettle is at [1, 2]
    pos = positions(s)
    @test pos[:kettle] == [1.0, 2.0] && pos[:wort] == layout(quiver(s))[:wort]

    # layout! writes them as one undoable step, without brewing
    res, doc = result(s), state(s)
    layout!(s)
    @test undo_description(s) == "Arrange the nodes"
    @test result(s) === res
    @test positions(s) == layout(quiver(s))
    @test all(haskey(nodeview(quiver(s), n), "position") for n in nodes(quiver(s)))
    n = length(history(s))
    layout!(s)                                           # nothing to move: no new step
    @test length(history(s)) == n
    undo!(s)
    @test state(s) == doc && result(s) === res
    layout!(s; description = "Tidy up", sweeps = 0)
    @test undo_description(s) == "Tidy up"
end
