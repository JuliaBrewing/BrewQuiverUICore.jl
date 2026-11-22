# The ingredients a session can add.

@testset "Catalog" begin
    s = batch_session()
    c = catalog(s)
    @test c["Pale ale malt"] == pale && c["Cascade"] == cascade && c["US-05"] == us05
    @test c["Gypsum"] isa Salt && c["Lactic acid 88.0%"] isa Acid
    @test length(c) == length(WATER_AGENTS) + length(STARTER_LIBRARY)   # (the lots' are named as the starter's)
    @test c["Maris Otter"] == STARTER_LIBRARY["Maris Otter"]   # the starter library
    @test isempty(keys(library(s)))
    @test find_ingredient(s, "pale ale malt") == pale         # ignoring case
    @test find_ingredient(s, "  Cascade ") == cascade
    @test find_ingredient(s, "crystal 6") == crystal          # the only one containing it
    @test find_ingredient(s, "gyps") isa Salt
    @test_throws ArgumentError find_ingredient(s, "Munich")  # (Munich malt, Dark Munich malt)
    @test_throws ArgumentError find_ingredient(s, "Mnuich")
    e = try find_ingredient(s, "a") catch e e end
    @test e isa ArgumentError && occursin("could be", e.msg)
    @test_throws ArgumentError find_ingredient(s, "")

    # a library: its ingredients, the quiver's take precedence
    lib = Library()
    push!(lib, Fermentable("Munich malt"; color = 9u"°L"))
    push!(lib, Fermentable("Pale ale malt"; yield = 70u"percent"))
    set_library!(s, lib)
    @test library(s) === lib
    @test find_ingredient(s, "munich malt").color ≈ 9u"°L"   # the library's, not the starter's
    @test find_ingredient(s, "munich malt").yield ≈ 0.8
    @test catalog(s)["Pale ale malt"] == pale
    # added to the quiver from the catalog, and the lot's amount set in the catalog's way
    apply!(s, AddNode(:munich, find_ingredient(s, "munich malt") => 0.5u"kg"))
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

@testset "Starter library and search" begin
    s = Session(Quiver())
    @test length(STARTER_LIBRARY) > 60 && isempty(keys(library(s)))
    @test all(n -> haskey(catalog(s), n), keys(STARTER_LIBRARY))
    @test count(i -> i isa Hop, values(STARTER_LIBRARY.ingredients)) > 20
    @test STARTER_LIBRARY["W-34/70"].kind === :lager
    # searching: names starting with the text first, then words starting with it, then the rest
    @test search_ingredients(s, "pale")[1:2] == ["Pale ale malt", "Pale chocolate malt"]
    @test "Two-row pale malt" in search_ingredients(s, "pale")
    @test search_ingredients(s, "crystal") == ["Crystal 15", "Crystal 40", "Crystal 60", "Crystal 120"]   # natural order
    @test search_ingredients(s, "pale malt") == ["Pale ale malt", "Pale chocolate malt", "Two-row pale malt"]  # every word
    @test first(search_ingredients(s, "goldings")) == "East Kent Goldings"
    @test search_ingredients(s, "s"; role = :culture) ⊆ [n for (n, i) in catalog(s) if i isa Culture]
    @test "Saaz" in search_ingredients(s, "s"; role = :hop) && !("S-04" in search_ingredients(s, "s"; role = :hop))
    @test isempty(search_ingredients(s, "no such thing"))
    @test length(search_ingredients(s)) == length(catalog(s))                  # all, with no text
    @test "Gypsum" in search_ingredients(s, "gyp"; role = :agent)
    # the library of the session takes precedence over the starter
    lib = Library(); push!(lib, Hop("Cascade"; alpha = 7.5u"percent"))
    set_library!(s, lib)
    @test catalog(s)["Cascade"].alpha ≈ 0.075
end

@testset "Templates" begin
    @test length(TEMPLATES) == 4
    for (name, description) in TEMPLATES
        s = Session(template(name))
        @test isbrewed(s) && isempty(warnings(s)) && !isempty(description)
        @test all(n -> haskey(STARTER_LIBRARY, n), keys(requirements(result(s), quiver(s))))
    end
    @test count(x -> x.kind == :product && x.abv > 1u"percent", node_summaries(Session(template("parti-gyle")))) == 2
    @test_throws ArgumentError template("no such template")
end
