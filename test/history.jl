# The history: undo and redo, transactions, merging, the saved marker, the bounded length.

using Random: Xoshiro

# a clock for the tests, advanced by hand
mutable struct FakeClock
    t::Float64
end
(c::FakeClock)() = c.t

# the state of a session, to compare: its file document, and whether its brew is up to date
state(s) = document(quiver(s))
uptodate(s) = isbrewed(s) && same_brew(result(s), brew(quiver(s)))

history_session(; kwargs...) = batch_session(; history = History(; kwargs...))

amount(s, label) = only(solids(quiver(s)[label].initial)).amount

@testset "History" begin
    @testset "Undo and redo of every command" begin
        @testset "$(describe(cmd))" for (cmd, effect) in EDITS
            s = history_session()
            select!(s, NodeRef(:wort))
            doc, res = state(s), result(s)
            apply!(s, cmd)
            edited, sel = state(s), copy(selection(s))
            @test canundo(s) && !canredo(s)
            @test undo_description(s) == describe(cmd)
            @test undo!(s) == describe(cmd)
            @test state(s) == doc
            @test uptodate(s) && same_brew(result(s), res)
            @test selection(s) == [NodeRef(:wort)]
            @test !canundo(s) && canredo(s) && redo_description(s) == describe(cmd)
            @test redo!(s) == describe(cmd)
            @test state(s) == edited && uptodate(s) && effect(s)
            @test selection(s) == sel
            # and again
            undo!(s)
            @test state(s) == doc && uptodate(s)
            redo!(s)
            @test state(s) == edited && uptodate(s)
        end
    end

    @testset "Stacks" begin
        s = history_session()
        @test undo!(s) === nothing && redo!(s) === nothing
        @test undo_description(s) === nothing && redo_description(s) === nothing
        apply!(s, SetAmount(:pale, 4.6u"kg"))
        apply!(s, RenameNode(:kettle, :boiler))
        apply!(s, SetAmount(:crystal, 0.4u"kg"))
        @test [h.description for h in history(s)] ==
              ["Set :pale to 4.6 kg", "Rename :kettle to :boiler", "Set :crystal to 0.4 kg"]
        undo!(s); undo!(s)
        @test haskey(quiver(s), :kettle) && amount(s, :crystal) ≈ 0.3u"kg"
        @test [h.done for h in history(s)] == [true, false, false]
        @test redo_description(s) == "Rename :kettle to :boiler"
        # a new edit clears the redo stack
        apply!(s, SetAmount(:pale, 4.7u"kg"))
        @test !canredo(s)
        @test [h.description for h in history(s)] == ["Set :pale to 4.6 kg", "Set :pale to 4.7 kg"]
        # undo restores the changed nodes of the brew
        @test :bottles in changed(s)
        undo!(s)
        @test :pale in changed(s) && :bottles in changed(s)
        # a refused edit leaves the history as it was
        @test_throws CommandError apply!(s, SetAmount(:strike_water, 1u"L"))
        @test length(history(s)) == 2 && canredo(s)
    end

    @testset "Layout-only steps keep the brew" begin
        s = history_session()
        res = result(s)
        apply!(s, MoveNode(:kettle, [4, 4]))
        undo!(s)
        @test result(s) === res && isempty(changed(s))
        redo!(s)
        @test result(s) === res && nodeview(quiver(s), :kettle)["position"] == [4.0, 4.0]
    end

    @testset "Transactions" begin
        s = history_session()
        doc = state(s)
        select!(s, NodeRef(:kettle))
        begin_transaction!(s, "Brew a stronger beer")
        @test intransaction(s)
        apply!(s, SetAmount(:pale, 5u"kg"))
        apply!(s, SetAmount(:crystal, 0.4u"kg"))
        @test amount(s, :pale) ≈ 5u"kg" && uptodate(s)      # applied as they come
        @test !canundo(s)
        @test_throws CommandError undo!(s)
        select!(s, NodeRef(:wort))
        commit!(s)
        @test !intransaction(s)
        @test [h.description for h in history(s)] == ["Brew a stronger beer"]
        edited = state(s)
        undo!(s)
        @test state(s) == doc && uptodate(s) && selection(s) == [NodeRef(:kettle)]
        redo!(s)
        @test state(s) == edited && uptodate(s) && selection(s) == [NodeRef(:wort)]

        # abort restores the state at the beginning
        s = history_session()
        apply!(s, SetAmount(:pale, 4.6u"kg"))
        doc, res = state(s), result(s)
        select!(s, NodeRef(:kettle))
        begin_transaction!(s, "Restructure")
        apply!(s, RenameNode(:kettle, :boiler))
        apply!(s, RemoveNode(:bottles))
        apply!(s, MoveNode(:boiler, [3, 3]))
        abort!(s)
        @test state(s) == doc && same_brew(result(s), res) && uptodate(s)
        @test selection(s) == [NodeRef(:kettle)]
        @test [h.description for h in history(s)] == ["Set :pale to 4.6 kg"]
        @test_throws CommandError abort!(s)
        @test_throws CommandError commit!(s)

        # the do-block form, committed or aborted
        transaction(s, "Move 2 nodes") do
            apply!(s, MoveNode(:mash, [0, 1]))
            apply!(s, MoveNode(:rested, [1, 1]))
        end
        @test undo_description(s) == "Move 2 nodes"
        doc = state(s)
        @test_throws CommandError transaction(s, "Break it") do
            apply!(s, SetAmount(:pale, 4u"kg"))
            apply!(s, SetAmount(:strike_water, 1u"L"))   # refused: aborts it all
        end
        @test state(s) == doc && !intransaction(s) && undo_description(s) == "Move 2 nodes"

        # nested transactions fold into the outermost; empty ones leave nothing
        transaction(s, "Outer") do
            apply!(s, SetAmount(:pale, 4.4u"kg"))
            transaction(s, "Inner") do
                apply!(s, SetAmount(:crystal, 0.2u"kg"))
            end
            @test intransaction(s)
        end
        @test undo_description(s) == "Outer"
        undo!(s)
        @test amount(s, :pale) ≈ 4.6u"kg" && amount(s, :crystal) ≈ 0.3u"kg"
        n = length(history(s))
        transaction(() -> nothing, s, "Nothing")
        @test length(history(s)) == n
        # an inner exception aborts the whole transaction
        doc = state(s)
        @test_throws ErrorException transaction(s, "Outer") do
            apply!(s, SetAmount(:pale, 4.4u"kg"))
            transaction(s, "Inner") do
                error("cancelled")
            end
        end
        @test state(s) == doc && !intransaction(s)
    end

    @testset "Merging" begin
        clock = FakeClock(0.0)
        s = history_session(; clock)
        doc = state(s)
        for (t, m) in ((0.0, 4.6), (1.0, 4.7), (2.2, 4.8))     # typing, each within 1.5 s
            clock.t = t
            apply!(s, SetAmount(:pale, m * u"kg"))
        end
        @test [h.description for h in history(s)] == ["Set :pale to 4.8 kg"]
        undo!(s)
        @test state(s) == doc && amount(s, :pale) ≈ 4.5u"kg" && uptodate(s)
        redo!(s)
        @test amount(s, :pale) ≈ 4.8u"kg" && uptodate(s)

        # not merged: after the window, another field, after an undo or a save
        clock.t = 10.0
        apply!(s, SetAmount(:pale, 4.9u"kg"))                  # (after a redo)
        clock.t = 10.5
        apply!(s, SetAmount(:crystal, 0.4u"kg"))
        clock.t = 11.0
        apply!(s, SetAmount(:pale, 5.0u"kg"))
        clock.t = 20.0
        apply!(s, SetAmount(:pale, 5.1u"kg"))
        @test length(history(s)) == 5
        mktempdir() do dir
            save!(s, joinpath(dir, "q.json"))
            clock.t = 20.5
            apply!(s, SetAmount(:pale, 5.2u"kg"))
            @test length(history(s)) == 6
            undo!(s)
            @test !isdirty(s)                                   # the saved state is intact
        end

        # arrow fields merge by field; moves of a node merge
        s = history_session(; clock)
        clock.t = 30.0
        apply!(s, SetArrowField(:kettle, :wort, 1, :time, 61u"minute"))
        apply!(s, SetArrowField(:kettle, :wort, 1, :time, 62u"minute"))
        apply!(s, SetArrowField(:kettle, :wort, 1, :stand, 10u"minute"))
        @test length(history(s)) == 2
        apply!(s, MoveNode(:kettle, [1, 1]))
        apply!(s, MoveNode(:kettle, [1, 2]))
        apply!(s, SetView(:kettle, "position", [1, 3]))
        @test length(history(s)) == 3
        undo!(s)
        @test nodeview(quiver(s), :kettle)["position"] == [1.0, 2.0]
        @test mergekey(RemoveNode(:kettle)) === nothing
        @test mergekey(SetAmount(:pale, 1u"kg")) == mergekey(SetAmount(:pale, 2u"kg"))
        @test mergekey(SetAmount(:pale, 1u"kg")) != mergekey(SetIngredient(:pale, pale))

        # an amount and an ingredient set in quick succession stay two steps, so that redo
        # gives both (a merged step is redone by its last command alone)
        s = history_session(; clock)
        clock.t = 40.0
        apply!(s, SetAmount(:pale, 4.8u"kg"))
        mo = Fermentable("Maris Otter"; yield = 81u"percent", color = 3u"°L")
        apply!(s, SetIngredient(:pale, mo))
        apply!(s, SetTemperature(:strike_water, 72u"°C"))
        apply!(s, SetAmount(:strike_water, 17u"L"))
        @test length(history(s)) == 4
        edited = state(s)
        foreach(_ -> undo!(s), 1:4)
        foreach(_ -> redo!(s), 1:4)
        @test state(s) == edited && amount(s, :pale) ≈ 4.8u"kg"
    end

    @testset "Saved marker" begin
        mktempdir() do dir
            file = joinpath(dir, "bitter.quiver.json")
            save!(Session(single_batch()), file)
            s = open_session(file; history = History(; clock = FakeClock(0.0), merge_window = 0))
            @test !isdirty(s)
            apply!(s, SetAmount(:pale, 4.6u"kg"))
            @test isdirty(s)
            undo!(s)
            @test !isdirty(s)                                   # back to the saved state
            redo!(s)
            @test isdirty(s)
            save!(s)
            @test !isdirty(s) && history(s)[end].saved
            undo!(s)
            @test isdirty(s)
            apply!(s, SetAmount(:crystal, 0.4u"kg"))            # the saved state is lost
            undo!(s)
            @test isdirty(s)
            # changing back by hand is a new state: dirty, as editors do
            redo!(s)
            apply!(s, SetAmount(:crystal, 0.3u"kg"))
            @test isdirty(s)
            # transactions and layout edits count
            save!(s)
            apply!(s, MoveNode(:kettle, [0, 0]))
            @test isdirty(s)
            undo!(s)
            @test !isdirty(s)
        end
        # never saved: dirty
        @test isdirty(Session(single_batch()))
        @test isdirty(import_recipe(joinpath(DATA, "RRSummerBitter.json")))
    end

    @testset "Bounded history" begin
        mktempdir() do dir
            file = joinpath(dir, "bitter.quiver.json")
            save!(Session(single_batch()), file)
            s = open_session(file; history = History(; limit = 3, merge_window = 0))
            for m in 4.6:0.1:5.0
                apply!(s, SetAmount(:pale, m * u"kg"))
            end
            @test length(history(s)) == 3
            @test [h.description for h in history(s)][1] == "Set :pale to 4.8 kg"
            while canundo(s)
                undo!(s)
            end
            @test amount(s, :pale) ≈ 4.7u"kg"
            @test isdirty(s)                                    # the saved state was dropped
        end
        @test_throws ArgumentError History(; limit = 0)
    end

    @testset "Random sequences of edits, undos, redos and saves" begin
        # a random edit of the quiver of `s`: often refused, which must change nothing
        function random_edit(rng, s)
            q = quiver(s)
            ns = nodes(q)
            lots = [n for n in ns if !iszero(q[n].initial)]
            arrows_ = arrows(q)
            k = rand(rng, 1:11)
            n = rand(rng, ns)
            if k == 1 && !isempty(lots)
                l = rand(rng, lots)
                x = q[l].initial
                isempty(solids(x)) ? SetAmount(l, volume(x) * (0.8 + 0.4rand(rng))) :
                    only(solids(x)).amount isa Real ? SetAmount(l, rand(rng, 1:3)) :
                    SetAmount(l, only(solids(x)).amount * (0.8 + 0.4rand(rng)))
            elseif k == 2
                SetView(n, "color", rand(rng, ["#aa0000", "#00aa00", nothing]))
            elseif k == 3
                MoveNode(n, rand(rng, 0:5, 2))
            elseif k == 4
                RenameNode(n, Symbol(n, "_", rand(rng, 1:9)))
            elseif k == 5
                AddNode(Symbol(:stage, rand(rng, 1:99)); vessel = rand(rng, [nothing, :kettle]))
            elseif k == 6
                Connect(n => rand(rng, ns))
            elseif k == 7 && !isempty(arrows_)
                (src, dst, _) = rand(rng, arrows_)
                RemoveArrow(src, dst, rand(rng, 1:length(q[src => dst])))
            elseif k == 8
                RemoveNode(n)
            elseif k == 9
                Equip(:kettle, rand(rng, [nothing, Vessel(evaporation = 5u"L/hr"), Vessel(dead_space = 0.5u"L")]))
            elseif k == 10
                ts = [(src, dst) for (src, dst, a) in arrows_ if a isa Transfer]
                isempty(ts) ? MoveNode(n, [0, 0]) :
                    ((src, dst) = rand(rng, ts); SetArrowField(src, dst, 1, :duration, rand(rng, 0:10) * u"minute"))
            else
                SetVessel(n, rand(rng, [nothing, :kettle, :fermentor]))
            end
        end

        for seed in 1:4
            rng = Xoshiro(seed)
            mktempdir() do dir
                file = joinpath(dir, "q.json")
                save!(batch_session(), file)
                s = open_session(file; history = History(; merge_window = 0))
                # the model: the states of the history, the current one, the saved one
                states, pos, saved = [state(s)], 1, 1
                for _ in 1:120
                    r = rand(rng)
                    if r < 0.55
                        before = state(s)
                        try
                            apply!(s, random_edit(rng, s))
                        catch e
                            e isa CommandError || rethrow()
                            @test state(s) == before
                            continue
                        end
                        states = push!(states[1:pos], state(s))
                        pos += 1
                        saved > pos - 1 && (saved = 0)       # dropped with the redo stack
                    elseif r < 0.8
                        undo!(s) === nothing || (pos -= 1)
                    elseif r < 0.95
                        redo!(s) === nothing || (pos += 1)
                    else
                        save!(s)
                        saved = pos
                    end
                    @test state(s) == states[pos]
                    @test uptodate(s)
                    @test isdirty(s) == (saved != pos)
                    @test canundo(s) == (pos > 1) && canredo(s) == (pos < length(states))
                end
            end
        end
    end
end
