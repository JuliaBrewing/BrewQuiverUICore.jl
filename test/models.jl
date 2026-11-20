# Models, inventory and export.

using BeerJSON: BeerJSONParser

# the brew of a session is that of its quiver with its models
uptodate_with(s) = isbrewed(s) && same_brew(result(s), brew(quiver(s); models = models(s)))

@testset "Models" begin
    @test [first(v) for v in values(MODEL_CHOICES)] ==
          [DEFAULT_MODELS[k] for k in keys(MODEL_CHOICES)]
    s = batch_session()
    select!(s, NodeRef(:wort))
    res, doc = result(s), state(s)
    @test models_in_use(s).bitterness == Tinseth()
    cmd = set_model(s, :bitterness, Rager())
    @test cmd == SetModels((bitterness = Rager(),))
    @test describe(cmd) == "Use the models bitterness Rager"
    @test describe(SetModels((;))) == "Use the default models"
    apply!(s, cmd)
    @test models(s) == (bitterness = Rager(),) && models_in_use(s).bitterness == Rager()
    @test result(s).models.bitterness == Rager() && uptodate_with(s)
    @test !(ibu(result(s)[:wort]) ≈ ibu(res[:wort])) && :wort in changed(s)
    @test state(s) == doc                                   # the quiver is the same
    apply!(s, set_model(s, :color, Daniels()))
    @test models(s) == (bitterness = Rager(), color = Daniels())
    undo!(s); undo!(s)
    @test models(s) == (;) && same_brew(result(s), res) && selection(s) == [NodeRef(:wort)]
    redo!(s)
    @test models(s) == (bitterness = Rager(),)
    @test_throws CommandError apply!(s, SetModels((bitterness = Morey(),)))
    @test_throws CommandError apply!(s, SetModels((sweetness = Rager(),)))
    @test_throws ArgumentError revert_record(cmd, quiver(s))
    @test models(s) == (bitterness = Rager(),)
end


@testset "Inventory and export" begin
    s = batch_session()
    lib = Library()
    push!(lib, pale; stock = 3u"kg")
    push!(lib, cascade; stock = 100u"g")
    push!(lib, us05)
    set_library!(s, lib)
    rows = inventory_rows(s)
    @test [r.name for r in rows] == sort([r.name for r in rows])
    p = only(r for r in rows if r.name == "Pale ale malt")
    @test p.needed ≈ 4.5u"kg" && p.stock ≈ 3u"kg" && p.short
    c = only(r for r in rows if r.name == "Cascade")
    @test c.needed ≈ 50u"g" && !c.short
    x = only(r for r in rows if r.name == "Crystal 60")
    @test x.stock === nothing && x.short                      # not in the library
    messages = consume_stock!(s)
    @test any(occursin("Pale ale malt", m) for m in messages)
    @test iszero(stock(lib, "Pale ale malt")) && stock(lib, "Cascade") ≈ 50u"g"
    mktempdir() do dir
        f = save_library(s, joinpath(dir, "lib.json"))
        @test stock(Library(f), "Cascade") ≈ 50u"g"
        r = export_recipes(s, joinpath(dir, "recipes.json"))
        doc = readjson(BeerJSONParser, r).beerjson
        @test length(doc.recipes) == length(products(result(s), quiver(s)))
    end
    f = Session(overdrawn())
    @test isempty(inventory_rows(f))
    @test_throws ArgumentError consume_stock!(f)
    @test_throws ArgumentError export_recipes(f, "x.json")
end
