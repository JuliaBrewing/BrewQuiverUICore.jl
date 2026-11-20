# Edit commands: their effect, their descriptions, their refusals, and their revert records.

const UI = BrewQuiverUICore

# whether two brews have the same nodes with the same contents and leftovers
same_brew(a::BrewResult, b::BrewResult) =
    Set(keys(a.nodes)) == Set(keys(b.nodes)) &&
    all(a[n] ≈ b[n] && leftover(a, n) ≈ leftover(b, n) for n in keys(a.nodes))

# the commands tried on the single batch, each with a check of its effect
const EDITS = [
    SetInitial(:pale, pale => 5u"kg") => s -> only(solids(quiver(s)[:pale].initial)).amount ≈ 5u"kg",
    SetAmount(:pale, 4800u"g") => s -> only(solids(quiver(s)[:pale].initial)).amount ≈ 4.8u"kg",
    SetAmount(:strike_water, 17u"L") => s -> volume(quiver(s)[:strike_water].initial) ≈ 17u"L",
    SetAmount(:yeast, 2) => s -> only(solids(quiver(s)[:yeast].initial)).amount == 2,
    SetIngredient(:pale, Fermentable("Maris Otter"; yield = 81u"percent", color = 3u"°L")) =>
        s -> only(solids(quiver(s)[:pale].initial)).ingredient.name == "Maris Otter",
    SetTemperature(:strike_water, 72u"°C") =>
        s -> liquor(quiver(s)[:strike_water].initial).temperature ≈ 72u"°C",
    SetWaterProfile(:strike_water, WaterProfile(calcium = 50u"mg/L", sulfate = 100u"mg/L")) =>
        s -> profile(quiver(s)[:strike_water].initial).calcium ≈ 50u"mg/L" &&
             isapprox(volume(quiver(s)[:strike_water].initial), 16u"L"; rtol = 1e-3) &&
             liquor(quiver(s)[:strike_water].initial).temperature ≈ 75u"°C",
    SetArrow(:kettle, :wort, 1, Boil(time = 90u"minute")) =>
        s -> quiver(s)[:kettle => :wort, 1].time ≈ 90u"minute",
    SetArrowField(:kettle => :wort, 1, :time, 1.5u"hr") =>
        s -> quiver(s)[:kettle => :wort, 1].time ≈ 90u"minute",
    SetArrowField(:cascade, :kettle, 2, :amount, 20u"g") =>
        s -> quiver(s)[:cascade => :kettle, 2].amount ≈ 0.02u"kg",
    SetArrowField(:mash, :rested, 1, :conversion, 90u"percent") =>
        s -> quiver(s)[:mash => :rested, 1].conversion ≈ 0.9,
    SetArrowField(:cascade, :kettle, 1, :timing, Remaining(45u"minute")) =>
        s -> quiver(s)[:cascade => :kettle, 1].timing == Remaining(45u"minute"),
    Connect(:sparge_water => :mash) => s -> :mash in successors(quiver(s), :sparge_water),
    RemoveArrow(:cascade, :kettle, 1) => s -> length(quiver(s)[:cascade => :kettle]) == 1,
    RemoveArrow(:cascade => :kettle, 2) => s -> length(quiver(s)[:cascade => :kettle]) == 1,
    Disconnect(:priming_sugar => :bottling) => s -> isempty(successors(quiver(s), :priming_sugar)),
    AddNode(:top_up, water(1u"L")) => s -> haskey(quiver(s), :top_up),
    AddNode(:trub; vessel = :kettle) => s -> vessel(quiver(s), :trub) == :kettle,
    RemoveNode(:bottles) => s -> !haskey(quiver(s), :bottles),
    RemoveNode(:crystal) => s -> !haskey(quiver(s), :crystal),
    RenameNode(:kettle, :boiler) => s -> haskey(quiver(s), :boiler) && !haskey(quiver(s), :kettle),
    SetVessel(:wort, nothing) => s -> vessel(quiver(s), :wort) === nothing,
    SetVessel(:chilled, :fermentor) => s -> vessel(quiver(s), :chilled) == :fermentor,
    Equip(:kettle, Vessel(evaporation = 5u"L/hr", dead_space = 1u"L")) =>
        s -> equipment(quiver(s), :kettle).dead_space ≈ 1u"L",
    SetView(:kettle, "color", "#aa3300") => s -> nodeview(quiver(s), :kettle)["color"] == "#aa3300",
    SetView(:kettle, "term.folded", true) => s -> nodeview(quiver(s), :kettle)["term.folded"],
    MoveNode(:kettle, (2, 3.5)) => s -> nodeview(quiver(s), :kettle)["position"] == [2.0, 3.5],
    Solve(:fermentor => gravity => 1.050u"sg", Amount(:pale, :crystal)) =>
        s -> gravity(result(s)[:fermentor]) ≈ 1.050u"sg",
]

# a single batch with some view data and equipment, so that their edits have something to revert
function batch_session()
    q = single_batch()
    nodeview(q, :kettle)["position"] = [1.0, 2.0]
    nodeview(q, :kettle)["color"] = "#ffcc00"
    equip!(q, :kettle, Vessel(evaporation = 4u"L/hr"))
    return Session(q)
end

@testset "Commands" begin
    @testset "$(describe(cmd))" for (cmd, effect) in EDITS
        s = batch_session()
        doc, res = document(quiver(s)), result(s)
        applied, _ = UI._apply!(s, cmd)
        @test effect(s)
        @test isbrewed(s)
        @test same_brew(result(s), brew(quiver(s)))      # the brew is up to date
        if brew_effect(cmd) isa LayoutOnly
            @test result(s) === res && isempty(changed(s))
        end
        edited = document(quiver(s))
        @test edited != doc
        # the record reverts the quiver exactly, and its brew
        UI._revert!(s, applied.record)
        @test document(quiver(s)) == doc
        @test same_brew(brew(quiver(s)), res)
    end

    @testset "Revert records" begin
        q = single_batch()
        @test revert_record(SetAmount(:pale, 5u"kg"), q) isa Inverse{SetInitial}
        @test revert_record(RenameNode(:kettle, :boiler), q) == Inverse(RenameNode(:boiler, :kettle))
        @test revert_record(Connect(:cascade => :kettle), q) == Inverse(RemoveArrow(:cascade, :kettle, 3))
        @test revert_record(Connect(:cascade => :wort), q) == Inverse(RemoveArrow(:cascade, :wort, 1))
        @test revert_record(RemoveArrow(:cascade, :kettle, 2), q) isa Inverse{<:Connect}
        @test revert_record(RemoveArrow(:cascade, :kettle, 1), q) isa Snapshot
        @test revert_record(RemoveNode(:kettle), q) isa Snapshot
        @test revert_record(Disconnect(:yeast, :fermentor), q) isa Snapshot
        @test revert_record(MoveNode(:kettle, [1, 2]), q) == Inverse(SetView(:kettle, "position", nothing))
        @test revert_record(Equip(:kettle, Vessel()), q) == Inverse(Equip(:kettle, nothing))
        # a snapshot is a copy, not changed by later edits
        r = revert_record(RemoveNode(:kettle), q)
        remove!(q, :kettle)
        @test haskey(r.quiver, :kettle)
    end

    @testset "Affected nodes" begin
        q = single_batch()
        @test affected(SetAmount(:pale, 5u"kg"), q) == [:pale]
        @test Set(affected(RemoveNode(:kettle), q)) == Set([:rested, :grain_bed, :cascade, :wort])
        @test affected(RenameNode(:kettle, :boiler), q) == [:boiler]
        @test affected(Equip(:kettle, Vessel()), q) == [:kettle, :wort, :chilled]
        @test affected(MoveNode(:kettle, [0, 0]), q) == Symbol[]
        @test affected(Solve(:wort => ibu => 30u"IBU", Amount(:cascade)), q) == AllNodes()
        @test brew_effect(MoveNode(:kettle, [0, 0])) == LayoutOnly()
        @test brew_effect(SetView(:kettle, "note", "")) == LayoutOnly()
        @test brew_effect(SetAmount(:pale, 5u"kg")) == Rebrews()
    end

    @testset "Descriptions" begin
        @test describe(SetAmount(:pale, 4.8u"kg")) == "Set :pale to 4.8 kg"
        @test describe(SetAmount(:yeast, 2)) == "Set :yeast to 2"
        @test describe(SetInitial(:pale, pale => 4.8u"kg")) == "Set :pale to 4.8 kg Pale ale malt"
        @test describe(SetInitial(:cascade, cascade => 30u"g")) == "Set :cascade to 30 g Cascade"
        @test describe(SetInitial(:yeast, us05 => 1)) == "Set :yeast to 1 × US-05"
        @test describe(SetInitial(:strike_water, water(16u"L"))) == "Set :strike_water to 16 L"
        @test describe(SetArrowField(:kettle, :wort, 1, :stand_temperature, 80u"°C")) ==
              "Set the stand temperature of :kettle => :wort to 80 °C"
        @test describe(SetArrowField(:cascade, :kettle, 2, :amount, 30u"g")) ==
              "Set the amount of :cascade => :kettle #2 to 30 g"
        @test describe(SetArrow(:kettle, :wort, 1, Boil())) == "Set :kettle => :wort to a Boil"
        @test describe(Connect(:a => :b)) == "Connect :a => :b"
        @test describe(Connect(:a => :b, Drain())) == "Connect :a => :b with a Drain"
        @test describe(RemoveArrow(:a, :b, 2)) == "Remove the arrow :a => :b #2"
        @test describe(Disconnect(:a, :b)) == "Disconnect :a => :b"
        @test describe(AddNode(:x; vessel = :kettle)) == "Add :x to the kettle"
        @test describe(RemoveNode(:x)) == "Remove :x"
        @test describe(RenameNode(:x, :y)) == "Rename :x to :y"
        @test describe(SetVessel(:x, :kettle)) == "Put :x in the kettle"
        @test describe(SetTemperature(:w, 75u"°C")) == "Set the temperature of :w to 75 °C"
        @test describe(SetWaterProfile(:w, WaterProfile())) == "Set the water profile of :w"
        @test describe(SetVessel(:x, nothing)) == "Take :x out of its vessel"
        @test describe(Equip(:kettle, Vessel())) == "Equip the kettle"
        @test describe(Equip(:kettle, nothing)) == "Remove the equipment of the kettle"
        @test describe(MoveNode(:x, [1, 2])) == "Move :x"
        @test describe(SetView(:x, "color", "#000000")) == "Set the color of :x"
        @test describe(SetView(:x, "color", nothing)) == "Clear the color of :x"
        @test describe(Solve(:wort => ibu => 30u"IBU", Amount(:cascade))) == "Solve for the ibu of :wort"
        @test describe(Solve([:wort => ibu => 30u"IBU", :wort => gravity => 1.05u"sg"],
                             [Amount(:cascade), Amount(:pale)])) == "Solve for 2 targets"
    end

    @testset "Refusals" begin
        refused = [
            SetAmount(:nowhere, 1u"kg") => "no node labelled :nowhere",
            SetAmount(:pale, -1u"kg") => "negative",
            SetAmount(:pale, 1u"L") => "mass or a count",
            SetAmount(:strike_water, 1u"minute") => "volume or a mass",
            SetAmount(:kettle, 1u"L") => "set its contents instead",
            SetIngredient(:pale, Hop("Saaz"; alpha = 3u"percent")) => "takes a fermentable",
            SetIngredient(:strike_water, pale) => "not a lot of one ingredient",
            SetIngredient(:crystal, Fermentable("Pale ale malt"; yield = 70u"percent")) =>
                "another ingredient named",
            AddNode(:extra, Fermentable("Crystal 60") => 1u"kg") => "another ingredient named",
            AddNode(:kettle) => "already a node",
            AddNode(Symbol("")) => "cannot be empty",
            RenameNode(:kettle, :wort) => "already a node",
            RenameNode(:nowhere, :x) => "no node",
            Connect(:bottles => :pale) => "cycle",
            Connect(:kettle => :kettle) => "itself",
            Connect(:kettle => :fermentor) => "transformation",
            Connect(:rested => :fermentor, Drain()) => "one drain",
            Connect(:nowhere => :kettle) => "no node",
            SetArrow(:rested, :grain_bed, 1, Drain()) => "one drain",
            SetArrow(:cascade, :kettle, 3, Transfer()) => "2 arrows",
            SetArrow(:kettle, :fermentor, 1, Transfer()) => "no arrow",
            SetArrowField(:kettle, :wort, 1, :color, 3) => "has no color",
            SetArrowField(:kettle, :wort, 1, :time, 3u"kg") => "takes a quantity in minute",
            SetArrowField(:kettle, :wort, 1, :time, -3u"minute") => "negative",
            SetArrowField(:mash, :rested, 1, :conversion, 120u"percent") => "between 0 and 1",
            RemoveArrow(:kettle, :fermentor, 1) => "no arrow",
            Disconnect(:kettle, :fermentor) => "no arrow",
            RemoveNode(:nowhere) => "no node",
            SetVessel(:nowhere, :kettle) => "no node",
            Equip(Symbol(""), Vessel()) => "cannot be empty",
            SetView(:kettle, "position", [1]) => "[x, y]",
            SetView(:kettle, "color", "red") => "#rrggbb",
            SetView(:kettle, "collapsed", 1) => "true or false",
            SetView(:kettle, "size", [1, 2]) => "\"term.size\"",
            MoveNode(:kettle, [1.0, NaN]) => "[x, y]",
            Solve(:nowhere => ibu => 30u"IBU", Amount(:cascade)) => "no node",
            Solve(:wort => ibu => 30u"IBU", Setting(:kettle => :fermentor, :time)) => "no arrow",
            SetTemperature(:pale, 70u"°C") => "not a lot of water or of a liquor",
            SetTemperature(:kettle, 70u"°C") => "not a lot of water or of a liquor",
            SetWaterProfile(:pale, WaterProfile()) => "not a lot of water or of a liquor",
            # the quiver would no longer brew
            SetAmount(:strike_water, 1u"L") => "would no longer brew: not enough liquid",
            Disconnect(:yeast, :fermentor) => "would no longer brew: there is no culture",
            SetArrowField(:cascade, :kettle, 1, :amount, 40u"g") => "would no longer brew",
        ]
        @testset "$(describe(cmd))" for (cmd, why) in refused
            s = batch_session()
            select!(s, NodeRef(:kettle))
            doc, res = document(quiver(s)), result(s)
            err = try
                apply!(s, cmd)
                nothing
            catch e
                e
            end
            @test err isa CommandError
            @test err.description == describe(cmd)
            @test occursin(why, sprint(showerror, err))
            # nothing changed
            @test document(quiver(s)) == doc
            @test result(s) === res && isbrewed(s)
            @test selection(s) == [NodeRef(:kettle)]
        end
    end

    @testset "Editing a quiver that does not brew" begin
        s = Session(overdrawn())
        apply!(s, SetAmount(:w, 11u"L"))              # still too little: accepted, still failed
        @test status(s) isa BrewFailed && volume(quiver(s)[:w].initial) ≈ 11u"L"
        apply!(s, SetAmount(:w, 12u"L"))
        @test isbrewed(s) && volume(result(s)[:b]) ≈ 6u"L"
        @test_throws CommandError apply!(s, SetAmount(:w, 11u"L"))   # now it brews: refused
        @test isbrewed(s)
    end

    @testset "Solve" begin
        s = batch_session()
        sol = apply!(s, Solve(:fermentor => gravity => 1.050u"sg", Amount(:pale, :crystal)))
        @test sol.converged
        @test gravity(result(s)[:fermentor]) ≈ 1.050u"sg"
        @test :pale in changed(s) && :bottles in changed(s)
    end

    @testset "Selection follows the edits" begin
        s = batch_session()
        select!(s, NodeRef(:wort), ArrowRef(:cascade, :kettle, 2), NodeRef(:kettle),
                ArrowRef(:kettle, :wort))
        apply!(s, RenameNode(:kettle, :boiler))
        @test selection(s) == [NodeRef(:wort), ArrowRef(:cascade, :boiler, 2), NodeRef(:boiler),
                               ArrowRef(:boiler, :wort, 1)]
        apply!(s, RemoveArrow(:cascade, :boiler, 1))
        @test selection(s) == [NodeRef(:wort), ArrowRef(:cascade, :boiler, 1), NodeRef(:boiler),
                               ArrowRef(:boiler, :wort, 1)]
        select!(s, ArrowRef(:cascade, :boiler, 1), NodeRef(:bottles))
        apply!(s, RemoveArrow(:cascade, :boiler, 1))
        @test selection(s) == [NodeRef(:bottles)]
        apply!(s, RemoveNode(:bottles))
        @test isempty(selection(s))
    end

    @testset "Changed nodes" begin
        s = batch_session()
        apply!(s, SetAmount(:crystal, 0.4u"kg"))
        @test :crystal in changed(s) && :bottles in changed(s) && !(:cascade in changed(s))
        apply!(s, MoveNode(:kettle, [5, 5]))
        @test isempty(changed(s))
        apply!(s, RenameNode(:kettle, :boiler))
        @test changed(s) == Set([:boiler])            # new to the brew, nothing else differs
    end
end
