# Parsing what users type: the inverse of format.

@testset "Parsing values" begin
    @test parse_value("4.8 kg") == 4.8u"kg" && parse_value("4.8kg") == 4.8u"kg"
    @test parse_value("1.050 sg") == 1.05u"sg"
    @test parse_value("95%") == 95.0u"percent"
    @test parse_value("70 min") == 70.0u"minute"
    @test parse_value("4 L/h") == 4.0u"L/hr"
    @test parse_value("0.10 1/h") == 0.1u"hr^-1"
    @test parse_value("80 °C") == 80.0u"°C" && parse_value("80°C") == 80.0u"°C"
    @test parse_value("14 days") == 14.0u"d"
    @test parse_value("1.5 L/min") == 1.5u"L/minute"
    @test parse_value("2") === 2.0 && parse_value(".5") === 0.5 && parse_value("-1") === -1.0
    @test parse_value("1e-3 kg") == 0.001u"kg"
    @test all(parse_value(t) === nothing for t in ("", "  ", "-", "–", "nothing", "None"))
    @test parse_value("true") === true && parse_value("FALSE") === false
    @test parse_value("10 min remaining") == Remaining(10u"minute")
    @test parse_value("at 70 min") == At(70u"minute")
    @test parse_value("3 d remaining") == Remaining(3u"d")
    for bad in ("abc", "4 furlongs", "at 5 kg", "5 kg remaining", "1.2.3 kg")
        @test_throws ArgumentError parse_value(bad)
    end
    # it reads what format writes
    for x in (1.0523u"sg", 23.14u"L", 0.25u"L", 4.5u"kg", 0.3u"kg", 5.23u"percent", 34.6u"IBU",
              8.43u"SRM", 67u"°C", 60.0u"minute", 14.0u"d", 2.4u"vols", 150.0u"mg/L", 1.0u"L/kg",
              4.0u"L/hr", 0.1u"hr^-1", 1.5u"L/minute", 12.0u"°P", Remaining(10u"minute"), At(70u"minute"))
        y = parse_value(format(x))
        x isa Unitful.Quantity ? (@test y ≈ x rtol = 0.02) : (@test y == x)   # (as rounded)
    end
    # a number without a unit, in the unit given, or that of the value it replaces
    @test parse_value("25"; unit = u"L") == 25u"L"
    @test parse_value("2500 mL"; unit = u"L") == 2500u"mL"           # a unit typed is kept
    @test parse_value("25", 27.0u"L") == 25u"L"
    @test parse_value("2500", 27.0u"L") == 2500u"L"                  # no guessing
    @test parse_value("25L", 27.0u"L") == 25u"L"
    @test parse_value("250", 0.3u"kg") == 250u"g"                    # as it is shown: 300 g
    @test parse_value("5", 4.5u"kg") == 5u"kg"
    @test parse_value("72", 75.0u"°C") == 72u"°C"
    @test parse_value("90", 95.0u"percent") == 90u"percent"
    @test parse_value("70", 60.0u"minute") == 70u"minute"
    @test parse_value("5 remaining", Remaining(10u"minute")) == Remaining(5u"minute")
    @test parse_value("at 55", At(70u"minute")) == At(55u"minute")
    @test parse_value("2", 1.0) === 2.0                               # a count stays a number
    @test parse_value("2", nothing) === 2.0
    @test parse_value("", 27.0u"L") === nothing
    @test input_unit(0.3u"kg") == u"g" && input_unit(Remaining(10u"minute")) == u"minute"
    @test input_unit(1.0) === nothing && input_unit(nothing) === nothing
    s2 = batch_session()
    apply!(s2, SetAmount(:strike_water, parse_value("17", volume(quiver(s2)[:strike_water].initial))))
    @test volume(quiver(s2)[:strike_water].initial) ≈ 17u"L"

    # into commands
    s = batch_session()
    apply!(s, SetArrowField(:mash, :rested, 1, :conversion, parse_value("90%")))
    @test quiver(s)[:mash => :rested, 1].conversion ≈ 0.9
    apply!(s, SetArrowField(:cascade, :kettle, 2, :timing, parse_value("at 55 min")))
    @test quiver(s)[:cascade => :kettle, 2].timing == At(55u"minute")
    apply!(s, SetAmount(:pale, parse_value("4.6 kg")))
    @test amount(s, :pale) ≈ 4.6u"kg"
end
