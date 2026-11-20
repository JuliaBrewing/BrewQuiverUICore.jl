# View data: formatting, node and arrow summaries, details, tables, timeline, solutions.

@testset "View data" begin
    @testset "Formatting" begin
        @test format(1.0523u"sg") == "1.052 sg"
        @test format(23.14u"L") == "23.1 L"
        @test format(0.25u"L") == "250 mL"
        @test format(4.5u"kg") == "4.50 kg"
        @test format(0.3u"kg") == "300 g"
        @test format(0.0005u"kg") == "500 mg"
        @test format(0.0u"kg") == "0 g"
        @test format(5.23u"percent") == "5.2%"
        @test format(34.6u"IBU") == "35 IBU"
        @test format(8.43u"SRM") == "8.4 SRM"
        @test format(67u"°C") == "67.0 °C"
        @test format(60.0u"minute") == "60 min"
        @test format(14.0u"d") == "14.0 d"
        @test format(2.4u"vols") == "2.40 vols"
        @test format(150.0u"mg/L") == "150 mg/L"
        @test format(1.0u"L/kg") == "1.00 L/kg"
        @test format(4.0u"L/hr") == "4.0 L/h"
        @test format(0.1u"hr^-1") == "0.10 1/h"
        @test format(2.0u"m/s^2") == "2 m/s^2"
        @test format(2.0u"m") == "2 m"                    # three significant digits
        @test format(3.14159u"m") == "3.14 m"
        @test format(1.0523u"sg"; digits = 4) == "1.0523 sg"
        @test format(1.0u"kg"; unit = u"g") == "1000 g"
        @test format(5.4321) == "5.43"
        @test format(2) == "2"
        @test format(missing) == "–" && format(nothing) == "–"
        @test format(:kettle) == ":kettle"
        @test format(Remaining(10u"minute")) == "10 min remaining"
        @test format(At(70u"minute")) == "at 70 min"
        @test display_digits(u"sg") == 3 && display_digits(u"m") === nothing
    end

    s = batch_session()
    select!(s, NodeRef(:wort), ArrowRef(:cascade, :kettle, 2))
    res = result(s)

    @testset "Node summaries" begin
        w = node_summary(s, :wort)
        @test w.label == :wort && w.vessel == :kettle && w.kind == :stage
        @test w.contents == ""
        @test w.volume ≈ uconvert(u"L", volume(res[:wort]))
        @test w.gravity ≈ gravity(res[:wort])
        @test w.ibu ≈ ibu(res[:wort])
        @test w.abv ≈ 0u"percent" atol = 1e-9u"percent"
        @test w.srm isa Unitful.Quantity && w.temperature ≈ 100u"°C"
        @test w.mash_ph === missing                        # no grain left to mash
        @test w.color == srm_hex(w.srm)
        @test w.selected && !w.changed && isempty(w.warnings)

        b = node_summary(s, :bottles)
        @test b.kind == :product && b.abv > 4u"percent" && b.carbonation > 2u"vols"
        p = node_summary(s, :pale)
        @test p.kind == :lot && p.contents == "4.50 kg Pale ale malt"
        @test p.volume === missing && p.gravity === missing
        @test p.color == srm_hex(3u"°L")                   # the color of the malt
        m = node_summary(s, :mash)
        @test 5 < m.mash_ph < 6
        @test node_summary(s, :strike_water).color === nothing
        @test node_summary(s, :kettle).color == "#ffcc00"  # the user's color
        @test [x.label for x in node_summaries(s)] == nodes(quiver(s))
        @test_throws ArgumentError node_summary(s, :nowhere)

        # changed nodes, and warnings
        apply!(s, SetAmount(:crystal, 0.4u"kg"))
        @test node_summary(s, :wort).changed && !node_summary(s, :cascade).changed
        undo!(s)
        q = single_batch()
        equip!(q, :kettle, Vessel(capacity = 20u"L"))
        add!(q, :roast, Fermentable("Roasted barley"; color = 500u"°L") => 0.2u"kg")
        connect!(q, :roast => :mash)
        s2 = Session(q)
        @test any(occursin("capacity", w) for w in node_summary(s2, :kettle).warnings)
        @test any(occursin("distilled water pH", w) for w in node_summary(s2, :mash).warnings)

        # a quiver that does not brew has no results
        f = node_summary(Session(overdrawn()), :a)
        @test f.volume === missing && f.mash_ph === missing && f.color === nothing
    end

    @testset "Groups and tables" begin
        g = vessel_groups(s)
        @test first(g) == (nothing => [:pale, :crystal, :cascade, :yeast, :strike_water,
                                       :sparge_water, :priming_sugar])
        @test [v for (v, _) in g] == [nothing, :mashtun, :kettle, :fermentor, :bottles]
        @test g[3] == (:kettle => [:kettle, :wort, :chilled])
        t = results_table(s)
        @test t.header == ["Node", "Vessel", "Volume", "Gravity", "OG", "ABV", "IBU", "Color", "Temp.", "Mash pH"]
        @test length(t.rows) == length(nodes(quiver(s)))
        row = t.rows[findfirst(r -> r[1] == :wort, t.rows)]
        @test row[2] == :kettle && row[4] ≈ gravity(res[:wort])
        t2 = results_table(s; columns = [:ibu => "IBU"])
        @test t2.header == ["Node", "Vessel", "IBU"] && all(length(r) == 3 for r in t2.rows)
    end

    @testset "Arrows" begin
        a = arrow_summary(s, :cascade, :kettle, 2)
        @test a.kind == "Transfer" && a.selected
        @test (:amount => 0.025u"kg") in a.parameters
        @test (:timing => Remaining(10u"minute")) in a.parameters
        @test a.moved_mass ≈ 25u"g" && a.moved_volume ≈ 0u"L"
        b = arrow_summary(s, ArrowRef(:kettle, :wort))
        @test b.kind == "Boil" && b.duration ≈ 60u"minute"
        @test b.released_water ≈ 4u"kg" rtol = 0.01
        @test !b.selected
        @test length(arrow_summaries(s)) == length(arrows(quiver(s)))
        @test_throws ArgumentError arrow_summary(s, :kettle, :wort, 2)
        @test arrow_summary(Session(overdrawn()), :w, :a).moved_volume === missing

        fs = fields(Boil())
        @test [f.name for f in fs] == [:time, :evaporation, :stand, :stand_temperature]
        e = fs[2]
        @test e.label == "evaporation" && e.optional && !e.fraction
        @test Set(e.units) == Set([u"L/hr", u"hr^-1"])
        t = only(f for f in fields(Transfer(0.5)) if f.name == :amount)
        @test t.fraction && t.optional && t.value == 0.5 && Set(t.units) == Set([u"L", u"kg"])
        @test only(f for f in fields(MashRest()) if f.name == :conversion).fraction
        v = fields(Vessel(capacity = 30u"L"))
        @test v[1].name == :name && isempty(v[1].units)
        @test v[2].value ≈ 30u"L" && v[2].units == [u"L"]
    end

    @testset "Details" begin
        d = node_detail(s, :kettle)
        @test d.summary.label == :kettle
        @test iszero(d.initial)
        @test d.contents ≈ res[:kettle]
        @test [(a.source, a.index) for a in d.incoming if a.source == :cascade] == [(:cascade, 1), (:cascade, 2)]
        @test only(d.outgoing).kind == "Boil"
        rows = solid_rows(d.contents)
        hops = [r for r in rows if r.name == "Cascade"]
        @test Set(r.timing for r in hops) == Set([Remaining(60u"minute"), Remaining(10u"minute")])
        @test any(r -> r.kind == "Residue", solid_rows(res[:grain_bed]))
        @test any(r -> r.kind == "HopMatter", solid_rows(res[:wort]))
        @test any(r -> r.kind == "YeastCake", solid_rows(res[:beer]))
        l = liquor_rows(res[:beer])
        @test [r.name for r in l] == ["water", "extract", "alcohol", "iso-alpha acids", "CO₂", "temperature"]
        @test l[3].value > 0u"kg"
        @test [r.ion for r in mineral_rows(res[:wort])][1] == "calcium"
        @test isempty(mineral_rows(res[:pale]))
        g = node_detail(s, :grain_bed)
        @test leftover(res, :grain_bed) ≈ g.leftover
        @test node_detail(Session(overdrawn()), :w).contents === nothing
    end

    @testset "Timeline" begin
        rows = timeline_rows(s; start = 8u"hr")
        @test [r.label for r in rows] == nodes(quiver(s))
        k = only(r for r in rows if r.label == :kettle)
        @test k.vessel == :kettle && k.ready ≥ k.arrive ≥ 8u"hr"
        @test only(r for r in rows if r.label == :bottles).leave === nothing
        b = vessel_bookings(s)
        @test [v for (v, _) in b.vessels] == [:mashtun, :kettle, :fermentor, :bottles]
        @test b.makespan > 14u"d"
        @test isempty(b.overlaps)
        last_booking = last(last(b.vessels).second)
        @test last_booking.label == :bottles && last_booking.to ≈ b.makespan
        @test isempty(timeline_rows(Session(overdrawn())))
        @test vessel_bookings(Session(overdrawn())) === nothing
    end

    @testset "Solutions" begin
        s3 = batch_session()
        sol = apply!(s3, Solve([:fermentor => gravity => 1.050u"sg", :wort => ibu => 30u"IBU"],
                               [Amount(:pale, :crystal), Amount(:cascade)]))
        r = solution_rows(sol)
        @test r.converged && r.iterations ≥ 1
        @test [p.name for p in r.parameters] == ["amount of :pale, :crystal", "amount of :cascade"]
        @test UI._parameter_name(Setting(:cascade => :kettle, :amount; index = 2)) ==
              "amount of :cascade => :kettle #2"
        @test r.targets[1].node == :fermentor && r.targets[1].quantity == "gravity"
        @test r.targets[1].reached ≈ 1.050u"sg" && r.targets[2].goal == 30u"IBU"
    end
end

@testset "SetEquipmentField" begin
    s = batch_session()
    doc = state(s)
    apply!(s, SetEquipmentField(:kettle, :dead_space, 1.5u"L"))
    @test equipment(quiver(s), :kettle).dead_space ≈ 1.5u"L"
    @test equipment(quiver(s), :kettle).evaporation ≈ 4u"L/hr"      # the rest is kept
    apply!(s, SetEquipmentField(:fermentor, :capacity, 25u"L"))     # a new equipment
    @test equipment(quiver(s), :fermentor).capacity ≈ 25u"L"
    @test describe(SetEquipmentField(:kettle, :dead_space, 1.5u"L")) == "Set the dead space of the kettle to 1.5 L"
    @test_throws CommandError apply!(s, SetEquipmentField(:kettle, :colour, 1))
    @test_throws CommandError apply!(s, SetEquipmentField(:kettle, :capacity, -1u"L"))
    undo!(s); undo!(s)
    @test state(s) == doc && uptodate(s)
end
