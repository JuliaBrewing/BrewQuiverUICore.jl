using Test
using Unitful
using UnitfulBrewing
using BrewingFormulas
using BrewQuiver
using BrewQuiverUICore

include("quivers.jl")

const DATA = joinpath(@__DIR__, "data")

@testset "BrewQuiverUICore" begin

@testset "Session" begin
    q = single_batch()
    s = Session(q)
    @test quiver(s) === q
    @test filepath(s) === nothing
    @test status(s) == Brewed() && isbrewed(s)
    @test result(s)[:bottles] ≈ brew(q)[:bottles]
    @test isempty(changed(s))                   # nothing changed since it was opened
    @test isempty(warnings(s))
    @test models(s) == (;)

    # other models
    s2 = Session(single_batch(); models = (bitterness = Rager(),))
    @test result(s2).models.bitterness == Rager()
    @test !(ibu(result(s2)[:wort]) ≈ ibu(result(s)[:wort]))

    # a quiver that does not brew
    s3 = Session(overdrawn())
    @test status(s3) isa BrewFailed && !isbrewed(s3)
    @test result(s3) === nothing
    @test occursin("take", sprint(show, status(s3)))
end

@testset "Rebrew after a change" begin
    q = single_batch()
    s = Session(q)
    before = result(s)
    q[:cascade] = cascade => 80u"g"
    @test BrewQuiverUICore._rebrew!(s, [:cascade]) === nothing
    @test result(s) !== before                  # a new result, the old one is kept intact
    @test before[:wort] ≈ brew(single_batch())[:wort]
    @test result(s)[:bottles] ≈ brew(q)[:bottles]
    # the nodes whose results changed: only what is left of the hops, the transfers take 25 g
    @test changed(s) == Set([:cascade])
    q[:crystal] = crystal => 0.4u"kg"
    @test BrewQuiverUICore._rebrew!(s, [:crystal]) === nothing
    @test changed(s) == Set([:crystal, :mash, :rested, :grain_bed, :kettle, :wort, :chilled,
                             :fermentor, :beer, :bottling, :bottles])
    @test result(s)[:bottles] ≈ brew(q)[:bottles]

    # a change that makes the quiver fail leaves the brew as it was
    current = result(s)
    q[:strike_water] = water(2u"L"; temperature = 75u"°C")
    e = BrewQuiverUICore._rebrew!(s, [:strike_water])
    @test e isa Exception
    @test result(s) === current && isbrewed(s)
    q[:strike_water] = water(16u"L"; temperature = 75u"°C")
    @test BrewQuiverUICore._rebrew!(s, [:strike_water]) === nothing
    @test changed(s) == Set{Symbol}()           # back where it was

    # structural changes are detected by rebrew!, or fall back to a whole brew
    remove!(q, :bottles)
    @test BrewQuiverUICore._rebrew!(s, [:bottles]) === nothing
    @test !haskey(result(s).nodes, :bottles)
    @test result(s)[:bottling] ≈ brew(q)[:bottling]

    # from a failed brew, the whole quiver is brewed
    s3 = Session(overdrawn())
    quiver(s3)[:w => :b] = Transfer(4u"L")
    @test BrewQuiverUICore._rebrew!(s3, [:w]) === nothing
    @test isbrewed(s3) && volume(result(s3)[:b]) ≈ 4u"L"
    @test changed(s3) == Set([:w, :a, :b])
end

@testset "Warnings" begin
    q = single_batch()
    equip!(q, :kettle, Vessel(capacity = 20u"L"))
    s = Session(q)
    w = warnings(s, :kettle)
    @test length(w) == 1 && occursin("capacity", only(w).message)
    @test isempty(warnings(s, :wort)) == false    # the wort after the boil too
    @test all(x -> x.node in (:kettle, :wort, :chilled), warnings(s))
end

@testset "Files" begin
    mktempdir() do dir
        file = joinpath(dir, "bitter.quiver.json")
        s = Session(single_batch())
        @test_throws ArgumentError save!(s)      # no path yet
        save!(s, file)
        @test filepath(s) == file && isfile(file)
        s2 = open_session(file)
        @test filepath(s2) == file
        @test document(quiver(s2)) == document(quiver(s))
        @test result(s2)[:bottles] ≈ result(s)[:bottles]
        save!(s2)                                # at its own path
        @test document(readjson(Quiver, file)) == document(quiver(s))

        # a quiver that does not brew is saved without computed values, and loads failed
        s3 = Session(overdrawn())
        save!(s3, joinpath(dir, "overdrawn.quiver.json"))
        @test status(open_session(joinpath(dir, "overdrawn.quiver.json"))) isa BrewFailed
    end

    # BeerJSON recipes
    bitter = joinpath(DATA, "RRSummerBitter.json")
    @test length(recipe_names(bitter)) == 1
    name = only(recipe_names(bitter))
    s = import_recipe(bitter; calibration = BrewhouseEfficiency())
    @test isbrewed(s) && filepath(s) === nothing
    @test brewhouse_efficiency(result(s), quiver(s)) ≈ 0.75 rtol = 1e-3
    @test document(quiver(import_recipe(bitter, name))) == document(quiver(import_recipe(bitter)))
    @test_throws ArgumentError import_recipe(bitter, 2)
    @test_throws ArgumentError import_recipe(bitter, "Nothing")
    @test all(w -> w.node === nothing, warnings(s))  # the import's own warnings, if any
end

@testset "Selection" begin
    s = Session(single_batch())
    @test isempty(selection(s))
    select!(s, NodeRef(:kettle))
    @test selection(s) == [NodeRef(:kettle)]
    select!(s, Add(), ArrowRef(:cascade => :kettle, 2), NodeRef(:wort))
    @test selection(s) == [NodeRef(:kettle), ArrowRef(:cascade, :kettle, 2), NodeRef(:wort)]
    select!(s, Add(), NodeRef(:kettle))         # moved to the end: the primary one
    @test last(selection(s)) == NodeRef(:kettle) && length(selection(s)) == 3
    deselect!(s, NodeRef(:wort))
    @test selection(s) == [ArrowRef(:cascade, :kettle, 2), NodeRef(:kettle)]
    @test_throws ArgumentError select!(s, NodeRef(:nowhere))
    @test_throws ArgumentError select!(s, ArrowRef(:cascade => :kettle, 3))
    @test_throws ArgumentError select!(s, ArrowRef(:kettle => :cascade))
    @test length(selection(s)) == 2              # unchanged by the refused selections
    clear_selection!(s)
    @test isempty(selection(s))

    q = quiver(s)
    @test isvalid_ref(q, ArrowRef(:kettle, :wort))
    select!(s, NodeRef(:bottles), NodeRef(:kettle))
    remove!(q, :bottles)
    BrewQuiverUICore._prune_selection!(s)
    @test selection(s) == [NodeRef(:kettle)]
    @test sprint(show, ArrowRef(:a => :b, 2)) == "ArrowRef(:a => :b, 2)"
end

include("commands.jl")
include("history.jl")
include("views.jl")
include("layout.jl")
include("parse.jl")

end
