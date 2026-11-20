# The ingredients a session can add.

@testset "Catalog" begin
    s = batch_session()
    c = catalog(s)
    @test c["Pale ale malt"] == pale && c["Cascade"] == cascade && c["US-05"] == us05
    @test c["Gypsum"] isa Salt && c["Lactic acid 88.0%"] isa Acid
    @test length(c) == length(WATER_AGENTS) + 5               # the five ingredients of the lots
    @test isempty(keys(library(s)))
    @test find_ingredient(s, "pale ale malt") == pale         # ignoring case
    @test find_ingredient(s, "  Cascade ") == cascade
    @test find_ingredient(s, "crystal") == crystal            # the only one containing it
    @test find_ingredient(s, "gyps") isa Salt
    @test_throws ArgumentError find_ingredient(s, "Munich")
    e = try find_ingredient(s, "a") catch e e end
    @test e isa ArgumentError && occursin("could be", e.msg)
    @test_throws ArgumentError find_ingredient(s, "")

    # a library: its ingredients, the quiver's take precedence
    lib = Library()
    push!(lib, Fermentable("Munich malt"; color = 9u"°L"))
    push!(lib, Fermentable("Pale ale malt"; yield = 70u"percent"))
    set_library!(s, lib)
    @test library(s) === lib
    @test find_ingredient(s, "munich").color ≈ 9u"°L"
    @test catalog(s)["Pale ale malt"] == pale
    # added to the quiver from the catalog, and the lot's amount set in the catalog's way
    apply!(s, AddNode(:munich, find_ingredient(s, "munich") => 0.5u"kg"))
    apply!(s, Connect(:munich => :mash))
    @test amount(s, :munich) ≈ 0.5u"kg" && isbrewed(s)
    apply!(s, AddNode(:gypsum, find_ingredient(s, "gypsum") => 4u"g"))
    apply!(s, Connect(:gypsum => :mash))
    @test profile(result(s)[:mash]).sulfate > 0u"mg/L"
    apply!(s, SetAmount(:gypsum, 6u"g"))
    @test total_mass(quiver(s)[:gypsum].initial) ≈ 6u"g" rtol = 1e-6

    # a library from files, and through the import of a recipe
    s2 = import_recipe(joinpath(DATA, "RRSummerBitter.json"); library = lib)
    @test library(s2) === lib
    mktempdir() do dir
        f = joinpath(dir, "q.json")
        save!(Session(single_batch()), f)
        @test isempty(keys(library(open_session(f))))
        @test library(open_session(f; library = lib)) === lib
    end
end
