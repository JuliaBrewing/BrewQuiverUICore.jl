# Preferred units: display, input, roles, the configuration file.

@testset "Units" begin
    p = UnitPreferences()
    @test p[:fermentable] === :auto && p[:hop] == u"g" && p[:volume] === :auto && p[:temperature] == u"°C"
    @test all(p[r] == first(UNIT_CHOICES[r]) for r in keys(UNIT_CHOICES))
    @test_throws ArgumentError UnitPreferences(sweetness = u"kg")
    @test_throws ArgumentError UnitPreferences(hop = u"L")
    q = with_unit(p, :hop, u"oz")
    @test q[:hop] == u"oz" && p[:hop] == u"g" && q != p

    @test unit_role(1u"kg") == :mass && unit_role(1u"L") == :volume && unit_role(1u"°F") == :temperature
    @test unit_role(1u"sg") == :gravity && unit_role(12u"°P") == :gravity && unit_role(8u"SRM") == :color
    @test unit_role(1u"L/kg") == :absorption && unit_role(4u"L/hr") == :rate
    @test unit_role(60u"minute") === nothing && unit_role(30u"IBU") === nothing && unit_role(2.0) === nothing
    @test unit_role(pale) == :fermentable && unit_role(cascade) == :hop && unit_role(us05) == :culture
    @test unit_role(Salt(Gypsum())) == :agent

    # display in the preferred units, auto by size
    @test format(p, 0.3u"kg"; role = :fermentable) == "300 g"
    @test format(p, 4.5u"kg"; role = :fermentable) == "4.50 kg"
    us = UnitPreferences(fermentable = u"lb", hop = u"oz", volume = u"gal", temperature = u"°F",
                         gravity = u"°P", color = u"EBC", absorption = u"qt/lb", rate = u"gal/hr")
    @test format(us, 4.5u"kg"; role = :fermentable) == "9.92 lb"
    @test format(us, 50u"g"; role = :hop) == "1.76 oz"
    @test format(us, 23.0u"L") == "6.08 gal"
    @test format(us, 100.0u"°C") == "212 °F"
    @test format(us, 1.050u"sg") == "12.4 °P"                    # through the equivalence
    @test format(us, 8.0u"SRM") == "16 EBC"
    @test format(us, 1.0u"L/kg") == "0.479 qt/lb"
    @test format(us, 4.0u"L/hr") == "1.06 gal/h"
    @test format(us, 60.0u"minute") == "60 min"                  # no role: its own unit
    @test format(us, 2.0) == "2.00"
    @test format(us, Remaining(10u"minute")) == "10 min remaining"
    @test preferred_unit(us, :fermentable, 1.0) == u"lb"          # (a count does not fit)
    @test preferred_unit(us, nothing, 1.0u"kg") == u"kg"
    @test preferred_unit(p, :fermentable) == u"kg" && preferred_unit(p, :volume) == u"L"

    # input: the unit shown, or for an empty field the preferred unit of its role
    s = batch_session()
    set_units!(s, us)
    @test units(s) === us
    @test parse_value(s, "10", 4.5u"kg"; role = :fermentable) == 10u"lb"
    @test parse_value(s, "10 kg", 4.5u"kg"; role = :fermentable) == 10u"kg"
    @test parse_value(s, "1.5", nothing; role = :hop) == 1.5u"oz"
    @test parse_value(s, "0.5", nothing; role = :absorption) == 0.5u"qt/lb"
    @test parse_value(s, "12", 1.05u"sg") == 12u"°P"
    @test parse_value(s, "2", 1.0; role = :culture) === 2.0       # a count stays a count
    @test parse_value(s, "2", nothing) === 2.0
    @test format(s, node_summary(s, :wort).volume) == format(us, node_summary(s, :wort).volume)
    # (gravity in the equivalence of the models of the session)
    apply!(s, SetModels((gravity = SugarGravity(),)))
    @test format(s, 1.050u"sg") == format(us, 1.050u"sg"; eq = SugarGravity())

    # the description of lots
    @test node_summary(s, :pale).contents == "9.92 lb Pale ale malt"
    @test node_summary(s, :cascade).contents == "1.76 oz Cascade"
    @test node_summary(s, :yeast).contents == "1 × US-05"
    @test node_summary(s, :strike_water).contents == "4.23 gal"
    apply!(s, AddNode(:gypsum, Salt(Gypsum()) => 4u"g"))
    @test contents_text(s, quiver(s)[:gypsum].initial) == "4 g"
    @test contents_text(s, Contents()) == "nothing"

    # the configuration file
    mktempdir() do dir
        f = joinpath(dir, "brewquiver", "units.toml")
        @test load_units(f) == UnitPreferences()                  # no file: the defaults
        save_units(us, f)
        @test load_units(f) == us
        @test occursin("fermentable = \"lb\"", read(f, String))
        write(f, "[units]\nhop = \"furlongs\"\n")
        @test_throws ArgumentError load_units(f)
        write(f, "[units]\nhop = \"mg\"\nvolume = \"auto\"\n")
        @test load_units(f) == UnitPreferences(hop = u"mg")
        withenv("XDG_CONFIG_HOME" => dir) do
            @test units_path() == f
            @test load_units() == UnitPreferences(hop = u"mg")
        end
    end
end
